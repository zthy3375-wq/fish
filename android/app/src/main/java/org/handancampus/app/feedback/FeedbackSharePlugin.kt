package org.handancampus.app.feedback

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONObject
import java.io.File

@CapacitorPlugin(name = "FeedbackShare")
class FeedbackSharePlugin : Plugin() {
    @PluginMethod fun sendToQQ(call: PluginCall) {
        val report = call.getString("report") ?: ""
        try {
            require(report.toByteArray(Charsets.UTF_8).size in 1..131072)
            require(JSONObject(report).getInt("schema") == 1)
        } catch (_: Exception) {
            call.reject("反馈文件格式无效", "INVALID_REPORT")
            return
        }
        val host = activity
        if (host == null || host.isFinishing || host.isDestroyed) {
            call.reject("当前无法打开分享", "UNAVAILABLE")
            return
        }
        host.runOnUiThread {
            try {
                val directory = File(host.cacheDir, "failure-feedback").apply { mkdirs() }
                val file = File.createTempFile("hanyuantong-feedback-", ".json", directory)
                file.writeText(report, Charsets.UTF_8)
                val uri = FileProvider.getUriForFile(host, host.packageName + ".fileprovider", file)
                fun intent() = Intent(Intent.ACTION_SEND).apply {
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, "邯院通故障反馈")
                    clipData = ClipData.newUri(host.contentResolver, "邯院通故障反馈", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                try {
                    host.startActivity(intent().setPackage("com.tencent.mobileqq"))
                    call.resolve(JSObject().put("target", "qq"))
                } catch (_: ActivityNotFoundException) {
                    host.startActivity(Intent.createChooser(intent(), "QQ 不可用，请选择其他方式发送反馈"))
                    call.resolve(JSObject().put("target", "system"))
                }
                // The user chooses a recipient and confirms in QQ. Dispatch is not delivery.
            } catch (_: Exception) {
                call.reject("分享未打开，请尝试系统分享", "UNAVAILABLE")
            }
        }
    }
}
