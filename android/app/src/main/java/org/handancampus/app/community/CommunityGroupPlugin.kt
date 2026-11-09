package org.handancampus.app.community

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "CommunityGroup")
class CommunityGroupPlugin : Plugin() {
    // Fixed destination: callers cannot supply arbitrary links or clipboard content.
    @PluginMethod fun open(call: PluginCall) {
        val host = activity
        if (host == null || host.isFinishing || host.isDestroyed) {
            call.resolve(JSObject().put("opened", false))
            return
        }
        host.runOnUiThread {
            try {
                val uri = Uri.parse("mqqapi://card/show_pslcard?src_type=internal&version=1&uin=434217654&card_type=group&source=qrcode")
                host.startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.tencent.mobileqq"))
                // Intent dispatch is not confirmation that QQ displayed or joined the group.
                call.resolve(JSObject().put("opened", true))
            } catch (_: ActivityNotFoundException) {
                call.resolve(JSObject().put("opened", false))
            } catch (_: SecurityException) {
                call.resolve(JSObject().put("opened", false))
            }
        }
    }

    @PluginMethod fun copy(call: PluginCall) {
        val host = activity
        if (host == null || host.isFinishing || host.isDestroyed) {
            call.reject("当前无法复制，请长按群号复制")
            return
        }
        host.runOnUiThread {
            try {
                val clipboard = host.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("邯院通 QQ 交流群", "434217654"))
                call.resolve()
            } catch (_: Exception) { call.reject("复制失败，请长按群号复制") }
        }
    }
}
