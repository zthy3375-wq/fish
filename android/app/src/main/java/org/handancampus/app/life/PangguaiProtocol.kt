package org.handancampus.app.life

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.math.BigDecimal
import java.security.MessageDigest

internal class PangguaiFailure(val kind: String) : Exception(kind)

/** Independently implemented from public protocol facts; sources in docs/V083-NATIVE-LIFE.md. */
internal object PangguaiProtocol {
    const val VERSION = "1.109.1"
    private const val CLIENT_SALT = "nFU9pbG8YQoAe1kFh+E7eyrdlSLglwEJeA0wwHB1j5o="
    val paths = setOf("common/sms/sendCode", "user/reg", "user/info", "user/astrict/list",
        "tokenCoin/userTokenCoins", "order/list", "goods/scan/v2", "goods/normal/details", "goods/normal/skus")
    fun text(obj: JSONObject, key: String): String = obj.opt(key)?.takeUnless { it == JSONObject.NULL }?.toString().orEmpty()
    fun required(obj: JSONObject, key: String) = text(obj,key).takeIf { it.isNotBlank() && it.length <= 256 } ?: throw PangguaiFailure("FORMAT")
    fun phone(raw: String): String = raw.trim().takeIf { it.matches(Regex("1[0-9]{10}")) } ?: throw PangguaiFailure("PHONE")
    fun money(raw: Any?): String? = raw?.takeUnless { it == JSONObject.NULL }?.toString()?.takeIf {
        it.matches(Regex("[0-9]{1,10}(\\.[0-9]{1,4})?"))
    }?.let { BigDecimal(it).stripTrailingZeros().toPlainString() }
    fun signature(path: String, token: String, timestamp: String): String {
        require(path in paths)
        val input = "appSecret=$CLIENT_SALT&channel=android_app&timestamp=$timestamp&token=$token&version=$VERSION&/$path"
        return MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
    fun payload(envelope: JSONObject): Any? {
        val code = text(envelope,"code")
        if (code !in setOf("0","200")) {
            val message = text(envelope,"msg") + text(envelope,"message")
            val kind = when {
                code in setOf("2","401") || Regex("未登[录陆]|登录.*(失效|过期)|token.*(invalid|expired|过期|无效)", RegexOption.IGNORE_CASE).containsMatchIn(message) -> "AUTH"
                Regex("验证码|验证|频繁|风控|captcha|risk",RegexOption.IGNORE_CASE).containsMatchIn(message) -> "VERIFY"
                else -> "SERVICE"
            }
            throw PangguaiFailure(kind)
        }
        return envelope.opt("data").takeUnless { it == JSONObject.NULL }
    }
    fun profile(data: Any?, expectedPhone: String? = null): JSONObject {
        val obj = data as? JSONObject ?: throw PangguaiFailure("FORMAT")
        val phone = phone(required(obj,"phone"))
        if (expectedPhone != null && phone != expectedPhone) throw PangguaiFailure("ACCOUNT")
        return JSONObject().put("id",required(obj,"id")).put("phone",phone)
            .put("balance",money(obj.opt("balance")) ?: JSONObject.NULL)
    }
    fun orderStatus(row:JSONObject):String = text(row,"orderStatusName").take(40).ifBlank {
        when(text(row,"orderStatus")){"0"->"待支付";"1"->"订单超时";"2"->"已支付";"3"->"已完成";else->"状态待核对"}
    }
    fun tickets(data: Any?): Pair<JSONArray, Int> {
        val obj = data as? JSONObject ?: throw PangguaiFailure("FORMAT")
        val items = obj.optJSONArray("items") ?: throw PangguaiFailure("FORMAT")
        val total = text(obj,"total").toIntOrNull()?.takeIf { it >= 0 } ?: throw PangguaiFailure("FORMAT")
        val result = JSONArray()
        for(i in 0 until items.length()) {
            val row = items.getJSONObject(i)
            result.put(JSONObject().put("id",required(row,"shopId")).put("name",required(row,"shopName"))
                .put("balance",money(row.opt("totalAmount")) ?: JSONObject.NULL)
                .put("principal",money(row.opt("principalAmount")) ?: JSONObject.NULL)
                .put("gift",money(row.opt("presentAmount")) ?: JSONObject.NULL))
        }
        return result to total
    }
    /** Decode once, never visit the scanned URL. No scan can create an order. */
    fun deviceCode(raw: String): Map<String,String> {
        if (raw.length !in 1..2048 || raw.any { it <= ' ' || it == '\\' }) throw PangguaiFailure("QR")
        val uri = try { URI(raw) } catch (_: Exception) { throw PangguaiFailure("QR") }
        if (uri.scheme !in setOf("http","https") || uri.host != "h5.qiekj.com" || uri.userInfo != null ||
            uri.port !in setOf(-1,443,80) || uri.path !in setOf("/skip","/pages/skip/skip")) throw PangguaiFailure("QR")
        val fields = (uri.rawQuery ?: "").split('&').filter { it.isNotEmpty() }.map {
            val parts = it.split('=',limit=2)
            if (parts.size != 2) throw PangguaiFailure("QR")
            try { URLDecoder.decode(parts[0],"UTF-8") to URLDecoder.decode(parts[1],"UTF-8") } catch (_: Exception) { throw PangguaiFailure("QR") }
        }
        if (fields.map { it.first }.distinct().size != fields.size) throw PangguaiFailure("QR")
        val selected = fields.filter { it.first in setOf("NQT","SN") }
        if (selected.size != 1 || fields.any { it.first.equals("IMEI",true) } || !selected[0].second.matches(Regex("[A-Za-z0-9_-]{4,128}"))) throw PangguaiFailure("QR")
        return mapOf(selected[0])
    }
    fun device(scan: JSONObject, detail: JSONObject, skus: JSONArray): JSONObject {
        val id = required(scan,"id"); val category = required(scan,"categoryCode")
        if (text(scan,"type") != "goods" || category !in setOf("00","04","08") ||
            text(detail,"goodsId") != id || text(detail,"categoryCode") != category) throw PangguaiFailure("DEVICE")
        val choices = JSONArray()
        for(i in 0 until minOf(skus.length(),40)) {
            val row = skus.getJSONObject(i)
            choices.put(JSONObject().put("id",required(row,"skuId")).put("name",text(row,"name").take(100))
                .put("price",money(row.opt("price")) ?: JSONObject.NULL).put("feature",text(row,"feature").take(200))
                .put("available",text(row,"scanAvailable") in setOf("true","1") && text(row,"stockState") == "1"))
        }
        return JSONObject().put("id",id).put("category",category).put("name",required(detail,"name"))
            .put("operator",text(detail,"orgName").take(100)).put("payment",text(detail,"payment"))
            .put("issue",text(detail,"deviceErrorMsg").take(150)).put("skus",choices)
    }
}
