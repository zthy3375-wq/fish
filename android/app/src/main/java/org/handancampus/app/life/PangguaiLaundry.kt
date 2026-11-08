package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

/** Native-only transaction coordinator. No credentials or SDK parameters cross the JS bridge. */
internal class PangguaiLaundry(
    private val request:(String,Map<String,String>)->Any?,
    private val persist:(JSONObject)->Unit,
    private val now:()->Long = {System.currentTimeMillis()},
    private val pause:(Long)->Unit = {Thread.sleep(it)},
    private val alive:()->Unit = {},
    private val alipay:(String)->Unit = {}
) {
    companion object {
        val paths=setOf("trade/preview/v4","payChannelRoute/prePay","trade/check_device_status","machine/sync",
            "trade/create","pay/unify/pay","pay/unify/prePay","order/pay_status","machine/device_is_start",
            "order/detail","payChannelRoute/againPay","order/cancel")
        private fun text(o:JSONObject,k:String)=PangguaiProtocol.text(o,k)
        private fun req(o:JSONObject,k:String)=PangguaiProtocol.required(o,k)
        private fun obj(v:Any?)=v as? JSONObject ?: throw PangguaiFailure("FORMAT")
        private fun yes(o:JSONObject,k:String)=text(o,k) in setOf("true","1")
        private fun price(v:Any?):String {
            val s=PangguaiProtocol.money(v) ?: throw PangguaiFailure("PRICE")
            if(BigDecimal(s).scale()>2)throw PangguaiFailure("PRICE")
            return s
        }
        private fun samePrice(a:String,b:String)=BigDecimal(a).compareTo(BigDecimal(b))==0
        private fun items(d:String,s:String)=JSONArray().put(JSONObject().put("goodsId",d).put("skuId",s)
            .put("amount","1").put("num","1").put("soldType","1")).toString()
        private fun timestamp(value:String):Long?=runCatching {LocalDateTime.parse(value,DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
            .atZone(ZoneId.of("Asia/Shanghai")).toInstant().toEpochMilli()}.getOrNull()
        fun view(session:JSONObject?):JSONObject? {
            if(session==null)return null
            val result=JSONObject()
            listOf("id","deviceId","deviceName","program","amount","phase","orderId","orderNo","updatedAt","expectedEnd","finishedAt","error","paySent").forEach {
                if(session.has(it))result.put(it,session.get(it))
            }
            return result
        }
    }
    private fun post(path:String,fields:Map<String,String> = emptyMap()):Any? {alive();return request(path,fields)}
    private fun save(s:JSONObject){alive();persist(JSONObject(s.toString()))}
    private fun channels(value:Any?):JSONArray {
        val rows=value as? JSONArray ?: throw PangguaiFailure("FORMAT");val out=JSONArray()
        for(i in 0 until rows.length()) {
            val r=rows.getJSONObject(i);val method=text(r,"method")
            if(method !in setOf("2","13"))continue
            out.put(JSONObject().put("id",method).put("name",text(r,"methodName").take(40).ifBlank {if(method=="2")"余额支付" else "支付宝"})
                .put("available",yes(r,"useStatus") && text(r,"needOpenFlag") in setOf("false","0"))
                .put("reason",text(r,"notUseRemark").take(120)))
        }
        return out
    }
    fun quote(device:JSONObject,skuId:String):JSONObject {
        if(text(device,"category")!="00"||text(device,"payment")!="before"||text(device,"isBluetooth")!="0"||text(device,"issue").isNotBlank())throw PangguaiFailure("DEVICE")
        val skus=device.getJSONArray("skus")
        val sku=(0 until skus.length()).map{skus.getJSONObject(it)}.singleOrNull{text(it,"id")==skuId&&it.optBoolean("available")} ?: throw PangguaiFailure("DEVICE")
        val data=obj(post("trade/preview/v4",mapOf("items" to items(req(device,"id"),skuId),"promotions" to "[]","forbiddenPromotions" to "[]","isAutoSelectPromotion" to "0")))
        val rows=data.optJSONArray("items") ?: throw PangguaiFailure("FORMAT")
        if(rows.length()!=1||text(rows.getJSONObject(0),"goodsId")!=text(device,"id")||text(rows.getJSONObject(0),"skuId")!=skuId)throw PangguaiFailure("DEVICE")
        val amount=price(data.opt("realPrice"))
        val methods=channels(post("payChannelRoute/prePay",mapOf("imei" to req(device,"imei"),"goodsId" to req(device,"id"),"hitAd" to "0","payPrice" to amount,"useTicket" to "0","shopId" to req(device,"routeShopId"),"combineOrderStatus" to "false","confirmSelectedStatus" to "false")))
        return JSONObject().put("id",UUID.randomUUID().toString()).put("expiresAt",now()+60_000).put("deviceId",req(device,"id"))
            .put("deviceName",req(device,"name")).put("skuId",skuId).put("program",text(sku,"name")).put("amount",amount).put("channels",methods)
    }
    private fun ready(deviceId:String) {
        val check=obj(post("trade/check_device_status",mapOf("goodsId" to deviceId)))
        if(!yes(check,"health"))throw PangguaiFailure("DEVICE_BUSY")
        val msg=req(check,"msgId")
        repeat(8){if(post("machine/sync",mapOf("msgId" to msg))==true)return;pause(750)}
        throw PangguaiFailure("DEVICE_BUSY")
    }
    private fun allowed(q:JSONObject,method:String) {
        if(now()>q.getLong("expiresAt"))throw PangguaiFailure("QUOTE_EXPIRED")
        val rows=q.getJSONArray("channels")
        if((0 until rows.length()).none{text(rows.getJSONObject(it),"id")==method&&rows.getJSONObject(it).optBoolean("available")})throw PangguaiFailure("PAY_CHANNEL")
    }
    fun start(device:JSONObject,q:JSONObject,method:String,previous:JSONObject?):JSONObject {
        if(previous!=null&&text(previous,"phase") !in setOf("completed","closed","refunded"))throw PangguaiFailure("ORDER_ACTIVE")
        allowed(q,method)
        if(req(q,"deviceId")!=req(device,"id"))throw PangguaiFailure("DEVICE")
        val fresh=quote(device,req(q,"skuId"));allowed(fresh,method)
        if(!samePrice(req(q,"amount"),req(fresh,"amount")))throw PangguaiFailure("PRICE_CHANGED")
        ready(req(device,"id"))
        val before=obj(post("order/list",mapOf("page" to "1","pageSize" to "20"))).optJSONArray("items") ?: throw PangguaiFailure("FORMAT")
        val known=JSONArray();for(i in 0 until before.length())known.put(req(before.getJSONObject(i),"id"))
        val s=JSONObject().put("knownOrders",known).put("createSentAt",now()).put("id",UUID.randomUUID().toString()).put("deviceId",req(device,"id"))
            .put("deviceName",req(device,"name")).put("skuId",req(q,"skuId")).put("program",text(q,"program"))
            .put("shopId",req(device,"shopId")).put("amount",req(q,"amount")).put("phase","creating").put("paySent",false).put("updatedAt",now())
        // A durable intent precedes the HTTP mutation. An unknown create result never triggers a second create.
        save(s)
        try {
            val created=obj(post("trade/create",mapOf("items" to items(req(device,"id"),req(q,"skuId")),"promotions" to "[]")))
            s.put("orderNo",req(created,"tradeNo")).put("orderId",req(created,"orderId")).put("phase","pending");save(s)
            read(s)
            if(text(s,"phase")!="pending")return s
            if(!samePrice(req(s,"amount"),req(q,"amount")))throw PangguaiFailure("PRICE_CHANGED")
            pay(s,method)
            return s
        } catch(e:Exception) {s.put("error",(e as? PangguaiFailure)?.kind ?: "NETWORK");save(s);throw e}
    }
    private fun read(s:JSONObject) {
        val data=obj(post("order/detail",mapOf("orderNo" to req(s,"orderNo"))))
        val rows=data.optJSONArray("tradeOrderItem") ?: data.optJSONArray("lineItems") ?: throw PangguaiFailure("FORMAT")
        if(text(data,"orderNo")!=text(s,"orderNo")||text(data,"id")!=text(s,"orderId")||rows.length()!=1||
            text(rows.getJSONObject(0),"goodsId")!=text(s,"deviceId")||text(rows.getJSONObject(0),"skuId")!=text(s,"skuId"))throw PangguaiFailure("ORDER_MISMATCH")
        val phase=when(text(data,"orderStatus")){"0"->if(s.optBoolean("paySent"))"checking" else "pending";"1"->"closed";"2"->"paid";"3"->"completed";"4"->"refunding";"5"->"refunded";else->"unknown"}
        // A stale pending response must not erase previously confirmed payment/start.
        if(!(phase in setOf("pending","checking") && text(s,"phase") in setOf("paid","running","completed")))s.put("phase",phase)
        s.put("amount",price(data.opt("payPrice"))).put("updatedAt",now());s.remove("error")
        listOf("completeTime" to "expectedEnd","finishTime" to "finishedAt").forEach{(from,to)->timestamp(text(data,from))?.let{s.put(to,it)}}
        save(s)
    }
    private fun recover(s:JSONObject) {
        val known=s.optJSONArray("knownOrders") ?: throw PangguaiFailure("CREATE_UNKNOWN")
        val ids=(0 until known.length()).map{known.getString(it)}.toSet()
        val rows=obj(post("order/list",mapOf("page" to "1","pageSize" to "20"))).optJSONArray("items") ?: throw PangguaiFailure("FORMAT")
        val sent=s.optLong("createSentAt",0)
        val matches=(0 until rows.length()).map{rows.getJSONObject(it)}.filter{row->
            val items=row.optJSONArray("tradeOrderItem") ?: row.optJSONArray("lineItems")
            val created=timestamp(text(row,"createTime"))
            text(row,"id").isNotBlank() && text(row,"id") !in ids && text(row,"orderNo").isNotBlank() &&
                items?.length()==1 && text(items.getJSONObject(0),"goodsId")==text(s,"deviceId") &&
                text(items.getJSONObject(0),"skuId")==text(s,"skuId") && created!=null && sent>0 && created in (sent-5000)..(sent+120000)
        }
        if(matches.size!=1)throw PangguaiFailure("CREATE_UNKNOWN")
        val candidate=JSONObject(s.toString()).put("orderId",req(matches.single(),"id")).put("orderNo",req(matches.single(),"orderNo"))
        read(candidate) // Bind identity via order/detail before adopting a recovered list item. Never pays.
        candidate.keys().forEach{key->s.put(key,candidate.get(key))}
    }
    fun poll(source:JSONObject):JSONObject {
        val s=JSONObject(source.toString())
        if(text(s,"orderNo").isBlank())recover(s)
        try {
            read(s)
            if(text(s,"phase") in setOf("checking","pending","paid","running")) {
                val method=text(s,"method")
                if(text(s,"phase") in setOf("checking","pending")&&method in setOf("2","13")&&post("order/pay_status",mapOf("orderNo" to req(s,"orderNo"),"payType" to method))==true)s.put("phase","paid")
                if(text(s,"phase") in setOf("paid","running")&&post("machine/device_is_start",mapOf("orderNo" to req(s,"orderNo")))==true)s.put("phase","running")
                save(s)
            }
        }catch(e:Exception){s.put("error",(e as? PangguaiFailure)?.kind ?: "NETWORK");save(s);throw e}
        return s
    }
    fun quoteExisting(source:JSONObject):JSONObject {
        val s=poll(source)
        if(text(s,"phase")!="pending"||s.optBoolean("paySent"))throw PangguaiFailure("ORDER_ACTIVE")
        return JSONObject().put("id",UUID.randomUUID().toString()).put("sessionId",req(s,"id")).put("expiresAt",now()+60_000)
            .put("deviceName",text(s,"deviceName")).put("program",text(s,"program")).put("amount",req(s,"amount"))
            .put("channels",channels(post("payChannelRoute/againPay",mapOf("orderNo" to req(s,"orderNo"),"shopId" to req(s,"shopId"),"confirmSelectedStatus" to "false"))))
    }
    fun payExisting(source:JSONObject,q:JSONObject,method:String):JSONObject {
        allowed(q,method)
        if(text(source,"id")!=text(q,"sessionId"))throw PangguaiFailure("ORDER_MISMATCH")
        val s=poll(source)
        if(text(s,"phase")!="pending"||s.optBoolean("paySent"))throw PangguaiFailure("ORDER_ACTIVE")
        if(!samePrice(req(s,"amount"),req(q,"amount")))throw PangguaiFailure("PRICE_CHANGED")
        val latest=quoteExisting(s);allowed(latest,method)
        if(!samePrice(req(latest,"amount"),req(q,"amount")))throw PangguaiFailure("PRICE_CHANGED")
        ready(req(s,"deviceId"));pay(s,method);return s
    }
    private fun pay(s:JSONObject,method:String) {
        s.put("method",method).put("paySent",true).put("phase","checking");save(s)
        try {
            if(method=="2")post("pay/unify/pay",mapOf("orderNo" to req(s,"orderNo"),"payType" to method))
            else {
                val params=text(obj(post("pay/unify/prePay",mapOf("orderNo" to req(s,"orderNo"),"payType" to method))),"prepayParam")
                if(params.length !in 20..32768)throw PangguaiFailure("FORMAT")
                alive();alipay(params) // SDK return is not proof of payment. Always query the same server order.
            }
            val result=poll(s);result.keys().forEach{key->s.put(key,result.get(key))}
        }catch(e:Exception){s.put("error",(e as? PangguaiFailure)?.kind ?: "NETWORK");save(s);throw e}
    }
    fun cancel(source:JSONObject):JSONObject {
        val s=poll(source)
        // Cancellation is explicit and rechecks the server; the platform arbitrates a payment race.
        if(text(s,"phase") !in setOf("pending","checking"))throw PangguaiFailure("ORDER_ACTIVE")
        post("order/cancel",mapOf("orderId" to req(s,"orderId")))
        return poll(s)
    }
}
