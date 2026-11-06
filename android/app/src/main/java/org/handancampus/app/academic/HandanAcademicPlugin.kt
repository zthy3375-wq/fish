package org.handancampus.app.academic

import android.app.Dialog
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.webkit.*
import android.widget.*
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayInputStream

/** One native school session for all modules. School content gets NO JavascriptInterface/Capacitor bridge. */
@CapacitorPlugin(name = "HandanAcademicClient")
class HandanAcademicPlugin : Plugin() {
    private var web: WebView? = null
    private var dialog: Dialog? = null
    private var call: PluginCall? = null
    private var generation = 0
    private var authenticated = false
    private var started = false
    private val handler = Handler(Looper.getMainLooper())
    private val vault by lazy { SchoolSessionVault(context) }
    private val cookies get() = CookieManager.getInstance()
    private var login = false
    private var script = ""
    private var method = "syncAll"
    private var term = JSONObject()

    @PluginMethod fun login(call: PluginCall) = start(call, true, "timetable")
    @PluginMethod fun syncAll(call: PluginCall) = start(call, false, "syncAll")
    @PluginMethod fun getSessionState(call: PluginCall) = start(call, false, "session")
    @PluginMethod fun getTimetable(call: PluginCall) = start(call, false, "timetable")
    @PluginMethod fun getSemesters(call: PluginCall) = start(call, false, "semesters")
    @PluginMethod fun getProfile(call: PluginCall) = start(call, false, "profile")
    @PluginMethod fun getGrades(call: PluginCall) = start(call, false, "grades")
    @PluginMethod fun getExams(call: PluginCall) = start(call, false, "exams")

    private fun start(next: PluginCall, interactive: Boolean, operation: String) {
        activity.runOnUiThread {
            if (call != null) { next.reject("同步正在进行", "BUSY"); return@runOnUiThread }
            call = next; login = interactive; method = operation; started = false; authenticated = false
            term = JSONObject().apply {
                val year = next.getString("xnm") ?: ""
                val code = next.getString("xqm") ?: ""
                if (Regex("20\\d{2}").matches(year) && code in listOf("3", "12")) { put("xnm", year); put("xqm", code) }
            }
            val token = ++generation
            handler.postDelayed({ if (token == generation) fail("学校连接超时，保留上次数据", "NETWORK") }, if (interactive) 300000 else 80000)
            try {
                script = context.assets.open("handan-academic.js").bufferedReader().use { it.readText() }
                createWeb()
                val saved = vault.restore()
                // Restore before navigation. Cookie values never cross the native boundary.
                if (saved != null) saved.split(";").forEach {
                    if (it.contains("=")) cookies.setCookie(AcademicPolicy.ORIGIN, "${it.trim()}; Path=/; Secure; HttpOnly; SameSite=Lax")
                }
                cookies.flush()
                if (interactive) showLogin()
                web!!.loadUrl(if (interactive) AcademicPolicy.LOGIN else AcademicPolicy.HOME)
            } catch (_: Exception) { fail("无法打开学校连接", "NATIVE") }
        }
    }
    private fun createWeb() {
        WebView.setWebContentsDebuggingEnabled(false)
        web = WebView(activity).apply {
            settings.javaScriptEnabled = true; settings.domStorageEnabled = true
            settings.allowFileAccess = false; settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false); settings.saveFormData = false
            if(android.os.Build.VERSION.SDK_INT >= 26) importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            cookies.setAcceptCookie(true); cookies.setAcceptThirdPartyCookies(this, false)
            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onConsoleMessage(message: ConsoleMessage?): Boolean = true // no school PII in logcat
            }
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean = !AcademicPolicy.allowed(r.url.toString())
                override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse? =
                    if (AcademicPolicy.allowed(r.url.toString())) null else WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
                override fun onPageFinished(v: WebView, url: String) {
                    if (call == null) return
                    if (AcademicPolicy.loginPage(url)) {
                        if (!login) { authenticated = false; vault.clear(); finish(JSONObject().put("session", "expired")) }
                        return
                    }
                    if (started) return
                    checkAuthenticated(v, generation, 0)
                }
                override fun onReceivedSslError(v: WebView, h: SslErrorHandler, e: android.net.http.SslError) { h.cancel(); fail("学校证书验证失败", "TLS") }
                override fun onReceivedError(v: WebView, r: WebResourceRequest, e: WebResourceError) { if (r.isForMainFrame) fail("学校网络暂不可用", "NETWORK") }
                override fun onReceivedHttpError(v: WebView, r: WebResourceRequest, e: WebResourceResponse) { if(r.isForMainFrame) fail("学校服务暂不可用", "HTTP") }
            }
        }
    }
    private fun checkAuthenticated(v: WebView, token: Int, attempt: Int) {
        if(token != generation || call == null || started) return
        v.evaluateJavascript("JSON.stringify({ready:!!document.querySelector('#menu,#navbar_container,#yhxm,#xnm,[data-gnmkdm],a[onclick*=clickMenu],a[href*=login_logout]')&&!document.querySelector('input[type=password]')})") { raw ->
            if(token != generation || call == null || started) return@evaluateJavascript
            try {
                val ready = JSONObject(JSONTokener(raw).nextValue() as String).optBoolean("ready")
                if(ready) {
                    authenticated = true; started = true; cookies.flush()
                    try { cookies.getCookie(AcademicPolicy.ORIGIN)?.let { vault.save(it) } } catch (_: Exception) {}
                    dialog?.hide()
                    if(method == "session") finish(JSONObject().put("session", "valid")) else execute()
                } else if(attempt < 30) handler.postDelayed({ checkAuthenticated(v, token, attempt+1) }, 300)
                else fail("学校页面结构需要适配", "SCHEMA")
            } catch (_: Exception) { fail("学校页面结构需要适配", "SCHEMA") }
        }
    }
    private fun showLogin() {
        dialog = Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar).apply {
            val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE); fitsSystemWindows = true }
            val bar = LinearLayout(activity)
            bar.addView(Button(activity).apply { text = "取消"; setOnClickListener { fail("已取消连接", "CANCELLED") } })
            bar.addView(TextView(activity).apply { text = "邯郸学院官方登录\njwgl.hdc.edu.cn"; textSize = 14f })
            root.addView(bar)
            root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
            setContentView(root); setOnCancelListener { fail("已取消连接", "CANCELLED") }
            window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            show(); window?.setLayout(-1, -1)
        }
    }
    private fun execute() {
        val token = generation
        web?.evaluateJavascript("window.__handanResult=null;($script)(${JSONObject.quote(method)},$term);", null)
        fun poll() {
            if (token != generation || call == null) return
            web?.evaluateJavascript("window.__handanResult == null ? null : JSON.stringify(window.__handanResult)") { raw ->
                if (token != generation) return@evaluateJavascript
                try {
                    val decoded = JSONTokener(raw ?: "null").nextValue()
                    if (decoded == JSONObject.NULL) handler.postDelayed({ poll() }, 250)
                    else {
                        val result = JSONObject(decoded as String)
                        if (result.toString().length > 700000) throw IllegalArgumentException()
                        if (result.optString("session") == "expired") { vault.clear(); authenticated = false }
                        finish(result)
                    }
                } catch (_: Exception) { fail("学校返回数据无法识别，保留上次数据", "SCHEMA") }
            }
        }
        handler.postDelayed({ poll() }, 200)
    }
    private fun finish(result: JSONObject) {
        val pending = call ?: return
        call = null; generation++; handler.removeCallbacksAndMessages(null)
        cookies.flush()
        if (authenticated) try { cookies.getCookie(AcademicPolicy.ORIGIN)?.let { vault.save(it) } } catch (_: Exception) { /* next start may require authentication */ }
        destroyWeb(); pending.resolve(JSObject(result.toString()))
    }
    private fun fail(message: String, code: String) {
        val pending = call ?: return
        call = null; generation++; handler.removeCallbacksAndMessages(null); cookies.flush(); destroyWeb()
        pending.reject(message, code)
    }
    private fun destroyWeb() { dialog?.dismiss(); dialog = null; web?.let { (it.parent as? android.view.ViewGroup)?.removeView(it); it.stopLoading(); it.destroy() }; web = null }
    @PluginMethod fun logout(next: PluginCall) {
        activity.runOnUiThread {
            if (call != null) fail("连接已退出", "CANCELLED")
            vault.clear(); authenticated = false
            WebStorage.getInstance().deleteOrigin(AcademicPolicy.ORIGIN)
            cookies.removeAllCookies { cookies.flush(); next.resolve(JSObject().put("session", "disconnected")) }
        }
    }
    override fun handleOnDestroy() { if(call != null) fail("应用已关闭", "CANCELLED"); super.handleOnDestroy() }
}
