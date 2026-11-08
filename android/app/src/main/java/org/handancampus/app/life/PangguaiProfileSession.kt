package org.handancampus.app.life

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.WebStorage
import android.webkit.WebView
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewFeature

/** Owns only :pangguai_official's separate WebView directory. Never used to clear the main profile. */
object PangguaiProfileSession {
    private val lifecycle = PangguaiProfileLifecycle()
    private val handler = Handler(Looper.getMainLooper())
    private val observers = linkedSetOf<(PangguaiProfilePhase) -> Unit>()
    private var suffixAttempted = false
    private var suffixConfigured = false
    private var preferences: SharedPreferences? = null
    private data class OwnedView(val token: Long, val dispose: () -> Unit)
    private var ownedView: OwnedView? = null
    private const val PENDING_RESET = "reset_pending"
    var hasCompletedReset = false
        private set
    val phase: PangguaiProfilePhase get() = lifecycle.phase
    val canReset: Boolean get() = lifecycle.canReset

    /** Called once in Application.attachBaseContext, before any android.webkit API or provider starts. */
    fun configureDataDirectory(context: Context) {
        if (suffixAttempted) return
        suffixAttempted = true
        if (Build.VERSION.SDK_INT < 28 || !PangguaiProfileLifecycle.isolationEligible(
                Build.VERSION.SDK_INT, Application.getProcessName(), context.packageName)) return
        try {
            WebView.setDataDirectorySuffix(PangguaiProfileLifecycle.DATA_SUFFIX)
            suffixConfigured = true
        } catch (_: Exception) {
            // Never fall back to the main/shared profile if another initializer touched WebKit first.
            suffixConfigured = false
        }
    }

    fun initialize(context: Context) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (phase != PangguaiProfilePhase.UNINITIALIZED) return
        if (!suffixConfigured) { lifecycle.initialize(false); return }
        val supported = try {
            WebView.setWebContentsDebuggingEnabled(false)
            WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)
        } catch (_: Exception) { false }
        if (!supported) { lifecycle.initialize(false); return }
        val pending: Boolean
        try {
            preferences = context.getSharedPreferences("pangguai_isolated_browser", Context.MODE_PRIVATE)
            pending = preferences!!.getBoolean(PENDING_RESET, false)
        } catch (_: Exception) {
            // Unknown pending state must never become READY on the next Activity instance.
            lifecycle.initialize(supported = true, markerReadable = false)
            return
        }
        lifecycle.initialize(true)
        // Process death during reset cannot reopen the old session: retry deletion before any page load.
        if (pending) reset()
    }

    fun claimView(): Long? {
        val token = if (ownedView == null) lifecycle.claimView() else null
        if (token != null) hasCompletedReset = false
        return token
    }
    fun ownsView(token: Long): Boolean = lifecycle.ownsView(token)

    fun registerView(token: Long, dispose: () -> Unit) {
        check(lifecycle.ownsView(token) && ownedView == null)
        ownedView = OwnedView(token, dispose)
    }

    /** Retain the sole disposal reference on failure; never rely on an Activity UI observer for ownership. */
    private fun disposeOwnedView(): Boolean {
        val owner = ownedView ?: return true
        return try {
            owner.dispose()
            ownedView = null
            lifecycle.releaseView(owner.token)
            true
        } catch (_: Exception) { false }
    }

    fun releaseView(token: Long) {
        val owner = ownedView
        if (owner == null) { lifecycle.releaseView(token); return }
        if (owner.token != token) return
        if (!disposeOwnedView()) {
            val reset = lifecycle.beginReset()
            if (reset != null) {
                try { preferences?.edit()?.putBoolean(PENDING_RESET, true)?.commit() } catch (_: Exception) { }
                lifecycle.failReset(reset) // Retain owner and quarantine this process; do not attempt concurrent cleanup.
                publish()
            }
        }
    }

    fun observe(observer: (PangguaiProfilePhase) -> Unit) { observers.add(observer); observer(phase) }
    fun removeObserver(observer: (PangguaiProfilePhase) -> Unit) { observers.remove(observer) }

    private fun publish() {
        observers.toList().forEach { observer -> try { observer(phase) } catch (_: Exception) { } }
    }

    fun reset() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (!suffixConfigured) return
        val store = preferences ?: return
        val token = lifecycle.beginReset() ?: return
        hasCompletedReset = false
        val marked = try { store.edit().putBoolean(PENDING_RESET, true).commit() } catch (_: Exception) { false }
        val detached = disposeOwnedView() // Mandatory disposal before the non-atomic deletion, not an observer side effect.
        publish()
        if (!detached) {
            lifecycle.failReset(token) // A view may still be alive; quarantine until this process restarts.
            publish()
            return
        }
        if (!marked) {
            lifecycle.failBeforeDispatch(token)
            publish()
            return
        }
        val timeout = Runnable {
            lifecycle.failReset(token)
            publish()
        }
        handler.postDelayed(timeout, 30000)
        try {
            // AndroidX 1.13+ completion covers cookies, cache, JavaScript storage and installed service workers.
            // Feature support and the dedicated data directory were established before any view was allowed.
            WebStorageCompat.deleteBrowsingData(WebStorage.getInstance(), Runnable {
                handler.removeCallbacks(timeout)
                // A timeout does not cancel the platform operation. A late callback only permits a deliberate retry.
                val recorded = lifecycle.isResetting(token) && try {
                    store.edit().putBoolean(PENDING_RESET, false).commit()
                } catch (_: Exception) { false }
                hasCompletedReset = lifecycle.completeReset(token, recorded)
                publish()
            })
        } catch (_: Exception) {
            handler.removeCallbacks(timeout)
            lifecycle.failReset(token)
            // Dispatch outcome may be uncertain: never overlap a new deletion in this process.
            publish()
        }
    }
}
