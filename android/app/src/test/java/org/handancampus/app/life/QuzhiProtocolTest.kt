package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class QuzhiProtocolTest {
    private fun rejected(kind: String, action: () -> Unit) {
        try { action(); fail("Expected $kind") } catch (e: QuzhiFailure) { assertEquals(kind, e.kind) }
    }
    private fun session() = QuzhiProtocol.session(JSONObject("""{"loginCode":"synthetic-session","userId":12,"userAccount":{"accountId":34,"projectId":56}}"""), "13800000000")
    private fun prior() = JSONObject().put("session", session()).put("snapshot", JSONObject("""{"school":"人工测试学校","wallet":{"total":"12.34"},"walletUpdatedAt":1,"billsMonth":"2026-10","billsUpdatedAt":2,"bills":[{"id":"old","amount":"1.20"}]}"""))

    @Test fun loginShapesAreNormalizedWithoutExportingCredentials() {
        val nested = session()
        assertEquals("34", nested.getString("accountId"))
        assertEquals("56", nested.getString("projectId"))
        assertEquals("138****0000", QuzhiProtocol.maskedPhone(nested))
        assertEquals("13800000000", QuzhiProtocol.auth(nested)["telPhone"])
        val flat = QuzhiProtocol.session(JSONObject("""{"loginCode":"synthetic","v3UserId":"12","projectId":"56"}"""), "13800000000")
        assertEquals("12", flat.getString("userId"))
        rejected("FORMAT") { QuzhiProtocol.session(JSONObject("""{"loginCode":"synthetic","userId":12}"""), "13800000000") }
    }
    @Test fun credentialsAndMonthRejectInvalidInputs() {
        assertEquals("DEB882CF99", QuzhiProtocol.password("password"))
        assertEquals(32, QuzhiProtocol.smsSecret("13800000000").length)
        rejected("PHONE") { QuzhiProtocol.phone("13800000000&projectId=1") }
        rejected("MONTH") { QuzhiProtocol.month("2026-13") }
        rejected("MONTH") { QuzhiProtocol.month("2026-11&foo=1") }
    }
    @Test fun walletPreservesUnknownFieldsAndZeroWithoutInventingTotals() {
        val wallet = QuzhiProtocol.wallet(JSONObject("""{"money":"0.00","accountRealMoney":0,"accountGivenMoney":"1.250"}"""))
        assertEquals("0", wallet.getString("total")); assertTrue(wallet.isNull("gift")); assertTrue(wallet.isNull("cash"))
        rejected("UNVERIFIED_UNITS") { QuzhiProtocol.wallet(JSONObject("""{"accountRealMoney":"3.5"}""")) }
        rejected("UNVERIFIED_UNITS") { QuzhiProtocol.wallet(JSONObject()) }
        rejected("FORMAT") { QuzhiProtocol.wallet(JSONObject("""{"money":"免费"}""")) }
    }
    @Test fun walletUnitsRequireExplicitFieldsAndAgreeWhenBothProvided() {
        assertEquals("12.345", QuzhiProtocol.wallet(JSONObject("""{"accountMoney":12345}""")).getString("total"))
        assertEquals("12.345", QuzhiProtocol.wallet(JSONObject("""{"money":"12.345","accountMoney":12345}""")).getString("total"))
        rejected("UNVERIFIED_UNITS") { QuzhiProtocol.wallet(JSONObject("""{"money":"12.34","accountMoney":12345}""")) }
        rejected("FORMAT") { QuzhiProtocol.wallet(JSONObject("""{"accountMoney":12.345}""")) }
        rejected("FORMAT") { QuzhiProtocol.wallet(JSONObject("""{"accountMoney":"9999999999999999"}""")) }
    }
    @Test fun ambiguousOrInvalidWalletNeverReplacesLastSuccessfulSnapshot() {
        for (response in listOf("{}", "{\"money\":null}", "{\"money\":\"invalid\"}", "{\"accountRealMoney\":12345}")) {
            val result = QuzhiRefresh.execute(prior(), "2026-11", { path, _ -> if (path == "account/wallet") JSONObject(response) else JSONArray() }, { 10 })
            val cached = result.getJSONObject("snapshot")
            assertEquals("12.34", cached.getJSONObject("wallet").getString("total"))
            assertEquals(1, cached.getLong("walletUpdatedAt"))
            assertTrue(cached.getJSONObject("issues").has("wallet"))
        }
    }
    @Test fun flatSessionsPreferTheV3LoginCodeWithoutChangingNestedSessions() {
        val flat = QuzhiProtocol.session(JSONObject("""{"loginCode":"legacy","v3LoginCode":"v3","userId":12,"projectId":56}"""), "13800000000")
        assertEquals("v3", flat.getString("loginCode"))
        val nested = QuzhiProtocol.session(JSONObject("""{"loginCode":"nested","v3LoginCode":"unused","userId":12,"userAccount":{"projectId":56}}"""), "13800000000")
        assertEquals("nested", nested.getString("loginCode"))
    }
    @Test fun onlyExplicitSuccessIsAcceptedAndAuthDoesNotHideSignatureFailures() {
        assertEquals(3, QuzhiProtocol.payload(JSONObject("""{"success":true,"errorCode":"0","data":3}""")))
        rejected("SERVICE") { QuzhiProtocol.payload(JSONObject("""{"success":true,"errorCode":9}""")) }
        rejected("AUTH") { QuzhiProtocol.payload(JSONObject("""{"success":false,"errorCode":2,"message":"登录已失效"}""")) }
        rejected("AUTH") { QuzhiProtocol.payload(JSONObject("""{"success":false,"errorCode":8,"message":"未获取到用户信息，请重新登录"}""")) }
        rejected("SERVICE") { QuzhiProtocol.payload(JSONObject("""{"success":false,"errorCode":2,"message":"签名过期，请重新登录"}""")) }
        rejected("VERIFY") { QuzhiProtocol.payload(JSONObject("""{"success":false,"errorCode":2,"message":"请求过于频繁"}""")) }
    }
    @Test fun billSchemaDriftIsNotAnEmptyMonth() {
        assertEquals(0, QuzhiProtocol.bills(JSONArray()).getJSONArray("items").length())
        rejected("FORMAT") { QuzhiProtocol.bills(JSONObject()) }
        rejected("FORMAT") { QuzhiProtocol.bills(JSONArray("""[{"differentShape":{}}]""")) }
        val bill = QuzhiProtocol.bills(JSONArray("""[{"consumeBillDTO":{"orderNo":123,"consumeMoney":"0.125","consumeDate":"2026-11-08 08:00","deviceDescription":"人工设备"}}]"""))
        assertEquals("0.125", bill.getJSONArray("items").getJSONObject(0).getString("amount"))
        val rows = JSONArray(); repeat(201) { rows.put(JSONObject().put("consumeBillDTO", JSONObject().put("orderNo", it))) }
        val bounded = QuzhiProtocol.bills(rows)
        assertTrue(bounded.getBoolean("truncated")); assertEquals(200, bounded.getJSONArray("items").length())
    }
    @Test fun networkFailureRetainsBalancesAndTheOriginalBillMonth() {
        val source = prior()
        val result = QuzhiRefresh.execute(source, "2026-11", { _, _ -> throw java.io.IOException() }, { 10 })
        val snapshot = result.getJSONObject("snapshot")
        assertEquals("12.34", snapshot.getJSONObject("wallet").getString("total"))
        assertEquals(1, snapshot.getLong("walletUpdatedAt"))
        assertEquals("2026-10", snapshot.getString("billsMonth"))
        assertEquals("NETWORK", snapshot.getJSONObject("issues").getString("bills"))
        assertFalse(source.getJSONObject("snapshot").has("issues"))
    }
    @Test fun partialRefreshPublishesOnlyTheSuccessfulModule() {
        val result = QuzhiRefresh.execute(prior(), "2026-11", { path, _ ->
            if (path == "account/wallet") JSONObject().put("money", "20") else JSONObject().put("unknown", true)
        }, { 10 })
        val snapshot = result.getJSONObject("snapshot")
        assertEquals("20", snapshot.getJSONObject("wallet").getString("total"))
        assertEquals(10, snapshot.getLong("walletUpdatedAt"))
        assertEquals("old", snapshot.getJSONArray("bills").getJSONObject(0).getString("id"))
        assertEquals("FORMAT", snapshot.getJSONObject("issues").getString("bills"))
    }
    @Test fun expiredSessionStopsFurtherRequestsAndRetainsPriorSnapshot() {
        var count = 0
        val result = QuzhiRefresh.execute(prior(), "2026-11", { _, _ -> count++; throw QuzhiFailure("AUTH") }, { 10 })
        assertEquals(1, count); assertTrue(result.getBoolean("expired"))
        assertEquals("12.34", result.getJSONObject("snapshot").getJSONObject("wallet").getString("total"))
    }
    @Test fun emptyConfirmedMonthReplacesOnlyBillsAndNeverAddsMoneyAfterRecharge() {
        val result = QuzhiRefresh.execute(prior(), "2026-11", { path, args ->
            if (path == "account/wallet") JSONObject().put("money", "12.34") else {
                assertEquals("2026-11", args["month"]); JSONArray()
            }
        }, { 10 })
        val snapshot = result.getJSONObject("snapshot")
        assertEquals("2026-11", snapshot.getString("billsMonth")); assertEquals(0, snapshot.getJSONArray("bills").length())
        assertEquals("12.34", snapshot.getJSONObject("wallet").getString("total"))
    }
}
