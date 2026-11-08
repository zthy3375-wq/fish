package org.handancampus.app.life

import org.json.JSONObject

internal object QuzhiRefresh {
    fun execute(source: JSONObject, requestedMonth: String, request: (String, Map<String,String>) -> Any?, now: () -> Long): JSONObject {
        val month = QuzhiProtocol.month(requestedMonth)
        val state = JSONObject(source.toString())
        val session = state.optJSONObject("session") ?: throw QuzhiFailure("AUTH")
        val auth = QuzhiProtocol.auth(session)
        val snapshot = state.optJSONObject("snapshot") ?: JSONObject().also { state.put("snapshot", it) }
        val issues = JSONObject()
        fun fetch(part: String, work: () -> Unit) {
            if (state.optBoolean("expired", false)) { issues.put(part, "AUTH"); return }
            try { work() } catch (e: Exception) {
                val reason = (e as? QuzhiFailure)?.kind ?: "NETWORK"
                issues.put(part, reason)
                if (reason == "AUTH") state.put("expired", true)
            }
        }
        fetch("wallet") {
            val wallet = QuzhiProtocol.wallet(request("account/wallet", auth))
            snapshot.put("wallet", wallet).put("walletUpdatedAt", now())
        }
        if (snapshot.optString("school").isBlank()) fetch("school") {
            val data = request("project/info/triple", auth) as? JSONObject ?: throw QuzhiFailure("FORMAT")
            val name = QuzhiProtocol.text(data, "projectName")
            if (name.isBlank()) throw QuzhiFailure("FORMAT")
            snapshot.put("school", name)
        }
        fetch("bills") {
            val bills = QuzhiProtocol.bills(request("order/query/account/bill/list", auth + mapOf("month" to month, "billRequestType" to "2")))
            snapshot.put("bills", bills.getJSONArray("items")).put("billsTruncated", bills.getBoolean("truncated"))
                .put("billsMonth", month).put("billsUpdatedAt", now())
        }
        snapshot.put("issues", issues)
        return state
    }
}
