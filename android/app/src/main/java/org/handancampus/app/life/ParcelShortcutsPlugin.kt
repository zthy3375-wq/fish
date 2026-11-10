package org.handancampus.app.life

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name = "ParcelShortcuts")
class ParcelShortcutsPlugin : Plugin() {
    private val busy = AtomicBoolean(false)
    @Volatile private var destroyed = false

    @PluginMethod fun open(call: PluginCall) {
        val target = try {
            ParcelShortcutContract.target(call.getString("provider"), call.data.keys().asSequence().toSet(), call.getString("mode"))
        } catch (_: Exception) {
            call.reject("只支持淘宝或拼多多出库码入口", "INVALID_PROVIDER")
            return
        }
        if (!busy.compareAndSet(false, true)) {
            call.reject("正在打开官方 App，请稍候", "BUSY")
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            busy.set(false)
            resolve(call, target, ParcelLaunchStatus.CANCELLED)
            return
        }
        currentActivity.runOnUiThread {
            try {
                val launcher = ParcelAndroidLauncher(currentActivity)
                val host = object : ParcelLaunchHost {
                    override fun isActive() = !destroyed && !currentActivity.isFinishing && !currentActivity.isDestroyed
                    override fun open(target: ParcelShortcutTarget, route: ParcelLaunchRoute) = launcher.open(target, route)
                }
                resolve(call, target, ParcelShortcutContract.launch(target, host))
            } catch (_: Exception) {
                resolve(call, target, ParcelLaunchStatus.UNAVAILABLE)
            } finally { busy.set(false) }
        }
    }

    private fun resolve(call: PluginCall, target: ParcelShortcutTarget, status: ParcelLaunchStatus) {
        call.resolve(JSObject().put("provider", target.provider).put("status", status.value))
    }

    override fun handleOnDestroy() {
        destroyed = true
        super.handleOnDestroy()
    }
}
