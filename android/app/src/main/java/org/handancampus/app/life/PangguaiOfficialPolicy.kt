package org.handancampus.app.life

import java.net.URI
import java.util.Locale

enum class PangguaiPage(val id: String, val url: String) {
    WALLET("wallet", "https://h5.qiekj.com/pages/wallet/myWallet/myWallet"),
    OPERATORS("operators", "https://h5.qiekj.com/user/recharge/goldList/goldList"),
    LOGIN("login", "https://h5.qiekj.com/login")
}

/** Browser policy only. This is not an authenticated API, account or payment bridge. */
object PangguaiOfficialPolicy {
    const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"
    const val ALIPAY_MINI_APP = "alipays://platformapi/startapp?appId=2018072460764274"
    private val pagePaths = setOf(
        "", "/", "/login", "/buyGold",
        "/pages/wallet/myWallet/myWallet", "/pages/wallet/balanceDetail/balanceDetail",
        "/pages/wallet/walletList/walletList", "/pages/wallet/walletDetail/walletDetail",
        "/user/recharge/goldList/goldList", "/user/recharge/goldDetail/goldDetail",
        "/user/recharge/goldAgreement/goldAgreement", "/user/recharge/operatorInfo/operatorInfo",
        "/user/UserAgreement/UserAgreement", "/user/UserAgreement/newUserAgreement",
        "/user/UserAgreement/userPrivacy/legalPrivacy", "/user/privacyPolicy/privacyPolicy",
        "/user/privacyPolicy/newPrivacyPolicy", "/user/setting/setting", "/user/userInfo/userInfo"
    )
    private val resourceHosts = setOf(
        "h5.qiekj.com", "static.qiekj.com", "userapi.qiekj.com", "market.qiekj.com",
        "cstaticdun.126.net", "cstaticdun1.126.net", "cstaticdun-v6.126.net",
        "c.dun.163.com", "c.dun.163yun.com", "c-v6.dun.163.com",
        "ac.dun.163.com", "ac.dun.163yun.com", "ac-v6.dun.163yun.com"
    )

    fun page(id: String?): PangguaiPage = PangguaiPage.entries.firstOrNull { it.id == id }
        ?: throw IllegalArgumentException("INVALID_PAGE")

    fun request(id: String?, argumentNames: Set<String>): PangguaiPage {
        require(argumentNames == setOf("page")) { "INVALID_PAGE" }
        return page(id)
    }

    /** Exact HTTPS hosts; never accept suffix matches, credentials, alternate ports or custom schemes. */
    private fun secureHost(raw: String?): String? = try {
        if (raw == null || raw.length > 16384 || raw.any { it <= ' ' || it == '\\' || it == '\u007f' }) null
        else {
            val uri = URI(raw)
            val host = uri.host?.lowercase(Locale.ROOT)
            if (!uri.scheme.equals("https", true) || uri.rawUserInfo != null || host == null ||
                (uri.port != -1 && uri.port != 443) ||
                uri.rawAuthority.lowercase(Locale.ROOT) !in setOf(host, "$host:443")) null
            else host
        }
    } catch (_: Exception) { null }

    fun navigationHost(raw: String?): String? {
        val host = secureHost(raw) ?: return null
        val uri = URI(raw!!)
        return host.takeIf {
            (host == "h5.qiekj.com" && uri.rawPath in pagePaths) ||
                (host == "market.qiekj.com" && uri.rawPath == "/marketing" && uri.rawQuery in setOf("id=34", "id=66"))
        }
    }
    fun allowsNavigation(raw: String?): Boolean = navigationHost(raw) != null

    /** Only verified HTTPS resource hosts. Unknown CAPTCHA/payment dependencies stay blocked until verified. */
    fun allowsResource(raw: String?, mainFrame: Boolean): Boolean =
        if (mainFrame) allowsNavigation(raw) else secureHost(raw) in resourceHosts
}
