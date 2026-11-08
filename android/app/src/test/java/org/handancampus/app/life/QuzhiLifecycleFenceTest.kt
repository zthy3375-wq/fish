package org.handancampus.app.life

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class QuzhiLifecycleFenceTest {
    private fun cancelled(work: () -> Unit) {
        try { work(); fail("Expected stale/cancelled operation to be fenced") }
        catch (_: QuzhiLifecycleCancelled) { }
    }

    @Test fun oldRefreshCannotResurrectSessionAfterNewInstanceLogout() {
        val fence = QuzhiLifecycleFence()
        val old = fence.admit()
        var vault: String? = "old-session"
        val refreshResult = fence.owned(old) { vault }
        val replacement = fence.admit()
        fence.owned(replacement) { vault = null }
        cancelled { fence.owned(old) { vault = refreshResult } }
        assertNull(vault)
        // A delayed destruction of the old plugin must not dispose the replacement.
        fence.dispose(old)
        fence.owned(replacement) { vault = "new-session" }
        assertEquals("new-session", vault)
    }

    @Test fun destructionBlocksPendingRefreshAndLoginCommit() {
        val fence = QuzhiLifecycleFence()
        val owner = fence.admit()
        val attempt = QuzhiLifecycleFence.Attempt(owner)
        fence.dispose(owner)
        cancelled { fence.owned(owner) { fail("refresh wrote after destruction") } }
        cancelled { fence.commit(attempt) { fail("login wrote after destruction") } }
    }

    @Test fun cancellationBlocksLoginButLeavesCurrentOwnerUsable() {
        val fence = QuzhiLifecycleFence()
        val owner = fence.admit()
        val attempt = QuzhiLifecycleFence.Attempt(owner)
        fence.cancel(attempt)
        cancelled { fence.commit(attempt) { fail("cancelled login wrote") } }
        assertEquals("snapshot", fence.owned(owner) { "snapshot" })
        assertEquals("new login", fence.commit(QuzhiLifecycleFence.Attempt(owner)) { "new login" })
    }

    @Test fun admissionWaitsForEntireVaultMutation() {
        val fence = QuzhiLifecycleFence()
        val old = fence.admit()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val admissionStarted = CountDownLatch(1)
        val admitted = CountDownLatch(1)
        var vault = "before"
        val writer = thread {
            fence.owned(old) {
                entered.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                vault = "old-write"
            }
        }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val replacement = thread {
            admissionStarted.countDown()
            val next = fence.admit()
            fence.owned(next) { vault = "new-write" }
            admitted.countDown()
        }
        try {
            assertTrue(admissionStarted.await(5, TimeUnit.SECONDS))
            assertFalse(admitted.await(100, TimeUnit.MILLISECONDS))
        } finally { release.countDown() }
        writer.join(5000); replacement.join(5000)
        assertFalse(writer.isAlive); assertFalse(replacement.isAlive)
        assertEquals("new-write", vault)
    }

    @Test fun smsCooldownSurvivesCancelReopenAndNewPluginIncludingTimeouts() {
        val fence = QuzhiLifecycleFence()
        val first = fence.admit()
        assertEquals(0L, fence.reserveSms(first, "phone-a", 1000))
        val attempt = QuzhiLifecycleFence.Attempt(first)
        fence.cancel(attempt)
        assertEquals(60L, fence.reserveSms(first, "phone-a", 1001))
        val replacement = fence.admit()
        assertEquals(59L, fence.reserveSms(replacement, "phone-a", 2000))
        assertEquals(0L, fence.reserveSms(replacement, "phone-b", 2000))
        assertEquals(0L, fence.reserveSms(replacement, "phone-a", 61000))
        cancelled { fence.reserveSms(first, "phone-a", 61000) }
    }
}
