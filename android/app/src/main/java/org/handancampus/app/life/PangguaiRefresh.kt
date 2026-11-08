package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject

internal object PangguaiRefresh {
    fun execute(source: JSONObject, request: (String,Map<String,String>,String)->Any?, now: ()->Long): JSONObject {
        val next=JSONObject(source.toString()); val token=next.optString("token")
        if(token.isBlank())throw PangguaiFailure("AUTH")
        val snapshot=next.optJSONObject("snapshot") ?: JSONObject().also { next.put("snapshot",it) }
        val issues=JSONObject()
        fun part(name:String, work:()->Unit) {
            if(next.optBoolean("expired")){issues.put(name,"AUTH");return}
            try{work()}catch(e:Exception){val kind=(e as? PangguaiFailure)?.kind ?: "NETWORK";issues.put(name,kind);if(kind in setOf("AUTH","ACCOUNT"))next.put("expired",true)}
        }
        part("wallet") {
            val data=request("user/info",emptyMap(),token)
            val identity=PangguaiProtocol.profile(data,next.getString("phone"))
            if(identity.getString("id")!=next.getString("id"))throw PangguaiFailure("ACCOUNT")
            val balance=PangguaiProtocol.money((data as JSONObject).opt("balance")) ?: throw PangguaiFailure("FORMAT")
            snapshot.put("balance",balance).put("walletUpdatedAt",now())
        }
        part("tickets") {
            val rows=JSONArray();val seen=mutableSetOf<String>();var total=0;var count=0
            for(page in 1..10) {
                val (items,expected)=PangguaiProtocol.tickets(request("tokenCoin/userTokenCoins",mapOf("page" to "$page","pageSize" to "20"),token))
                total=expected;count+=items.length()
                if(items.length()==0 && count<total)throw PangguaiFailure("PARTIAL")
                for(i in 0 until items.length()){val row=items.getJSONObject(i);if(!seen.add(row.getString("id")))throw PangguaiFailure("PARTIAL");rows.put(row)}
                if(count>=total)break
            }
            if(count<total)throw PangguaiFailure("PARTIAL")
            snapshot.put("tickets",rows).put("ticketsUpdatedAt",now())
        }
        part("orders") {
            val data=request("order/list",mapOf("page" to "1","pageSize" to "20"),token) as? JSONObject ?: throw PangguaiFailure("FORMAT")
            val items=data.optJSONArray("items") ?: throw PangguaiFailure("FORMAT");val rows=JSONArray()
            for(i in 0 until minOf(items.length(),20)){
                val row=items.getJSONObject(i)
                rows.put(JSONObject().put("id",PangguaiProtocol.required(row,"id"))
                    .put("name",PangguaiProtocol.text(row,"machineName").ifBlank { PangguaiProtocol.text(row,"goodsName") }.take(100))
                    .put("amount",PangguaiProtocol.money(row.opt("payPrice")) ?: JSONObject.NULL)
                    .put("status",PangguaiProtocol.orderStatus(row))
                    .put("time",PangguaiProtocol.text(row,"createTime").take(40)))
            }
            snapshot.put("orders",rows).put("ordersUpdatedAt",now())
        }
        snapshot.put("issues",issues)
        return next
    }
}
