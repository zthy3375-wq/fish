package org.handancampus.app.life

import android.content.Intent
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name = "PangguaiOfficial")
class PangguaiOfficialPlugin : Plugin() {
    private val opening = AtomicBoolean(false)
    @Volatile private var destroyed = false

    @PluginMethod fun open(call: PluginCall) {
        val page = try {
            PangguaiOfficialPolicy.request(call.getString("page"), call.data.keys().asSequence().toSet())
        } catch (_: Exception) {
            call.reject("只支持胖乖官方钱包、运营商或登录页面", "INVALID_PAGE")
            return
        }
        if (!opening.compareAndSet(false, true)) {
            call.reject("正在打开胖乖官方页面", "BUSY")
            return
        }
        val host = activity
        if (host == null) { opening.set(false); resolve(call, page, "cancelled"); return }
        host.runOnUiThread {
            try {
                if (destroyed || host.isFinishing || host.isDestroyed) resolve(call, page, "cancelled")
                else {
                    val intent = Intent(host, PangguaiOfficialActivity::class.java)
                        .putExtra(PangguaiOfficialActivity.PAGE_EXTRA, page.id)
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    host.startActivity(intent)
                    // Only Android's acceptance of the request, never rendering/authentication/payment success.
                    resolve(call, page, "opened")
                }
            } catch (_: Exception) { resolve(call, page, "unavailable") }
            finally { opening.set(false) }
        }
    }

    private fun resolve(call: PluginCall, page: PangguaiPage, status: String) {
        call.resolve(JSObject().put("page", page.id).put("status", status))
    }

    override fun handleOnDestroy() { destroyed = true; super.handleOnDestroy() }
}
