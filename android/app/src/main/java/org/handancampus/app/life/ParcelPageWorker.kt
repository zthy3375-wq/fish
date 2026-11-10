package org.handancampus.app.life

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.webkit.*
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONTokener
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Official page execution is a data source behind the native UI; it is shown only for authentication. */
@Suppress("DEPRECATION")
class ParcelPageWorker(
    private val activity: Activity, val provider: String, private val listener: Listener
) {
    interface Listener {
        fun onBatch(worker: ParcelPageWorker, batch: NativeParcelBatch, scope: String)
        fun onIssue(worker: ParcelPageWorker, issue: String)
        fun onVerified(worker: ParcelPageWorker)
        fun onIdentity(worker: ParcelPageWorker, bitmap: Bitmap)
    }
    val web = WebView(activity)
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var request: Future<*>? = null
    private val collector = asset("native/collector.js")
    private val identityScript = asset("native/identity.js")
    private var generation = 0
    private var document = 0
    private var running = false
    private var destroyed = false
    private var deadline = 0L
    private var nativeQueried = false
    private var lastResult = ""
    private var successful = false
    private var redirected = false
    var authenticating = false
        private set
    var identity = false
        private set
    private fun asset(name: String) = activity.assets.open("parcel/$name").bufferedReader().use { it.readText() }
    private fun target() = if (identity) ParcelWebPolicy.entry(provider) else if (provider == "taobao") ParcelWebPolicy.TAOBAO_PARCELS else ParcelWebPolicy.PDD_ENTRY
    init {
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            allowFileAccess = false; allowContentAccess = false
            allowFileAccessFromFileURLs = false; allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false; setSupportMultipleWindows(false)
            setGeolocationEnabled(false); mediaPlaybackRequiresUserGesture = true
            // A regular mobile browser user agent avoids official-app-only bridge branches.
            userAgentString = userAgentString.replace("; wv", "").replace("Version/4.0 ", "")
        }
        web.setBackgroundColor(android.graphics.Color.WHITE)
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, provider == "taobao")
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            if (provider == "pinduoduo") WebViewCompat.addDocumentStartJavaScript(web, asset("handycode/pdd-same-origin.js"), setOf("https://m.pinduoduo.net"))
            WebViewCompat.addDocumentStartJavaScript(web, collector,
                if (provider == "taobao") setOf("https://*.taobao.com") else setOf("https://m.pinduoduo.net", "https://mobile.yangkeduo.com"))
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: ConsoleMessage?) = true
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) { callback.invoke(origin, false, false) }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = !ParcelWebPolicy.allows(provider, request.url.toString())
            override fun shouldOverrideUrlLoading(view: WebView, url: String) = !ParcelWebPolicy.allows(provider, url)
            override fun onPageStarted(view: WebView, url: String, icon: Bitmap?) {
                document++
                if (!ParcelWebPolicy.allows(provider, url)) { view.stopLoading(); return }
                if (running) schedule(350)
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (!running || !ParcelWebPolicy.allows(provider, url)) return
                CookieManager.getInstance().flush()
                if (provider == "pinduoduo" && android.net.Uri.parse(url).path == "/index.html" && authenticating && !redirected) {
                    redirected = true; view.loadUrl(target()); return
                }
                view.evaluateJavascript(collector, null)
                schedule(400)
            }
            override fun onReceivedSslError(view: WebView, h: SslErrorHandler, error: SslError) { h.cancel(); issue("network") }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) { if (request.isForMainFrame) issue("network") }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) { if (request.isForMainFrame) issue("network") }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean { issue("renderer"); destroy(); return true }
        }
    }
    fun start(auth: Boolean = false, showIdentity: Boolean = false) {
        if (destroyed) return
        pause(); generation++; identity = showIdentity; authenticating = auth
        nativeQueried = false; successful = false; redirected = false; lastResult = ""
        running = true; deadline = System.currentTimeMillis() + if (auth) 180_000 else 40_000
        web.onResume(); web.loadUrl(target()); schedule(700)
    }
    fun continueAuthentication() {
        if (destroyed) return
        running = true; authenticating = true; deadline = System.currentTimeMillis() + 180_000
        web.onResume(); schedule(200)
    }
    private fun schedule(delay: Long) { handler.removeCallbacks(poll); if (running) handler.postDelayed(poll, delay) }
    private val poll = Runnable { read() }
    private fun issue(reason: String) {
        if (!running || destroyed) return
        running = false; handler.removeCallbacks(poll); request?.cancel(true)
        listener.onIssue(this, reason)
    }
    private fun read() {
        if (!running || destroyed || activity.isFinishing) return
        if (System.currentTimeMillis() > deadline) { issue(if (successful) "partial" else "unrecognized"); return }
        val ticket = generation; val page = document
        val current = web.url
        if (!ParcelWebPolicy.allows(provider, current)) { schedule(700); return }
        val fallback = "JSON.stringify(window.HytParcel ? HytParcel.read() : {version:2,provider:'$provider',phase:/login|passport|captcha|verify/i.test(location.href)?'login':'loading',items:[]})"
        web.evaluateJavascript(collector + "\n;" + fallback) { raw ->
            if (!running || destroyed || generation != ticket || document != page) return@evaluateJavascript
            val batch = NativeParcelBatch.parse(provider, raw)
            if (batch.phase == "login" || batch.phase == "verify") {
                if (!authenticating) { issue(batch.phase); return@evaluateJavascript }
                schedule(700); return@evaluateJavascript
            }
            if (batch.phase in setOf("partial", "empty")) {
                successful = true
                if (lastResult != raw) { lastResult = raw; listener.onBatch(this, batch, accountScope()) }
                if (authenticating) { authenticating = false; deadline = System.currentTimeMillis() + 15_000; listener.onVerified(this) }
                if (!identity) {
                    // Keep the source attached for late network/DOM results, without showing it to the user.
                    if (!nativeQueried && provider == "taobao") nativeQuery(ticket, page)
                    schedule(1300); return@evaluateJavascript
                }
            }
            captureIdentity(ticket, page) { ready ->
                if (!running || generation != ticket || document != page) return@captureIdentity
                if (ready && !identity && provider == "taobao") { web.loadUrl(ParcelWebPolicy.TAOBAO_PARCELS); schedule(700); return@captureIdentity }
                if (!nativeQueried && provider == "taobao" && batch.phase != "login") nativeQuery(ticket, page)
                schedule(900)
            }
        }
    }
    private fun captureIdentity(ticket: Int, page: Int, done: (Boolean) -> Unit) {
        web.evaluateJavascript(identityScript) { raw ->
            if (!running || destroyed || generation != ticket || document != page) return@evaluateJavascript
            val data = try { JSONTokener(raw).nextValue() as? String } catch (_: Exception) { null }
            if (data == null || !data.startsWith("data:image/png;base64,") || data.length > 1_500_000) { done(false); return@evaluateJavascript }
            try {
                val bytes = android.util.Base64.decode(data.substringAfter(','), android.util.Base64.DEFAULT)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                require(bounds.outWidth in 1..2048 && bounds.outHeight in 1..2048 && bounds.outWidth.toLong() * bounds.outHeight <= 2_000_000)
                if (authenticating) { authenticating = false; listener.onVerified(this) }
                if (identity) {
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: throw IllegalArgumentException()
                    running = false; handler.removeCallbacks(poll); listener.onIdentity(this, bitmap)
                }
                done(true)
            } catch (_: Exception) { done(false) }
        }
    }
    private fun nativeQuery(ticket: Int, page: Int) {
        val cookies = CookieManager.getInstance().getCookie(ParcelTaobaoQuery.ORIGIN).orEmpty()
        if (!cookies.contains("_m_h5_tk=")) return
        nativeQueried = true
        val ua = web.settings.userAgentString
        request = executor.submit {
            val result = try { ParcelTaobaoQuery.query(cookies, ua) } catch (_: Exception) { null }
            handler.post {
                if (result == null || !running || destroyed || ticket != generation || page != document) return@post
                result.cookies.forEach { CookieManager.getInstance().setCookie(ParcelTaobaoQuery.ORIGIN, it) }
                result.bodies.forEach { body -> web.evaluateJavascript("if(window.HytParcel) HytParcel.consume(${JSONObject.quote(body)})", null) }
                schedule(300)
            }
        }
    }
    fun accountScope(): String {
        val url = if (provider == "taobao") "https://m.taobao.com" else "https://m.pinduoduo.net"
        val cookie = CookieManager.getInstance().getCookie(url).orEmpty()
        val keys = if (provider == "taobao") listOf("unb", "_nk_", "tracknick") else listOf("pdd_user_id", "pdd_user_uin", "PDDAccessToken")
        val principal = keys.firstNotNullOfOrNull { key -> Regex("(?:^|;\\s*)${Regex.escape(key)}=([^;]+)").find(cookie)?.groupValues?.get(1) }.orEmpty()
        if (principal.isBlank()) return ""
        return MessageDigest.getInstance("SHA-256").digest("$provider:$principal".toByteArray()).joinToString("") { "%02x".format(it) }
    }
    fun pause() { generation++; running = false; handler.removeCallbacksAndMessages(null); request?.cancel(true); web.onPause() }
    fun destroy() {
        if (destroyed) return
        pause(); destroyed = true; executor.shutdownNow()
        (web.parent as? android.view.ViewGroup)?.removeView(web); web.stopLoading(); web.destroy()
    }
}
