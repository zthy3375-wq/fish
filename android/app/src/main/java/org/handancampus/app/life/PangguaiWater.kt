package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.util.UUID

/** Metered after-pay water sessions. Durable command intents prevent replay after lost responses. */
internal class PangguaiWater(
    private val request:(String,Map<String,String>)->Any?,
    private val persist:(JSONObject)->Unit,
    private val now:()->Long={System.currentTimeMillis()},
    private val alive:()->Unit={}
) {
    companion object {
        val paths=setOf("payChannelRoute/afterPay","payChannelRoute/addUserAfterPayChannel","goods/water/unlock",
            "machine/msg/sync","goods/water/sync","goods/endWater","order/afterPay/creating","order/sync")
        val terminal=setOf("settled","ended_zero","closed_unknown")
        private fun text(o:JSONObject,k:String)=PangguaiProtocol.text(o,k)
        private fun req(o:JSONObject,k:String)=PangguaiProtocol.required(o,k)
        private fun obj(v:Any?)=v as? JSONObject ?: throw PangguaiFailure("FORMAT")
        private fun yes(o:JSONObject,k:String)=text(o,k) in setOf("true","1")
        private fun money(v:Any?)=PangguaiProtocol.money(v)
        private fun promotions():String {
            val rows=JSONArray()
            for(type in listOf("-6","-7","-8"))rows.put(JSONObject().put("assetId","0").put("oldPromotionId",if(type=="-8")"0" else "")
                .put("orgId","0").put("promotionId","0").put("promotionType",type))
            return rows.toString()
        }
        fun view(s:JSONObject?):JSONObject? {
            if(s==null)return null
            val out=JSONObject()
            listOf("id","deviceId","deviceName","outlet","feature","paymentName","phase","orderNo","updatedAt","startedAt","endedAt","amount","remoteEnd","error","endSent","endBasis").forEach{k->if(s.has(k))out.put(k,s.get(k))}
            return out
        }
    }
    private fun post(path:String,fields:Map<String,String> = emptyMap()):Any?{alive();return request(path,fields)}
    private fun save(s:JSONObject){alive();persist(JSONObject(s.toString()))}
    private fun reading(skuId:String):JSONObject? {
        val value=post("goods/water/sync",mapOf("skuId" to skuId))
        return if(value==null||value==JSONObject.NULL)null else obj(value)
    }
    fun prepare(device:JSONObject,skuId:String):JSONObject {
        if(text(device,"category")!="04")throw PangguaiFailure("DEVICE")
        val id=req(device,"id")
        val details=obj(post("goods/normal/details",mapOf("goodsId" to id)))
        if(text(details,"goodsId")!=id||text(details,"categoryCode")!="04"||text(details,"payment")!="after"||text(details,"isBluetooth")!="0")throw PangguaiFailure("DEVICE")
        if(text(details,"deviceErrorMsg").isNotBlank())throw PangguaiFailure("DEVICE_BUSY")
        val rows=post("goods/normal/skus",mapOf("goodsId" to id)) as? JSONArray ?: throw PangguaiFailure("FORMAT")
        val sku=(0 until rows.length()).map{rows.getJSONObject(it)}.singleOrNull{text(it,"skuId")==skuId&&yes(it,"scanAvailable")&&text(it,"stockState")=="1"} ?: throw PangguaiFailure("DEVICE_BUSY")
        val channels=post("payChannelRoute/afterPay",mapOf("imei" to req(details,"imei"),"useTicket" to "0","shopId" to req(device,"routeShopId"),"goodsCategory" to "04")) as? JSONArray ?: throw PangguaiFailure("FORMAT")
        val channel=(0 until channels.length()).map{channels.getJSONObject(it)}.firstOrNull{text(it,"method")=="15"}
        val canStart=channel!=null&&yes(channel,"useStatus")&&text(channel,"needOpenFlag") in setOf("false","0")
        return JSONObject().put("id",UUID.randomUUID().toString()).put("expiresAt",now()+60_000).put("deviceId",id).put("skuId",skuId)
            .put("deviceName",req(details,"name")).put("outlet",text(sku,"name").take(100)).put("feature",text(sku,"feature").take(300))
            .put("price",money(sku.opt("price")) ?: JSONObject.NULL).put("remoteEnd",yes(details,"supportAppUserFinish"))
            .put("paymentName",channel?.let{text(it,"methodName").take(50)}?.ifBlank{"支付宝免密"} ?: "支付宝免密")
            .put("canStart",canStart).put("reason",when{channel==null->"设备未返回支付宝免密渠道";yes(channel,"needOpenFlag")->"请先在支付宝胖乖小程序开通本账户的免密付款";!canStart->text(channel,"notUseRemark").take(150).ifBlank{"付款方式暂不可用，请在官方端核对"};else->""})
    }
    fun start(device:JSONObject,quote:JSONObject,previous:JSONObject?):JSONObject {
        if(previous!=null&&text(previous,"phase") !in terminal)throw PangguaiFailure("WATER_ACTIVE")
        if(now()>quote.getLong("expiresAt"))throw PangguaiFailure("QUOTE_EXPIRED")
        if(req(quote,"deviceId")!=req(device,"id"))throw PangguaiFailure("DEVICE")
        if(!quote.optBoolean("canStart"))throw PangguaiFailure("WATER_CHANNEL")
        val fresh=prepare(device,req(quote,"skuId"))
        if(!fresh.optBoolean("canStart"))throw PangguaiFailure("WATER_CHANNEL")
        if(text(fresh,"price")!=text(quote,"price")||text(fresh,"feature")!=text(quote,"feature")||text(fresh,"outlet")!=text(quote,"outlet"))throw PangguaiFailure("PRICE_CHANGED")
        val before=reading(req(quote,"skuId"))
        if(before!=null&&text(before,"workStatus")=="2")throw PangguaiFailure("DEVICE_BUSY")
        // Explicit confirmation selects the already available payment method; it does not sign an agreement.
        post("payChannelRoute/addUserAfterPayChannel",mapOf("method" to "15"))
        val s=JSONObject().put("id",UUID.randomUUID().toString()).put("deviceId",req(device,"id")).put("skuId",req(quote,"skuId"))
            .put("deviceName",req(fresh,"deviceName")).put("outlet",text(fresh,"outlet")).put("feature",text(fresh,"feature"))
            .put("paymentName",text(fresh,"paymentName")).put("remoteEnd",fresh.optBoolean("remoteEnd")).put("phase","starting").put("updatedAt",now())
        save(s)
        try {
            val result=obj(post("goods/water/unlock",mapOf("skuId" to req(s,"skuId"),"promotions" to promotions())))
            // Keep the order number as soon as present, even if the optional command acknowledgement is missing.
            s.put("orderNo",req(result,"orderNo")).put("msgId",text(result,"msgId"));save(s)
            return poll(s)
        }catch(e:Exception){s.put("error",(e as? PangguaiFailure)?.kind ?: "NETWORK");save(s);throw e}
    }
    private fun bill(s:JSONObject):Boolean {
        val data=obj(post("order/detail",mapOf("orderNo" to req(s,"orderNo"))))
        if(text(data,"orderNo")!=text(s,"orderNo"))throw PangguaiFailure("ORDER_MISMATCH")
        val rows=data.optJSONArray("tradeOrderItem") ?: data.optJSONArray("lineItems") ?: throw PangguaiFailure("FORMAT")
        if(rows.length()!=1||text(rows.getJSONObject(0),"goodsId")!=text(s,"deviceId")||text(rows.getJSONObject(0),"skuId")!=text(s,"skuId"))throw PangguaiFailure("ORDER_MISMATCH")
        val id=req(data,"id")
        if(s.has("orderId")&&text(s,"orderId")!=id)throw PangguaiFailure("ORDER_MISMATCH")
        s.put("orderId",id)
        if(text(data,"orderStatus") in setOf("2","3")) {
            val paid=money(data.opt("payPrice")) ?: throw PangguaiFailure("FORMAT")
            s.put("amount",paid).put("billConfirmed",true).put("updatedAt",now())
            if(s.optBoolean("deviceEnded")){s.put("phase","settled");s.remove("error")}
            save(s);return true
        }
        save(s);return false
    }
    private fun settle(s:JSONObject) {
        // Start confirmation includes settlement for this metered session. Each command is sent at most once.
        if(!s.optBoolean("afterPaySent")) {
            s.put("afterPaySent",true).put("phase","settling");save(s)
            val created=obj(post("order/afterPay/creating",mapOf("orderNo" to req(s,"orderNo"))))
            if(text(created,"orderNo")!=text(s,"orderNo"))throw PangguaiFailure("ORDER_MISMATCH")
            s.put("orderId",req(created,"orderId"));save(s)
        }
        if(!s.has("orderId")){bill(s);if(!s.has("orderId"))return}
        if(text(s,"phase")=="settled"||bill(s))return
        if(!s.optBoolean("settleSent")) {
            s.put("settleSent",true).put("phase","settling");save(s)
            val result=obj(post("order/sync",mapOf("orderNo" to req(s,"orderNo"),"payType" to "0")))
            if(text(result,"code")!="0")throw PangguaiFailure("WATER_BILL")
        }
        bill(s)
    }
    fun poll(source:JSONObject):JSONObject {
        val s=JSONObject(source.toString())
        if(text(s,"phase") in terminal)return s
        try {
            if(text(s,"orderNo").isBlank())throw PangguaiFailure("WATER_UNKNOWN")
            if(text(s,"phase") in setOf("ended","settling")){settle(s);return s}
            if(text(s,"msgId").isNotBlank()&&!s.optBoolean("commandChecked")) {
                val message=post("machine/msg/sync",mapOf("msgId" to req(s,"msgId"))) as? JSONObject
                if(message!=null&&text(message,"state")=="OK"&&text(message,"code")=="0")s.put("commandChecked",true)
            }
            val reading=reading(req(s,"skuId"))
            if(reading==null){
                s.put("emptyReads",s.optInt("emptyReads")+1)
                // Observed platform variant: a used session disappears after physical settlement.
                if(s.has("startedAt")&&s.optInt("emptyReads")>=2){
                    s.put("deviceEnded",true).put("endBasis","session_closed").put("phase","ended").put("endedAt",now());s.remove("error");save(s);settle(s)
                }else{s.put("error","WATER_WAIT");save(s);runCatching{bill(s)}}
                return s
            }
            s.put("emptyReads",0)
            if(text(reading,"identify")!=text(s,"orderNo")) {
                s.put("error","WATER_OWNERSHIP");save(s);runCatching{bill(s)};return s
            }
            when {
                text(reading,"status")=="5"&&text(reading,"workStatus")=="1"->{
                    s.put("phase","ended").put("endBasis","device_report").put("deviceEnded",true).put("endedAt",now());s.remove("error")
                    val zero=text(reading,"amount").toBigDecimalOrNull()?.compareTo(BigDecimal.ZERO)==0
                    if(zero)s.put("phase","ended_zero")
                    s.put("updatedAt",now());save(s)
                    if(!zero)settle(s)
                }
                text(reading,"status")=="1"&&text(reading,"workStatus")=="2"->{
                    s.put("phase",if(s.optBoolean("endSent"))"ending" else "using")
                    if(!s.has("startedAt"))s.put("startedAt",now())
                    s.put("updatedAt",now());s.remove("error");save(s)
                }
                else->{s.put("error","WATER_WAIT").put("updatedAt",now());save(s)}
            }
            return s
        }catch(e:Exception){s.put("error",(e as? PangguaiFailure)?.kind ?: "NETWORK");save(s);throw e}
    }
    fun end(source:JSONObject):JSONObject {
        val s=poll(source)
        if(text(s,"phase") in terminal||text(s,"phase") in setOf("ended","settling"))return s
        if(s.optBoolean("endSent"))return s
        if(text(s,"orderNo").isBlank())throw PangguaiFailure("WATER_UNKNOWN")
        // Never send an end command against a stale or different user's device session.
        val reading=obj(post("goods/water/sync",mapOf("skuId" to req(s,"skuId"))))
        if(text(reading,"identify")!=text(s,"orderNo"))throw PangguaiFailure("WATER_OWNERSHIP")
        if(text(reading,"status")!="1"||text(reading,"workStatus")!="2")throw PangguaiFailure("WATER_WAIT")
        val details=obj(post("goods/normal/details",mapOf("goodsId" to req(s,"deviceId"))))
        if(text(details,"goodsId")!=text(s,"deviceId")||text(details,"categoryCode")!="04")throw PangguaiFailure("DEVICE")
        s.put("remoteEnd",yes(details,"supportAppUserFinish"));save(s)
        if(!s.optBoolean("remoteEnd"))throw PangguaiFailure("WATER_PHYSICAL_END")
        s.put("endSent",true).put("phase","ending");save(s)
        try {
            if(post("goods/endWater",mapOf("goodsId" to req(s,"deviceId")))!=true)throw PangguaiFailure("WATER_PHYSICAL_END")
            return poll(s)
        }catch(e:Exception){s.put("error",(e as? PangguaiFailure)?.kind ?: "NETWORK");save(s);throw e}
    }
    /** Explicit recovery only after user reports using the physical settlement button. Never sends commands. */
    fun confirmPhysicalEnd(source:JSONObject):JSONObject {
        val s=JSONObject(source.toString())
        if(text(s,"orderNo").isNotBlank())return poll(s)
        val reading=reading(req(s,"skuId"))
        if(reading!=null&&(text(reading,"status")!="5"||text(reading,"workStatus")!="1"))throw PangguaiFailure("WATER_WAIT")
        s.put("phase","closed_unknown").put("updatedAt",now()).put("error","WATER_BILL_UNKNOWN");save(s);return s
    }
}
