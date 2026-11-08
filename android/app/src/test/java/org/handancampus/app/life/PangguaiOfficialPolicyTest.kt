package org.handancampus.app.life

import org.junit.Assert.*
import org.junit.Test

class PangguaiOfficialPolicyTest {
    @Test fun fixedRequestsHaveNoCallerSuppliedUrlOrAccount() {
        for (page in PangguaiPage.entries) {
            assertEquals(page, PangguaiOfficialPolicy.request(page.id, setOf("page")))
            assertTrue(PangguaiOfficialPolicy.allowsNavigation(page.url))
            assertFalse(page.url.contains("#"))
            assertFalse(page.url.contains("shopId="))
        }
        assertEquals("https://h5.qiekj.com/pages/wallet/myWallet/myWallet", PangguaiPage.WALLET.url)
        assertEquals("https://h5.qiekj.com/user/recharge/goldList/goldList", PangguaiPage.OPERATORS.url)
    }

    @Test fun rejectsUnknownEnumsAndExtraArguments() {
        for (id in listOf(null, "", "WALLET", "wallet ", "account", "https://h5.qiekj.com/login", "alipays://platformapi/startapp")) {
            assertThrows(IllegalArgumentException::class.java) { PangguaiOfficialPolicy.request(id, setOf("page")) }
        }
        for (keys in listOf(emptySet(), setOf("page", "url"), setOf("page", "token"), setOf("page", "shopId"), setOf("page", "redirect"))) {
            assertThrows(IllegalArgumentException::class.java) { PangguaiOfficialPolicy.request("wallet", keys) }
        }
    }

    @Test fun onlySourceVerifiedWalletLoginAndAccountPathsNavigate() {
        val paths = listOf("/", "/login", "/buyGold?shopId=fixture-only",
            "/pages/wallet/balanceDetail/balanceDetail", "/pages/wallet/walletList/walletList",
            "/pages/wallet/walletDetail/walletDetail", "/user/recharge/goldDetail/goldDetail",
            "/user/recharge/goldAgreement/goldAgreement", "/user/recharge/operatorInfo/operatorInfo",
            "/user/setting/setting", "/user/userInfo/userInfo", "/user/UserAgreement/UserAgreement",
            "/user/privacyPolicy/privacyPolicy", "/user/UserAgreement/userPrivacy/legalPrivacy")
        for (path in paths) assertTrue(path, PangguaiOfficialPolicy.allowsNavigation("https://h5.qiekj.com$path"))
        assertEquals("h5.qiekj.com", PangguaiOfficialPolicy.navigationHost("https://h5.qiekj.com:443/login"))
    }

    @Test fun providerHostAloneDoesNotAuthorizeAllTopLevelPaths() {
        for (path in listOf("/skip?NQT=example", "/pages/skip/skip", "/unknown", "/login/", "/%6cogin", "/foo/../login")) {
            assertFalse(path, PangguaiOfficialPolicy.allowsNavigation("https://h5.qiekj.com$path"))
        }
        assertFalse(PangguaiOfficialPolicy.allowsNavigation("https://userapi.qiekj.com/user/info"))
        assertFalse(PangguaiOfficialPolicy.allowsNavigation("https://static.qiekj.com/soft/user/QeUser.apk"))
    }

    @Test fun marketNavigationIsLimitedToTheTwoVerifiedPolicies() {
        for (id in listOf("34", "66")) assertTrue(PangguaiOfficialPolicy.allowsNavigation("https://market.qiekj.com/marketing?id=$id"))
        for (suffix in listOf("", "?id=1", "?id=34&id=66", "?id=%33%34", "?id=34&redirect=https://example.com", "?other=34")) {
            assertFalse(suffix, PangguaiOfficialPolicy.allowsNavigation("https://market.qiekj.com/marketing$suffix"))
        }
        assertFalse(PangguaiOfficialPolicy.allowsNavigation("https://market.qiekj.com/other?id=34"))
    }

    @Test fun blocksSpoofedOriginsAndUnsafeSchemes() {
        val bad = listOf<String?>(null, "", "http://h5.qiekj.com/login", "https://h5.qiekj.com.evil.test/login",
            "https://evil.test/login?h5.qiekj.com", "https://h5.qiekj.com@evil.test/login", "https://evil.test@h5.qiekj.com/login",
            "https://h5.qiekj.com:444/login", "https://h5.qiekj.com:0443/login", "https://h5.qiekj.com./login",
            "https://%68%35.qiekj.com/login", "https://h5.qiekj.com\\@evil.test/login", "https://h5.qiekj.com/login\n",
            "https://h5.qiekj.com/login\u007f", " https://h5.qiekj.com/login", "//h5.qiekj.com/login",
            "javascript:alert(1)", "file:///tmp/login", "content://h5.qiekj.com/login", "data:text/html,private",
            "intent://platformapi/startapp#Intent;scheme=alipays;end", PangguaiOfficialPolicy.ALIPAY_MINI_APP)
        for (url in bad) assertFalse(url ?: "null", PangguaiOfficialPolicy.allowsNavigation(url))
        assertFalse(PangguaiOfficialPolicy.allowsNavigation("https://h5.qiekj.com/login?value=" + "x".repeat(16384)))
    }

    @Test fun resourcesUseASmallerVerifiedHttpsListWithoutTopLevelPrivileges() {
        val urls = listOf("https://h5.qiekj.com/js/app.js", "https://static.qiekj.com/logo.png",
            "https://userapi.qiekj.com/user/info", "https://market.qiekj.com/assets/app.js",
            "https://cstaticdun.126.net/load.min.js", "https://cstaticdun1.126.net/load.min.js",
            "https://cstaticdun-v6.126.net/load.min.js", "https://c.dun.163.com/api/v2/getconf",
            "https://c.dun.163yun.com/api/v2/getconf", "https://c-v6.dun.163.com/api/v2/getconf",
            "https://ac.dun.163.com/v3/d", "https://ac.dun.163yun.com/v3/d", "https://ac-v6.dun.163yun.com/v3/d")
        for (url in urls) {
            assertTrue(url, PangguaiOfficialPolicy.allowsResource(url, false))
            assertFalse(url, PangguaiOfficialPolicy.allowsResource(url, true))
        }
        for (url in listOf("https://unverified.test/captcha.js", "http://static.qiekj.com/logo.png",
            "https://static.qiekj.com.evil.test/a", "https://user:password@userapi.qiekj.com/user/info",
            "file:///tmp/a", "content://local/a", "https://127.0.0.1/a")) {
            assertFalse(url, PangguaiOfficialPolicy.allowsResource(url, false))
        }
    }

    @Test fun externalEntryIsOnlyAFixedMiniAppHomeWithoutShopOrPaymentData() {
        assertEquals("com.eg.android.AlipayGphone", PangguaiOfficialPolicy.ALIPAY_PACKAGE)
        assertEquals("alipays://platformapi/startapp?appId=2018072460764274", PangguaiOfficialPolicy.ALIPAY_MINI_APP)
        assertFalse(PangguaiOfficialPolicy.ALIPAY_MINI_APP.contains("shopId"))
        assertFalse(PangguaiOfficialPolicy.ALIPAY_MINI_APP.contains("amount"))
    }
}
