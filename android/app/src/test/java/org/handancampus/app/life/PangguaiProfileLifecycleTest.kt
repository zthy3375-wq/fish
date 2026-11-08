package org.handancampus.app.life

import org.junit.Assert.*
import org.junit.Test

class PangguaiProfileLifecycleTest {
    @Test fun exactRuntimeProcessAndAndroid9AreMandatory() {
        assertTrue(PangguaiProfileLifecycle.isolationEligible(28, "org.example.test:pangguai_official", "org.example.test"))
        assertTrue(PangguaiProfileLifecycle.isolationEligible(35, "org.handancampus.app.life.v082:pangguai_official", "org.handancampus.app.life.v082"))
        assertFalse(PangguaiProfileLifecycle.isolationEligible(27, "org.example.test:pangguai_official", "org.example.test"))
        assertFalse(PangguaiProfileLifecycle.isolationEligible(35, "org.example.test", "org.example.test"))
        assertFalse(PangguaiProfileLifecycle.isolationEligible(35, "evil:pangguai_official", "org.example.test"))
        assertFalse(PangguaiProfileLifecycle.isolationEligible(35, null, "org.example.test"))
    }

    @Test fun unsupportedRuntimeCanNeverCreateAViewOrClearSharedStorage() {
        val lifecycle = PangguaiProfileLifecycle()
        assertNull(lifecycle.claimView())
        assertNull(lifecycle.beginReset())
        lifecycle.initialize(false)
        assertNull(lifecycle.claimView())
        assertNull(lifecycle.beginReset())
        assertEquals(PangguaiProfilePhase.UNSUPPORTED, lifecycle.phase)
    }

    @Test fun onlyOneViewCanOwnTheIsolatedProfile() {
        val lifecycle = PangguaiProfileLifecycle().apply { initialize(true) }
        val first = lifecycle.claimView()!!
        assertTrue(lifecycle.ownsView(first))
        assertNull(lifecycle.claimView())
        lifecycle.releaseView(first + 1)
        assertNull(lifecycle.claimView())
        lifecycle.releaseView(first)
        val next = lifecycle.claimView()!!
        assertFalse(lifecycle.ownsView(first))
        assertTrue(lifecycle.ownsView(next))
    }

    @Test fun resetFencesEveryOldViewAndBlocksReopenUntilCompletion() {
        val lifecycle = PangguaiProfileLifecycle().apply { initialize(true) }
        val view = lifecycle.claimView()!!
        val reset = lifecycle.beginReset()!!
        assertFalse(lifecycle.ownsView(view))
        assertNull(lifecycle.claimView())
        assertNull(lifecycle.beginReset())
        lifecycle.releaseView(view)
        assertEquals(PangguaiProfilePhase.CLEARING, lifecycle.phase)
        assertFalse(lifecycle.completeReset(reset - 1))
        assertTrue(lifecycle.completeReset(reset))
        assertNotNull(lifecycle.claimView())
    }

    @Test fun timeoutNeverPermitsReopenAndLateCompletionCannotReviveIt() {
        val lifecycle = PangguaiProfileLifecycle().apply { initialize(true) }
        val reset = lifecycle.beginReset()!!
        lifecycle.failReset(reset)
        assertEquals(PangguaiProfilePhase.BLOCKED, lifecycle.phase)
        assertNull(lifecycle.beginReset()) // Timed out does not cancel the outstanding platform deletion.
        assertFalse(lifecycle.completeReset(reset))
        assertNull(lifecycle.claimView())
        val retry = lifecycle.beginReset()!!
        assertFalse(lifecycle.completeReset(reset))
        assertNull(lifecycle.claimView())
        assertTrue(lifecycle.completeReset(retry))
        assertNotNull(lifecycle.claimView())
    }

    @Test fun failedPendingMarkerCommitDoesNotAllowAView() {
        val lifecycle = PangguaiProfileLifecycle().apply { initialize(true) }
        val reset = lifecycle.beginReset()!!
        assertFalse(lifecycle.completeReset(reset, recorded = false))
        assertNull(lifecycle.claimView())
        assertNotNull(lifecycle.beginReset()) // Previous operation actually completed; a deliberate retry is safe.
    }

    @Test fun pendingResetCanRunBeforeAnyNewPageLoads() {
        val lifecycle = PangguaiProfileLifecycle().apply { initialize(true) }
        val recovery = lifecycle.beginReset()!!
        assertNull(lifecycle.claimView())
        assertTrue(lifecycle.completeReset(recovery))
        val view = lifecycle.claimView()!!
        assertTrue(lifecycle.ownsView(view))
        assertFalse(lifecycle.completeReset(recovery))
    }

    @Test fun unreadablePendingMarkerCannotBecomeReadyOnLaterOpen() {
        val lifecycle = PangguaiProfileLifecycle()
        lifecycle.initialize(supported = true, markerReadable = false)
        assertEquals(PangguaiProfilePhase.UNSUPPORTED, lifecycle.phase)
        assertNull(lifecycle.claimView())
        assertNull(lifecycle.beginReset())
        assertThrows(IllegalStateException::class.java) { lifecycle.initialize(true) }
    }
}
