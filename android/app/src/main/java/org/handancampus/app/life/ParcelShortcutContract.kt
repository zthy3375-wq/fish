package org.handancampus.app.life

import java.util.concurrent.CancellationException

/** Fixed routing facts, not account access. See docs/V082-PARCEL-SHORTCUTS.md. */
data class ParcelShortcutTarget(val provider: String, val packageName: String, val uri: String)

enum class ParcelLaunchStatus(val value: String) {
    OPENED("opened"), NOT_INSTALLED("not_installed"), UNAVAILABLE("unavailable"), CANCELLED("cancelled")
}

interface ParcelLaunchHost {
    fun isActive(): Boolean
    fun isInstalled(target: ParcelShortcutTarget): Boolean
    fun canOpen(target: ParcelShortcutTarget): Boolean
    fun open(target: ParcelShortcutTarget)
}

object ParcelShortcutContract {
    /** Only a provider ID crosses the JS bridge. Destinations cannot be supplied or overridden. */
    fun target(provider: String?, argumentNames: Set<String>): ParcelShortcutTarget {
        require(argumentNames == setOf("provider")) { "INVALID_PROVIDER" }
        return when (provider) {
            "taobao" -> ParcelShortcutTarget("taobao", "com.taobao.taobao",
                "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code")
            "pinduoduo" -> ParcelShortcutTarget("pinduoduo", "com.xunmeng.pinduoduo",
                "pinduoduo://com.xunmeng.pinduoduo/mdkd/package?tab=ID_CODE")
            else -> throw IllegalArgumentException("INVALID_PROVIDER")
        }
    }

    /** OPENED only means Android accepted the launch. There is no pickup/identity-code callback. */
    fun launch(target: ParcelShortcutTarget, host: ParcelLaunchHost): ParcelLaunchStatus = try {
        when {
            !host.isActive() -> ParcelLaunchStatus.CANCELLED
            !host.isInstalled(target) -> ParcelLaunchStatus.NOT_INSTALLED
            !host.canOpen(target) -> ParcelLaunchStatus.UNAVAILABLE
            !host.isActive() -> ParcelLaunchStatus.CANCELLED
            else -> { host.open(target); ParcelLaunchStatus.OPENED }
        }
    } catch (_: CancellationException) {
        ParcelLaunchStatus.CANCELLED
    } catch (_: Exception) {
        // Never remove the target package, open a browser, or fall back to an unverified route.
        ParcelLaunchStatus.UNAVAILABLE
    }
}
