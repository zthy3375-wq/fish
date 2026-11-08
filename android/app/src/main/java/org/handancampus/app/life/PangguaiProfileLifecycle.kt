package org.handancampus.app.life

enum class PangguaiProfilePhase { UNINITIALIZED, READY, IN_USE, CLEARING, BLOCKED, UNSUPPORTED }

/** Pure ownership/generation fence; contains no browser/account data. All callers are on the UI thread. */
class PangguaiProfileLifecycle {
    @Volatile var phase = PangguaiProfilePhase.UNINITIALIZED
        private set
    @Volatile private var generation = 0L
    @Volatile private var resetOutstanding = false
    val canReset: Boolean get() = !resetOutstanding && phase in setOf(PangguaiProfilePhase.READY, PangguaiProfilePhase.IN_USE, PangguaiProfilePhase.BLOCKED)

    fun initialize(supported: Boolean, markerReadable: Boolean = true) {
        check(phase == PangguaiProfilePhase.UNINITIALIZED)
        phase = if (supported && markerReadable) PangguaiProfilePhase.READY else PangguaiProfilePhase.UNSUPPORTED
    }

    fun claimView(): Long? {
        if (phase != PangguaiProfilePhase.READY) return null
        phase = PangguaiProfilePhase.IN_USE
        return ++generation
    }

    fun ownsView(token: Long): Boolean = phase == PangguaiProfilePhase.IN_USE && token == generation

    fun releaseView(token: Long) {
        if (ownsView(token)) phase = PangguaiProfilePhase.READY
    }

    fun beginReset(): Long? {
        if (!canReset) return null
        phase = PangguaiProfilePhase.CLEARING
        resetOutstanding = true
        return ++generation
    }

    fun isResetting(token: Long): Boolean = phase == PangguaiProfilePhase.CLEARING && token == generation

    fun completeReset(token: Long, recorded: Boolean = true): Boolean {
        if (token != generation || !resetOutstanding) return false
        resetOutstanding = false
        if (phase != PangguaiProfilePhase.CLEARING || !recorded) { phase = PangguaiProfilePhase.BLOCKED; return false }
        phase = PangguaiProfilePhase.READY
        return true
    }

    fun failReset(token: Long) {
        if (isResetting(token)) phase = PangguaiProfilePhase.BLOCKED
    }

    fun failBeforeDispatch(token: Long) {
        if (!isResetting(token)) return
        resetOutstanding = false
        phase = PangguaiProfilePhase.BLOCKED
    }

    companion object {
        const val PROCESS_SUFFIX = ":pangguai_official"
        const val DATA_SUFFIX = "pangguai_official"
        fun isolationEligible(sdk: Int, process: String?, packageName: String): Boolean =
            sdk >= 28 && process == packageName + PROCESS_SUFFIX
    }
}
