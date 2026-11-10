package org.handancampus.app.life

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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

    @PluginMethod fun openEmbedded(call: PluginCall) {
        val provider = try {
            require(call.data.keys().asSequence().toSet() == setOf("provider"))
            ParcelWebPolicy.provider(call.getString("provider"))
        } catch (_: Exception) { call.reject("请选择淘宝或拼多多", "INVALID_PROVIDER"); return }
        val host = activity
        if (destroyed || host == null) { call.reject("页面已关闭", "CANCELLED"); return }
        host.runOnUiThread {
            if (destroyed || host.isFinishing || host.isDestroyed) {
                call.reject("页面已关闭", "CANCELLED")
            } else try {
                host.startActivity(Intent(host, ParcelWebActivity::class.java).putExtra("provider", provider))
                call.resolve(JSObject().put("provider", provider).put("status", "opened"))
            } catch (_: Exception) { call.reject("暂时无法打开取件页面", "UNAVAILABLE") }
        }
    }

    @PluginMethod fun open(call: PluginCall) {
        val target = try {
            ParcelShortcutContract.target(call.getString("provider"), call.data.keys().asSequence().toSet())
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
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(target.uri))
                    .addCategory(Intent.CATEGORY_BROWSABLE)
                    .setPackage(target.packageName)
                val manager = currentActivity.packageManager
                val host = object : ParcelLaunchHost {
                    override fun isActive() = !destroyed && !currentActivity.isFinishing && !currentActivity.isDestroyed
                    @Suppress("DEPRECATION")
                    override fun isInstalled(target: ParcelShortcutTarget): Boolean = try {
                        manager.getApplicationInfo(target.packageName, 0)
                        true
                    } catch (_: PackageManager.NameNotFoundException) { false }
                    @Suppress("DEPRECATION")
                    override fun canOpen(target: ParcelShortcutTarget): Boolean {
                        val info = manager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo
                        return info != null && info.packageName == target.packageName && info.exported &&
                            info.enabled && info.applicationInfo.enabled
                    }
                    override fun open(target: ParcelShortcutTarget) { currentActivity.startActivity(intent) }
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
