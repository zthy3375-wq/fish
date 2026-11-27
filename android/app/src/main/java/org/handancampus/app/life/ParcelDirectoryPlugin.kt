package org.handancampus.app.life

import android.content.Intent
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "ParcelDirectory")
class ParcelDirectoryPlugin : Plugin() {
    @PluginMethod fun open(call: PluginCall) {
        val current = activity
        if (current == null) {
            call.reject("暂时无法打开取件联调")
            return
        }
        current.runOnUiThread {
            if (current.isFinishing || current.isDestroyed) call.reject("暂时无法打开取件联调")
            else {
                try {
                    current.startActivity(Intent(current, ParcelDirectoryActivity::class.java))
                    call.resolve()
                } catch (_: Exception) {
                    call.reject("暂时无法打开校园取件")
                }
            }
        }
    }
}
