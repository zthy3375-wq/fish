package org.handancampus.app.life

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class ParcelShortcutContractTest {
    private val taobao = ParcelShortcutContract.target("taobao", setOf("provider"))
    private class Host : ParcelLaunchHost {
        var active = true
        var installed = true
        var supported = true
        var opens = 0
        var checked = 0
        var failure: Exception? = null
        var stopBeforeOpen = false
        override fun isActive() = active
        override fun isInstalled(target: ParcelShortcutTarget): Boolean { checked++; return installed }
        override fun canOpen(target: ParcelShortcutTarget): Boolean { if (stopBeforeOpen) active = false; return supported }
        override fun open(target: ParcelShortcutTarget) { failure?.let { throw it }; opens++ }
    }

    @Test fun targetsAreFixedAndPackageBound() {
        assertEquals("com.taobao.taobao", taobao.packageName)
        assertEquals("https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code", taobao.uri)
        val pdd = ParcelShortcutContract.target("pinduoduo", setOf("provider"))
        assertEquals("com.xunmeng.pinduoduo", pdd.packageName)
        assertEquals("pinduoduo://com.xunmeng.pinduoduo/mdkd/package?tab=ID_CODE", pdd.uri)
    }

    @Test fun rejectsUnknownIdsAndDestinationOverrides() {
        for (id in listOf(null, "", "TAOBAO", " taobao", "taobao ", "https://example.org", "javascript:alert(1)", "com.taobao.taobao")) {
            assertThrows(IllegalArgumentException::class.java) { ParcelShortcutContract.target(id, setOf("provider")) }
        }
        for (keys in listOf(emptySet(), setOf("uri"), setOf("provider", "uri"), setOf("provider", "package"), setOf("provider", "script"))) {
            assertThrows(IllegalArgumentException::class.java) { ParcelShortcutContract.target("taobao", keys) }
        }
    }

    @Test fun openedMeansOnlyOneDispatch() {
        val host = Host()
        assertEquals(ParcelLaunchStatus.OPENED, ParcelShortcutContract.launch(taobao, host))
        assertEquals(1, host.opens)
    }

    @Test fun missingAppDoesNotAttemptLaunch() {
        val host = Host().apply { installed = false }
        assertEquals(ParcelLaunchStatus.NOT_INSTALLED, ParcelShortcutContract.launch(taobao, host))
        assertEquals(0, host.opens)
    }

    @Test fun unsupportedRouteHasNoUnboundOrBrowserFallback() {
        val host = Host().apply { supported = false }
        assertEquals(ParcelLaunchStatus.UNAVAILABLE, ParcelShortcutContract.launch(taobao, host))
        assertEquals(0, host.opens)
    }

    @Test fun destroyedActivityCancelsBeforeInspectionOrOpen() {
        val host = Host().apply { active = false }
        assertEquals(ParcelLaunchStatus.CANCELLED, ParcelShortcutContract.launch(taobao, host))
        assertEquals(0, host.checked)
        assertEquals(0, host.opens)
    }

    @Test fun activityDisappearingDuringResolutionDoesNotLaunch() {
        val host = Host().apply { stopBeforeOpen = true }
        assertEquals(ParcelLaunchStatus.CANCELLED, ParcelShortcutContract.launch(taobao, host))
        assertEquals(0, host.opens)
    }

    @Test fun launchFailureAndCancellationHaveNoRetryOrSuccess() {
        for (failure in listOf(SecurityException("private payload"), IllegalStateException("route removed"))) {
            val host = Host().apply { this.failure = failure }
            assertEquals(ParcelLaunchStatus.UNAVAILABLE, ParcelShortcutContract.launch(taobao, host))
            assertEquals(0, host.opens)
        }
        val cancelled = Host().apply { failure = CancellationException() }
        assertEquals(ParcelLaunchStatus.CANCELLED, ParcelShortcutContract.launch(taobao, cancelled))
        assertEquals(0, cancelled.opens)
    }
}
