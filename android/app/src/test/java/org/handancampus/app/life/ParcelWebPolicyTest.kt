package org.handancampus.app.life

import org.junit.Assert.*
import org.junit.Test

class ParcelWebPolicyTest {
    @Test fun officialEntriesAreStrictAndProviderSpecific() {
        assertTrue(ParcelWebPolicy.isEntry("taobao", ParcelWebPolicy.TAOBAO_IDENTITY))
        assertTrue(ParcelWebPolicy.isEntry("pinduoduo", ParcelWebPolicy.PDD_ENTRY))
        assertFalse(ParcelWebPolicy.isEntry("taobao", ParcelWebPolicy.TAOBAO_PARCELS))
        assertFalse(ParcelWebPolicy.allows("pinduoduo", ParcelWebPolicy.TAOBAO_IDENTITY))
        assertFalse(ParcelWebPolicy.allows("taobao", ParcelWebPolicy.PDD_ENTRY))
    }
    @Test fun rejectsUntrustedHostsSchemesPortsAndAmbiguousAuthorities() {
        listOf("http://m.taobao.com/", "https://taobao.com.evil.test/", "https://eviltaobao.com/",
            "https://user@taobao.com/", "https://taobao.com:444/", "javascript:alert(1)",
            "file:///data/data/app", "https://taobao.com\\@evil.test/", "https://taobao.com/\n", "intent://taobao").forEach {
            assertFalse(it, ParcelWebPolicy.allows("taobao", it))
        }
        assertFalse(ParcelWebPolicy.allows("pinduoduo", "https://api.pinduoduo.com/"))
        assertFalse(ParcelWebPolicy.allows("pinduoduo", "https://m.pinduoduo.net.evil.test/"))
    }
    @Test fun authCanNavigateWithoutBeingMistakenForAnEntry() {
        assertTrue(ParcelWebPolicy.allows("taobao", "https://login.m.taobao.com/login.htm"))
        assertTrue(ParcelWebPolicy.allows("taobao", "https://passport.alipay.com/"))
        assertTrue(ParcelWebPolicy.allows("pinduoduo", "https://m.pinduoduo.net/login.html"))
        assertFalse(ParcelWebPolicy.isEntry("pinduoduo", "https://m.pinduoduo.net/login.html"))
        assertFalse(ParcelWebPolicy.isEntry("taobao", "https://evil.test" + java.net.URI(ParcelWebPolicy.TAOBAO_IDENTITY).path))
    }
    @Test(expected = IllegalArgumentException::class) fun arbitraryProviderCannotSelectUrl() { ParcelWebPolicy.provider("https://evil.test") }
}
