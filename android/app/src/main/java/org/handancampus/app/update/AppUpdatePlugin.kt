package org.handancampus.app.update

import android.content.Intent
import android.content.ClipData
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.BuildConfig
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name = "AppUpdate")
class AppUpdatePlugin : Plugin() {
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    @Volatile private var policy: UpdatePolicy? = null
    @Volatile private var stage = "idle"
    @Volatile private var progress = 0
    @Volatile private var error = ""
    @Volatile private var destroyed = false
    private val installed get() = BuildConfig.VERSION_CODE
    private val prefs get() = context.getSharedPreferences("app_updates", 0)
    private val directory get() = File(context.cacheDir, "updates").apply { mkdirs() }
    private fun target(p: UpdatePolicy) = File(directory, "${p.code}-${p.sha256.take(16)}.apk")
    override fun load() {
        policy = try { prefs.getString("policy", null)?.let { UpdatePolicy.parse(it) } } catch (_: Exception) { null }
        policy?.let { if (it.available(installed, Build.VERSION.SDK_INT) && target(it).exists()) stage = "ready" }
    }
    private fun snapshot(): JSObject {
        val p = policy
        return JSObject().put("currentVersion", BuildConfig.VERSION_NAME).put("currentCode", installed)
            .put("stage", stage).put("progress", progress).put("error", error)
            .put("available", p?.available(installed, Build.VERSION.SDK_INT) == true)
            .put("mandatory", p?.mandatory(installed, Build.VERSION.SDK_INT) == true)
            .put("release", p?.json()).put("checkedAt", prefs.getLong("checkedAt", 0))
    }
    @PluginMethod fun getState(call: PluginCall) { call.resolve(snapshot()) }
    @PluginMethod fun check(call: PluginCall) {
        if (!busy.compareAndSet(false, true)) { call.resolve(snapshot()); return }
        stage = "checking"; error = ""
        worker.execute {
            try {
                val c = connect(UpdatePolicy.CHANNEL + "?t=" + System.currentTimeMillis(), channel = true)
                val bytes = try { c.inputStream.use { stream ->
                    val out = java.io.ByteArrayOutputStream(); val b = ByteArray(4096)
                    while (true) { val n = stream.read(b); if (n < 0) break; require(out.size() + n <= 65536); out.write(b, 0, n) }; out.toByteArray()
                }} finally { c.disconnect() }
                val next = UpdatePolicy.parse(bytes.toString(Charsets.UTF_8))
                policy = next
                prefs.edit().putString("policy", next.json().toString()).putLong("checkedAt", System.currentTimeMillis()).apply()
                stage = if (next.available(installed, Build.VERSION.SDK_INT) && target(next).exists()) "ready" else "idle"
                if (next.code > installed && Build.VERSION.SDK_INT < next.minSdk) error = "新版本需要更高的 Android 系统版本，当前版本仍可使用"
            } catch (_: Exception) {
                error = "暂时无法检查更新，请检查网络后重试"
                stage = if (policy?.let { target(it).exists() } == true) "ready" else "idle"
            } finally { busy.set(false); if (!destroyed) call.resolve(snapshot()) }
        }
    }
    private fun connect(raw: String, channel: Boolean = false): HttpURLConnection {
        var url = raw
        repeat(5) {
            require(if(channel) UpdatePolicy.trustedChannelUrl(url) else UpdatePolicy.trustedUrl(url))
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 15000; c.readTimeout = 20000; c.instanceFollowRedirects = false
            c.setRequestProperty("User-Agent", "Hanyuantong/${BuildConfig.VERSION_NAME} Android")
            c.useCaches = false; c.setRequestProperty("Accept-Encoding", "identity")
            c.setRequestProperty("Cache-Control", "no-cache")
            try {
                val status = c.responseCode
                if (status in listOf(301,302,303,307,308)) {
                    val next = c.getHeaderField("Location") ?: error("missing redirect")
                    url = URL(URL(url), next).toString(); c.disconnect()
                } else { require(status == 200); return c }
            } catch (e: Exception) { c.disconnect(); throw e }
        }
        error("redirect limit")
    }
    @PluginMethod fun download(call: PluginCall) {
        val p = policy
        if (p == null || !p.available(installed, Build.VERSION.SDK_INT)) { call.reject("请先检查可用更新"); return }
        if (!busy.compareAndSet(false, true)) { call.resolve(snapshot()); return }
        stage = "downloading"; progress = 0; error = ""; call.resolve(snapshot())
        worker.execute {
            val file = target(p); val partial = File(directory, "download.part")
            try {
                directory.listFiles()?.filter { it != file }?.forEach { it.delete() }
                if (file.exists()) { validate(file, p); progress = 100; stage = "ready" }
                else {
                    val c = connect(p.url)
                    try {
                        val length = c.getHeaderField("Content-Length")?.toLongOrNull() ?: -1L; require(length < 0 || length == p.size)
                        c.inputStream.use { input -> partial.outputStream().use { output ->
                            val buffer = ByteArray(65536); var total = 0L
                            while (true) {
                                if (destroyed || Thread.currentThread().isInterrupted) throw InterruptedException()
                                val n = input.read(buffer); if (n < 0) break
                                total += n; require(total <= p.size); output.write(buffer, 0, n)
                                progress = (total * 99 / p.size).toInt()
                            }
                            require(total == p.size)
                        }}
                    } finally { c.disconnect() }
                    validate(partial, p); require(partial.renameTo(file)); progress = 100; stage = "ready"
                }
            } catch (_: Exception) {
                partial.delete(); file.delete(); stage = "idle"; error = "下载或安装包校验失败，请重试"
            } finally { busy.set(false) }
        }
    }
    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val values = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return values?.map { sha(it.toByteArray()) }?.toSet() ?: emptySet()
    }
    private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
    @Suppress("DEPRECATION")
    private fun validate(file: File, p: UpdatePolicy) {
        require(file.length() == p.size)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream -> val b = ByteArray(65536); while (true) { val n = stream.read(b); if (n < 0) break; digest.update(b, 0, n) } }
        require(digest.digest().joinToString("") { "%02x".format(it) } == p.sha256)
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = context.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("invalid archive")
        val current = context.packageManager.getPackageInfo(context.packageName, flags)
        val code = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        require(archive.packageName == context.packageName && code == p.code.toLong() && code > installed)
        require(signatures(current).isNotEmpty() && signatures(current) == signatures(archive))
    }
    @PluginMethod fun install(call: PluginCall) {
        val p = policy
        if (p == null || stage != "ready" || !busy.compareAndSet(false, true)) { call.reject("安装包尚未准备好"); return }
        worker.execute {
            try {
                val file = target(p); validate(file, p)
                activity.runOnUiThread {
                    try {
                        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
                            call.resolve(JSObject().put("status", "permission"))
                        } else {
                            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            intent.clipData = ClipData.newRawUri("邯院通更新", uri)
                            activity.startActivity(intent); call.resolve(JSObject().put("status", "installer"))
                        }
                    } catch (_: Exception) { call.reject("无法打开系统安装界面，请重试") }
                    finally { busy.set(false) }
                }
            } catch (_: Exception) { target(p).delete(); stage = "idle"; busy.set(false); call.reject("安装包校验失败，请重新下载") }
        }
    }
    override fun handleOnDestroy() { destroyed = true; worker.shutdownNow(); super.handleOnDestroy() }
}
