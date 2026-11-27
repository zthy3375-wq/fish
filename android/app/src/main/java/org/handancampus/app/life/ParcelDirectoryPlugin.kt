package org.handancampus.app.life

import android.content.Intent
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.BuildConfig

@CapacitorPlugin(name = "ParcelDirectory")
class ParcelDirectoryPlugin : Plugin() {
    @PluginMethod fun open(call: PluginCall) {
        if (!BuildConfig.DEBUG || !BuildConfig.PARCEL_PILOT) {
            call.reject("未开启取件联调")
            return
        }
        val current = activity
        if (current == null) {
            call.reject("暂时无法打开取件联调")
            return
        }
        current.runOnUiThread {
            if (current.isFinishing || current.isDestroyed) call.reject("暂时无法打开取件联调")
            else {
                current.startActivity(Intent(current, ParcelDirectoryActivity::class.java))
                call.resolve()
            }
        }
    }
}
