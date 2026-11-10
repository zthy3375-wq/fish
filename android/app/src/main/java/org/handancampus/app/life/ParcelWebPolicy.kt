package org.handancampus.app.life

import java.net.URI

/** Fixed official routing facts; no URL, script or credential is accepted from the bridge. */
object ParcelWebPolicy {
    const val TAOBAO_IDENTITY = "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code"
    const val TAOBAO_PARCELS = "https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home"
    const val PDD_ENTRY = "https://m.pinduoduo.net/mdkd/package?tab=ID_CODE"
    fun provider(raw: String?): String {
        require(raw == "taobao" || raw == "pinduoduo")
        return raw!!
    }
    fun entry(provider: String) = if (this.provider(provider) == "taobao") TAOBAO_IDENTITY else PDD_ENTRY
    fun host(raw: String?): String? = try {
        require(raw != null && raw.length <= 8192 && raw.none { it.isWhitespace() || it.isISOControl() || it == '\\' })
        val u = URI(raw)
        require(u.scheme == "https" && u.rawUserInfo == null && (u.port == -1 || u.port == 443))
        u.host?.lowercase()
    } catch (_: Exception) { null }
    fun allows(provider: String, raw: String?): Boolean {
        val h = host(raw) ?: return false
        return when (provider) {
            "taobao" -> listOf("taobao.com", "tmall.com", "alipay.com", "cainiao.com", "alibaba.com")
                .any { h == it || h.endsWith(".$it") }
            "pinduoduo" -> h == "m.pinduoduo.net"
            else -> false
        }
    }
    fun isEntry(provider: String, raw: String?): Boolean = try {
        allows(provider, raw) && URI(raw).path == URI(entry(provider)).path && host(raw) == host(entry(provider))
    } catch (_: Exception) { false }
}
