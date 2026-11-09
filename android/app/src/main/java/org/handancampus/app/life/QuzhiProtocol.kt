package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.security.MessageDigest
import java.util.Locale

/** Protocol facts researched independently; no upstream implementation is bundled. */
internal class QuzhiFailure(val kind: String) : Exception(kind)

internal object QuzhiProtocol {
    const val BASE = "https://v3-api.china-qzxy.cn/"
    const val RECHARGE = "alipays://platformapi/startapp?appId=2018090661238647&page=pages%2Frecharge%2Frecharge"
    val common = mapOf("phoneSystem" to "android", "version" to "6.5.28")
    val paths = setOf("user/login", "user/verification/code/get", "user/registerAndLogin", "account/wallet", "project/info/triple", "order/query/account/bill/list", "account/useCode/new")

    fun text(value: JSONObject, key: String): String = when (val raw = value.opt(key)) {
        is String -> raw.trim().take(240)
        is Number -> raw.toString()
        else -> ""
    }
    fun phone(value: String): String = value.trim().also {
        if (!it.matches(Regex("1[3-9][0-9]{9}"))) throw QuzhiFailure("PHONE")
    }
    fun month(value: String): String = value.also {
        if (!it.matches(Regex("20[0-9]{2}-(0[1-9]|1[0-2])"))) throw QuzhiFailure("MONTH")
    }
    private fun md5(value: String) = MessageDigest.getInstance("MD5").digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it.toInt() and 255) }
    fun password(value: String): String {
        if (value.isEmpty() || value.length > 128) throw QuzhiFailure("PASSWORD")
        return md5(value).takeLast(10).uppercase(Locale.ROOT)
    }
    fun smsSecret(value: String): String {
        val p = phone(value)
        return md5(p.take(3) + p.takeLast(4) + "klcx")
    }
    fun payload(envelope: JSONObject): Any? {
        val code = text(envelope, "errorCode")
        if (envelope.optBoolean("success", false) && code == "0") return envelope.opt("data")
        val message = text(envelope, "message") + text(envelope, "errorMessage")
        if (!message.contains("签名") && (code == "401" || code == "403" ||
            Regex("未登[录陆]|请先登[录陆]|请重新登[录陆]|登录.{0,12}(过期|失效)|loginCode.{0,12}失效").containsMatchIn(message))) throw QuzhiFailure("AUTH")
        if (Regex("频繁|稍后|次数|验证码|验证失败").containsMatchIn(message)) throw QuzhiFailure("VERIFY")
        if (Regex("密码|账号不存在|用户不存在").containsMatchIn(message)) throw QuzhiFailure("CREDENTIALS")
        throw QuzhiFailure("SERVICE")
    }
    fun session(data: Any?, inputPhone: String): JSONObject {
        val obj = data as? JSONObject ?: throw QuzhiFailure("FORMAT")
        val nested = obj.optJSONObject("userAccount") ?: obj
        fun first(vararg candidates: String) = candidates.firstOrNull { it.isNotBlank() }.orEmpty()
        val loginCode = if (obj.optJSONObject("userAccount") != null) text(obj, "loginCode") else first(text(obj, "v3LoginCode"), text(obj, "loginCode"))
        val result = JSONObject().put("loginCode", loginCode)
            .put("userId", first(text(obj, "userId"), text(obj, "v3UserId"), text(nested, "userId")))
            .put("accountId", first(text(nested, "accountId"), text(obj, "accountId")))
            .put("projectId", first(text(nested, "projectId"), text(obj, "projectId")))
            .put("telephone", phone(inputPhone))
        if (listOf("loginCode", "userId", "projectId").any { text(result, it).isBlank() }) throw QuzhiFailure("FORMAT")
        return result
    }
    fun auth(session: JSONObject): Map<String, String> = common +
        listOf("loginCode", "userId", "accountId", "projectId", "telephone").associateWith { text(session, it) }
            .filterValues { it.isNotBlank() } + mapOf("telPhone" to text(session, "telephone"))

    private fun amount(value: JSONObject, key: String): Any {
        val raw = text(value, key)
        if (raw.isEmpty()) return JSONObject.NULL
        if (!raw.matches(Regex("-?[0-9]{1,12}(\\.[0-9]{1,6})?"))) throw QuzhiFailure("FORMAT")
        return BigDecimal(raw).stripTrailingZeros().toPlainString()
    }
    fun wallet(data: Any?): JSONObject {
        val obj = data as? JSONObject ?: throw QuzhiFailure("FORMAT")
        // The published clients disagree on component-field units. Never display them as yuan.
        val yuan = amount(obj, "money").takeUnless { it == JSONObject.NULL } as? String
        val milliRaw = text(obj, "accountMoney")
        val milli = if (milliRaw.isBlank()) null else {
            if (!milliRaw.matches(Regex("-?[0-9]{1,15}"))) throw QuzhiFailure("FORMAT")
            BigDecimal(milliRaw).movePointLeft(3).stripTrailingZeros().toPlainString()
        }
        if (yuan != null && milli != null && BigDecimal(yuan).compareTo(BigDecimal(milli)) != 0) throw QuzhiFailure("UNVERIFIED_UNITS")
        val total = yuan ?: milli ?: throw QuzhiFailure("UNVERIFIED_UNITS")
        return JSONObject().put("total", total).put("cash", JSONObject.NULL).put("gift", JSONObject.NULL)
    }
    fun bills(data: Any?): JSONObject {
        val array = data as? JSONArray ?: throw QuzhiFailure("FORMAT")
        val rows = JSONArray()
        for (i in 0 until minOf(array.length(), 200)) {
            val wrapper = array.optJSONObject(i) ?: throw QuzhiFailure("FORMAT")
            val bill = wrapper.optJSONObject("consumeBillDTO") ?: throw QuzhiFailure("FORMAT")
            rows.put(JSONObject().put("id", text(bill, "orderNo")).put("date", text(bill, "consumeDate"))
                .put("amount", amount(bill, "consumeMoney"))
                .put("description", text(bill, "deviceDescription").ifBlank { text(bill, "description") }.ifBlank { "用水消费" }))
        }
        return JSONObject().put("items", rows).put("truncated", array.length() > 200)
    }
    /** Read the complete server-supplied code only; never reconstruct it from a phone or suffix. */
    fun bathCode(data: Any?): JSONObject {
        val obj = data as? JSONObject ?: throw QuzhiFailure("FORMAT")
        val status = text(obj, "useCodeStatus")
        if (status != "0" && status != "1") throw QuzhiFailure("FORMAT")
        val value = text(obj, "useCode")
        if (value.isNotEmpty() && !value.matches(Regex("[0-9]{8}"))) throw QuzhiFailure("FORMAT")
        if (status == "1" && value.isEmpty()) throw QuzhiFailure("FORMAT")
        return JSONObject().put("enabled", status == "1")
            .put("code", if (value.isEmpty()) JSONObject.NULL else value)
    }
    fun maskedPhone(session: JSONObject): String = text(session, "telephone").let {
        if (it.length == 11) it.take(3) + "****" + it.takeLast(4) else "已连接账户"
    }
}
