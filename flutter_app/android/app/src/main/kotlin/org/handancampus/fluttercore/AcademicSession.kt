package org.handancampus.fluttercore

import android.app.Dialog
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.webkit.*
import android.widget.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.util.UUID
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayInputStream

/** School content has no JavascriptInterface, Flutter channel, credential or file access. */
class AcademicSession(private val activity: FlutterActivity) {
    private val context get() = activity
    private class Pending(private val result: MethodChannel.Result) {
        fun resolve(value: JSONObject) { result.success(jsonValue(value)) }
        fun reject(message: String, code: String) { result.error(code, message, null) }
    }
    companion object {
        private fun jsonValue(value: Any?): Any? = when(value) {
            null, JSONObject.NULL -> null
            is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
            is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
            else -> value
        }
    }
    private var scope: String? = null
    fun handle(request: MethodCall, result: MethodChannel.Result) {
        val next = Pending(result)
        when(request.method) {
            "login" -> start(next, true)
            "getTimetable" -> start(next, false)
            "logout" -> logout(next)
            else -> result.notImplemented()
        }
    }
    private var web: WebView? = null
    private var dialog: Dialog? = null
    private var call: Pending? = null
    private var generation = 0
    private var authenticated = false
    private var started = false
    private val handler = Handler(Looper.getMainLooper())
    private val vault by lazy { SchoolSessionVault(context) }
    private val cookies get() = CookieManager.getInstance()
    private var login = false
    private var script = ""
    private var method = "timetable"
    private var renderedResult: JSONObject? = null
    private var term = JSONObject()

    private fun start(next: Pending, interactive: Boolean) {
        activity.runOnUiThread {
            if (call != null) { next.reject("同步正在进行", "BUSY"); return@runOnUiThread }
            renderedResult = null; call = next; login = interactive; method = "timetable"; started = false; authenticated = false
            term = JSONObject()
            val token = ++generation
            handler.postDelayed({ if (token == generation) fail("学校连接超时，保留上次数据", "NETWORK") }, 300000)
            try {
                script = context.assets.open("flutter_assets/assets/handan-academic.js").bufferedReader().use { it.readText() }
                if (interactive) { vault.clear(); scope = null }
                val saved = if (interactive) null else vault.restore()?.let { JSONObject(it) }
                scope = saved?.optString("scope")?.takeIf { it.isNotBlank() }
                if (!interactive && scope == null) { finish(JSONObject().put("session", "expired")); return@runOnUiThread }
                // CookieManager's transient WebView store is cleared before restoration and after use.
                // Never trust a pre-existing WebView cookie after process death/account switch.
                cookies.removeAllCookies {
                    if (token != generation || call == null) return@removeAllCookies
                    try {
                        createWeb()
                        restoreCookies(saved?.optString("cookies"), token) {
                            if(interactive) showLogin()
                            web?.loadUrl(if(interactive) AcademicPolicy.LOGIN else AcademicPolicy.HOME)
                        }
                    } catch (_: Exception) { fail("无法打开学校连接", "NATIVE") }
                }
            } catch (_: Exception) { fail("无法打开学校连接", "NATIVE") }
        }
    }
    private fun restoreCookies(header: String?, token: Int, done: () -> Unit) {
        val entries = header.orEmpty().split(";").map { it.trim() }.filter { it.contains("=") }
        fun restore(index: Int) {
            if (token != generation || call == null) return
            if (index == entries.size) { done(); return }
            cookies.setCookie(AcademicPolicy.ORIGIN, "${entries[index]}; Path=/; Secure; HttpOnly; SameSite=Lax") { accepted ->
                if (token != generation || call == null) return@setCookie
                if (accepted) restore(index + 1) else fail("无法恢复学校连接", "STORAGE")
            }
        }
        restore(0)
    }
    private fun createWeb() {
        WebView.setWebContentsDebuggingEnabled(false)
        web = WebView(activity).apply {
            settings.javaScriptEnabled = true; settings.domStorageEnabled = true
            settings.allowFileAccess = false; settings.allowContentAccess = false
            @Suppress("DEPRECATION")
            settings.allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            settings.allowUniversalAccessFromFileURLs = false
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
                        if (!login || renderedResult != null) { authenticated = false; vault.clear(); finish(JSONObject().put("session", "expired")) }
                        return
                    }
                    if (renderedResult != null) {
                        // Normal school query control; never call a CAPTCHA success function or fabricate verification.
                        v.evaluateJavascript("(function(){const challenge=['1','3'].includes(document.querySelector('#sfxyyzm')?.value)&&!document.querySelector('#kbgrid_table_0 .timetable_con');const b=document.querySelector('#search_go');if(b&&!challenge&&!document.querySelector('#kbgrid_table_0 .timetable_con'))b.click();return challenge;})()") { challenge ->
                            if (call == null) return@evaluateJavascript
                            if (challenge == "true") showLogin() else handler.postDelayed({readRendered(0,generation)},700)
                        }
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
                    authenticated = true; started = true
                    if (scope == null) scope = UUID.randomUUID().toString()
                    try { saveSession() } catch (_: Exception) { fail("无法安全保存学校连接", "STORAGE"); return@evaluateJavascript }
                    dialog?.hide()
                    execute()
                } else if(attempt < 30) handler.postDelayed({ checkAuthenticated(v, token, attempt+1) }, 300)
                else fail("学校页面结构需要适配", "SCHEMA")
            } catch (_: Exception) { fail("学校页面结构需要适配", "SCHEMA") }
        }
    }
    private fun showLogin() {
        val current = web ?: return
        (current.parent as? android.view.ViewGroup)?.removeView(current)
        dialog?.dismiss()
        current.alpha = 1f
        current.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        dialog = Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar).apply {
            val root = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE); fitsSystemWindows = true }
            val bar = LinearLayout(activity)
            bar.addView(Button(activity).apply { text = "取消"; setOnClickListener { fail("已取消连接", "CANCELLED") } })
            bar.addView(TextView(activity).apply { text = "邯郸学院官方登录\njwgl.hdc.edu.cn"; textSize = 14f })
            root.addView(bar)
            if (renderedResult != null) root.addView(Button(activity).apply {
                text = "请在官方页面完成验证，再点此继续"
                setOnClickListener { dialog?.hide(); readRendered(0, generation) }
            })
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
                        val fallback=result.optJSONObject("renderedPage")
                        val url=fallback?.optString("url") ?: ""
                        val uri=try { java.net.URI(AcademicPolicy.ORIGIN).resolve(url) } catch (_:Exception) { null }
                        if(fallback != null && uri != null && AcademicPolicy.allowed(uri.toString()) && Regex("/kbcx/xskbcx_cx(?:Xsgrkb(?:Index)?|XskbcxIndex)\\.html").matches(uri.path)) {
                            renderedResult=result
                            // Attach a tiny transparent WebView so the school page's AJAX/render lifecycle actually runs.
                            val view=web!!
                            (view.parent as? android.view.ViewGroup)?.removeView(view)
                            view.alpha=0f; view.importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                            activity.addContentView(view,android.view.ViewGroup.LayoutParams(1,1))
                            view.loadUrl(uri.toString())
                        } else finish(result)
                    }
                } catch (_: Exception) { fail("学校返回数据无法识别，保留上次数据", "SCHEMA") }
            }
        }
        handler.postDelayed({ poll() }, 200)
    }
    private fun readRendered(attempt: Int, token: Int) {
        val result=renderedResult ?: return
        if(token != generation || call == null) return
        val reader=try { context.assets.open("flutter_assets/assets/handan-rendered-reader.js").bufferedReader().use { it.readText() } } catch (_:Exception) { finish(result); return }
        web?.evaluateJavascript("($reader)()") { raw ->
            if(token != generation || call == null) return@evaluateJavascript
            try {
                val decoded=JSONTokener(raw ?: "null").nextValue() as? String ?: throw IllegalArgumentException()
                if(decoded.length>400000) throw IllegalArgumentException()
                val payload=JSONObject(decoded); val observation=payload.getJSONObject("observation")
                val rows=payload.getJSONArray("kbList")
                val source=result.optJSONObject("renderedPage")?.optJSONObject("term")
                val year=observation.optString("termYear"); val code=observation.optString("termCode")
                if((rows.length()>0 || (payload.optJSONArray("practice")?.length() ?: 0)>0) && observation.optInt("invalidCount")==0 && !observation.optBoolean("specialArrangements") && !observation.optBoolean("frameLimit") && Regex("20\\d{2}").matches(year) && code in listOf("3","12")) {
                    if(source != null && (source.optString("xnm")!=year || source.optString("xqm")!=code)) {
                        result.getJSONObject("modules").put("timetable",JSONObject().put("status","error").put("code","TERM"))
                    } else {
                        val data=JSONObject().put("term",JSONObject().put("xnm",year).put("xqm",code)).put("kbList",rows).put("practice",payload.optJSONArray("practice") ?: org.json.JSONArray())
                        result.getJSONObject("modules").put("timetable",JSONObject().put("status","ok").put("data",data))
                    }
                    result.remove("renderedPage");finish(result)
                } else if(attempt<30) handler.postDelayed({ readRendered(attempt+1,token) },700)
                else {
                    result.getJSONObject("modules").put("timetable",JSONObject().put("status","error").put("code",if(observation.optBoolean("specialArrangements")) "LIVE_SPECIAL" else "LIVE_EMPTY"))
                    result.remove("renderedPage");finish(result)
                }
            } catch (_:Exception) { result.remove("renderedPage"); finish(result) }
        }
    }
    private fun finish(result: JSONObject) {
        val pending = call ?: return
        renderedResult = null; call = null; generation++; handler.removeCallbacksAndMessages(null)
        if (authenticated) try { saveSession() } catch (_: Exception) {
            destroyWeb()
            cookies.removeAllCookies { cookies.flush(); pending.reject("无法安全保存学校连接", "STORAGE") }
            return
        }
        scope?.let { result.put("sessionScope", it) }
        result.remove("renderedPage")
        // Only timetable/semester data is used by Flutter; never bridge session material.
        destroyWeb()
        cookies.removeAllCookies { cookies.flush(); pending.resolve(result) }
    }
    private fun fail(message: String, code: String) {
        val pending = call ?: return
        renderedResult = null; call = null; generation++; handler.removeCallbacksAndMessages(null); destroyWeb()
        cookies.removeAllCookies {
            cookies.flush()
            if (authenticated && scope != null) pending.resolve(JSONObject()
                .put("session", "valid").put("sessionScope", scope)
                .put("cancelled", code == "CANCELLED")
                .put("modules", JSONObject().put("timetable", JSONObject().put("status", "error").put("code", code))))
            else pending.reject(message, code)
        }
    }
    private fun destroyWeb() { dialog?.dismiss(); dialog = null; web?.let { it.clearCache(true); it.clearHistory(); (it.parent as? android.view.ViewGroup)?.removeView(it); it.stopLoading(); it.destroy() }; web = null; WebStorage.getInstance().deleteAllData() }
    private fun logout(next: Pending) {
        activity.runOnUiThread {
            if (call != null) fail("连接已退出", "CANCELLED")
            try { vault.clear() } catch (_: Exception) { next.reject("无法清除学校连接，请重试", "STORAGE"); return@runOnUiThread }
            authenticated = false; scope = null
            WebStorage.getInstance().deleteAllData()
            cookies.removeAllCookies { cookies.flush(); next.resolve(JSONObject().put("session", "disconnected")) }
        }
    }
    private fun saveSession() {
        val value = cookies.getCookie(AcademicPolicy.ORIGIN) ?: throw IllegalStateException()
        val current = scope ?: throw IllegalStateException()
        check(value.isNotBlank() && value.length < 30000)
        vault.save(JSONObject().put("cookies", value).put("scope", current).toString())
    }
    fun dispose() { if(call != null) fail("应用已关闭", "CANCELLED"); destroyWeb() }
}
