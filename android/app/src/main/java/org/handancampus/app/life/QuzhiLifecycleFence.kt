package org.handancampus.app.life

/** One process-wide fence serializes ownership changes with vault access, never network I/O. */
internal class QuzhiLifecycleFence {
    class Owner internal constructor()
    class Attempt internal constructor(internal val owner: Owner) {
        internal var cancelled = false
    }
    private var current: Owner? = null
    private val smsNextAt = mutableMapOf<String, Long>()

    @Synchronized fun admit(): Owner = Owner().also { current = it }
    @Synchronized fun dispose(owner: Owner) { if (current === owner) current = null }
    @Synchronized fun isCurrent(owner: Owner): Boolean = current === owner
    @Synchronized fun <T> owned(owner: Owner, work: () -> T): T {
        if (current !== owner) throw QuzhiLifecycleCancelled()
        return work()
    }
    @Synchronized fun cancel(attempt: Attempt) { attempt.cancelled = true }
    @Synchronized fun <T> commit(attempt: Attempt, work: () -> T): T = owned(attempt.owner) {
        if (attempt.cancelled) throw QuzhiLifecycleCancelled()
        work()
    }
    /** Reserve before sending, including failures/timeouts; survives dialog and plugin recreation. */
    @Synchronized fun reserveSms(owner: Owner, phone: String, now: Long): Long = owned(owner) {
        smsNextAt.entries.removeAll { it.value <= now }
        val remaining = ((smsNextAt[phone] ?: now) - now + 999) / 1000
        if (remaining <= 0) smsNextAt[phone] = now + 60_000
        remaining.coerceAtLeast(0)
    }
}
internal class QuzhiLifecycleCancelled : Exception()
