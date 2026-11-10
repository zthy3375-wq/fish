package org.handancampus.app.life

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.webkit.*
import android.widget.*
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject

/** Official pages have no Capacitor/Java bridge. Codes stay in the document, never in logs or IPC. */
class ParcelWebActivity : Activity() {
    private lateinit var frame: FrameLayout
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private val handler = Handler(Looper.getMainLooper())
    private val browsers = linkedMapOf<String, WebView>()
    private val generations = mutableMapOf<WebView, Int>()
    private val rawPages = mutableSetOf<WebView>()
    private val projected = mutableSetOf<WebView>()
    private val failed = mutableSetOf<WebView>()
    private val passedLogin = mutableSetOf<WebView>()
    private val returnedOnce = mutableSetOf<WebView>()
    private val tabs = mutableMapOf<String, Button>()
    private var selected = "taobao"
    private var popup: WebView? = null
    private var closed = false
    private var foreground = false
    private var clearing = false
    private var usable = false
    private val preferences by lazy { getSharedPreferences("parcel_browser", MODE_PRIVATE) }
    private val purple = Color.rgb(104, 62, 174)
    private fun asset(name: String) = assets.open("parcel/handycode/$name").bufferedReader().use { it.readText() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        selected = try { ParcelWebPolicy.provider(savedInstanceState?.getString("provider") ?: intent.getStringExtra("provider")) }
            catch (_: Exception) { finish(); return }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.rgb(248, 245, 252))
            setOnApplyWindowInsetsListener { v, i ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val e = i.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                    v.setPadding(e.left, e.top, e.right, e.bottom)
                } else { @Suppress("DEPRECATION")
                    v.setPadding(i.systemWindowInsetLeft, i.systemWindowInsetTop, i.systemWindowInsetRight, i.systemWindowInsetBottom) }
                i
            }
        }
        val top = LinearLayout(this)
        top.addView(button("返回", true) { back() }, LinearLayout.LayoutParams(dp(62), dp(48)))
        top.addView(TextView(this).apply {
            text = "取快递"; textSize = 19f; setTextColor(Color.rgb(40, 31, 56)); gravity = 17
        }, LinearLayout.LayoutParams(0, dp(48), 1f))
        top.addView(button("关闭", true) { finish() }, LinearLayout.LayoutParams(dp(62), dp(48)))
        root.addView(top)
        val platforms = LinearLayout(this).apply { setPadding(dp(12), 0, dp(12), 0) }
        listOf("taobao" to "淘宝", "pinduoduo" to "拼多多").forEach { (id, name) ->
            val b = button(name) { select(id) }; tabs[id] = b
            platforms.addView(b, LinearLayout.LayoutParams(0, dp(46), 1f))
        }
        root.addView(platforms)
        val actions = LinearLayout(this)
        actions.addView(button("刷新") { refresh() }, LinearLayout.LayoutParams(0, dp(44), 1f))
        actions.addView(button("官方 App") { openOfficial() }, LinearLayout.LayoutParams(0, dp(44), 1f))
        actions.addView(button("更多") { menu() }, LinearLayout.LayoutParams(0, dp(44), 1f))
        root.addView(actions)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
        root.addView(progress, LinearLayout.LayoutParams(-1, dp(2)))
        status = TextView(this).apply {
            textSize = 11f; setTextColor(Color.rgb(104, 97, 116)); setPadding(dp(14), dp(6), dp(14), dp(6))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        root.addView(status)
        frame = FrameLayout(this); root.addView(frame, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root); root.requestApplyInsets()
        // Isolated profile is configured in Application.attachBaseContext, before ANY WebKit access.
        usable = ParcelWebProfile.configured && try { WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA) }
            catch (_: Exception) { false }
        if (!usable) {
            tell("应用内取件需要 Android 9 及以上和较新的系统 WebView。可点“官方 App”继续。")
            return
        }
        WebView.setWebContentsDebuggingEnabled(false)
        if (preferences.getBoolean("reset_pending", false)) clearProfile() else select(selected)
    }

    private fun button(label: String, allowDuringClear: Boolean = false, action: () -> Unit) = Button(this).apply {
        text = label; textSize = 13f; isAllCaps = false; minWidth = 0
        setTextColor(purple); setPadding(dp(3), 0, dp(3), 0)
        setOnClickListener { if (!closed && !isFinishing && (!clearing || allowDuringClear)) action() }
    }
    private fun tell(message: String) { if (!closed) status.text = message }
    private fun active(view: WebView) = !closed && !clearing && (browsers[selected] === view || popup === view)
    private fun owned(view: WebView) = !closed && !clearing && (browsers.values.contains(view) || popup === view)
    private fun attach(view: WebView) {
        (view.parent as? android.view.ViewGroup)?.removeView(view)
        frame.removeAllViews(); frame.addView(view, FrameLayout.LayoutParams(-1, -1))
        view.onResume()
    }
    private fun select(provider: String) {
        if (!usable || clearing || closed) return
        closePopup()
        browsers[selected]?.let { it.onPause(); it.evaluateJavascript("if(window.HandyPddLayout)HandyPddLayout.setActive(false)", null) }
        selected = provider
        tabs.forEach { (id, b) -> b.alpha = if (id == selected) 1f else .55f }
        try {
            val web = browsers[provider] ?: createBrowser(provider).also {
                browsers[provider] = it
                it.loadUrl(ParcelWebPolicy.entry(provider))
            }
            attach(web)
            web.evaluateJavascript("if(window.HandyPddLayout)HandyPddLayout.setActive(true)", null)
            tell("${if (provider == "taobao") "淘宝" else "拼多多"}官方网页 · 首次请在下方登录，登录后显示实际取件信息。")
            if (provider == "pinduoduo") tell("拼多多官方网页 · 网页与官方 App 登录同一账号可能互相退出，请按官方提示操作。")
            if (foreground) inspect(web, provider, generations[web] ?: 0, 0)
        } catch (_: Exception) { tell("无法打开网页，请更新系统 WebView 后重试，或使用官方 App。") }
    }

    @Suppress("DEPRECATION")
    private fun createBrowser(provider: String, isPopup: Boolean = false): WebView {
        val web = WebView(this)
        web.setBackgroundColor(Color.WHITE)
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            allowFileAccess = false; allowContentAccess = false
            allowFileAccessFromFileURLs = false; allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(true); javaScriptCanOpenWindowsAutomatically = false
            setGeolocationEnabled(false); mediaPlaybackRequiresUserGesture = true
            if (Build.VERSION.SDK_INT >= 26) safeBrowsingEnabled = true
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, provider == "taobao")
        // Installs before the first request, including SPA login return. No CDN rewriting or native cookie extraction.
        if (provider == "pinduoduo") {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                WebViewCompat.addDocumentStartJavaScript(web, asset("pdd-same-origin.js"), setOf("https://m.pinduoduo.net"))
            } else tell("系统网页组件较旧，拼多多登录可能无法保留。请更新系统 WebView。")
        }
        web.setDownloadListener { _, _, _, _, _ -> if (active(web)) tell("请在官方 App 中下载文件。") }
        web.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: ConsoleMessage?) = true // Never log account/page/code contents.
            override fun onProgressChanged(view: WebView, value: Int) {
                if (active(view)) { progress.progress = value; progress.visibility = if (value == 100 || failed.contains(view)) View.GONE else View.VISIBLE }
            }
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) { callback.invoke(origin, false, false) }
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                callback.onReceiveValue(null); if (active(view)) tell("如官方验证需要拍照或上传，请在官方 App 完成。"); return true
            }
            override fun onCreateWindow(view: WebView, dialog: Boolean, gesture: Boolean, result: android.os.Message): Boolean {
                if (!active(view) || !gesture || isPopup) return false
                closePopup()
                val child = createBrowser(provider, true); popup = child; attach(child)
                (result.obj as WebView.WebViewTransport).webView = child; result.sendToTarget()
                return true
            }
            override fun onCloseWindow(window: WebView) { if (window === popup) closePopup() }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val allowed = ParcelWebPolicy.allows(provider, request.url.toString())
                if (!allowed && active(view) && request.isForMainFrame) tell("该跳转请在上方“官方 App”中继续。")
                return !allowed
            }
            override fun shouldOverrideUrlLoading(view: WebView, url: String) = !ParcelWebPolicy.allows(provider, url)
            override fun onPageStarted(view: WebView, url: String, icon: Bitmap?) {
                if (!owned(view)) return
                if (isPopup && url == "about:blank") return
                if (!ParcelWebPolicy.allows(provider, url)) { view.stopLoading(); if (active(view)) tell("该地址暂不支持，请使用官方 App。"); return }
                generations[view] = (generations[view] ?: 0) + 1
                projected.remove(view); failed.remove(view)
                if (active(view)) tell("正在载入官方网页 · ${ParcelWebPolicy.host(url)}")
            }
            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                if (owned(view)) {
                    if (provider == "pinduoduo" && Uri.parse(url).path == "/login.html") passedLogin.add(view)
                    inspect(view, provider, generations[view] ?: 0, 0)
                }
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (!owned(view) || !ParcelWebPolicy.allows(provider, url)) return
                CookieManager.getInstance().flush()
                if (provider == "pinduoduo" && Uri.parse(url).path == "/index.html" && passedLogin.contains(view) && returnedOnce.add(view)) {
                    view.loadUrl(ParcelWebPolicy.PDD_ENTRY); return
                }
                inspect(view, provider, generations[view] ?: 0, 0)
            }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel(); failed.add(view); if (active(view)) tell("安全连接验证失败，请检查手机日期或稍后重试。")
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) pageFailed(view)
            }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame) pageFailed(view)
            }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                if (view === popup) closePopup() else {
                    browsers.entries.removeAll { it.value === view }; dispose(view)
                    if (!closed) tell("网页已关闭，请切换平台重新打开。")
                }
                return true
            }
        }
        return web
    }

    private fun pageFailed(view: WebView) {
        failed.add(view)
        if (active(view)) { progress.visibility = View.GONE; tell("官方页面暂不可用，可点“刷新”重试，或使用“官方 App”。") }
    }
    private fun inspect(view: WebView, provider: String, epoch: Int, attempt: Int) {
        if (!active(view) || !foreground || generations[view] != epoch || failed.contains(view) || rawPages.contains(view) || projected.contains(view)) return
        if (!ParcelWebPolicy.isEntry(provider, view.url)) return
        val probe = if (provider == "taobao") asset("official-identity.js") + "\n" + asset("login-ready.js")
            else assets.open("parcel/pdd-ready.js").bufferedReader().use { it.readText() }
        view.evaluateJavascript(probe) { result ->
            if (!active(view) || !foreground || generations[view] != epoch || failed.contains(view) || rawPages.contains(view) || projected.contains(view)) return@evaluateJavascript
            if (result == "true") {
                if (view === popup) { closePopup(); browsers[provider]?.loadUrl(ParcelWebPolicy.entry(provider)); return@evaluateJavascript }
                try {
                    val script = if (provider == "taobao") {
                        val html = asset("taobao.html")
                            .replace("@@REFRESH_CONTROLLER@@", asset("refresh-controller.js"))
                            .replace("@@OFFICIAL_IDENTITY@@", asset("official-identity.js"))
                            .replace("@@PICKUP_MOTION@@", asset("pickup-motion.js"))
                            .replace("@@IDENTITY_URL@@", ParcelWebPolicy.TAOBAO_IDENTITY)
                            .replace("@@PARCELS_URL@@", ParcelWebPolicy.TAOBAO_PARCELS)
                        "(function(){if(!HandyCodeOfficialIdentity.ready(document))return false;document.open();document.write(${JSONObject.quote(html)});document.close();if(window.HandyCodeSetDark)HandyCodeSetDark(false);return true;})()"
                    } else asset("pickup-motion.js") + "\nwindow.__HC_DARK__=false;\n" + asset("pdd-layout.js") +
                        "\n(function(){var s=document.createElement('style');s.textContent='[data-hc-pdd-refresh]{display:none!important}';document.head.appendChild(s);})();"
                    projected.add(view) // Fence duplicate inspection jobs before document changes.
                    view.evaluateJavascript(script) { applied ->
                        if (active(view)) {
                            if (provider == "taobao" && applied != "true") {
                                projected.remove(view); tell("官方页面仍在更新，请完成验证后刷新。")
                            } else tell("官方取件信息 · ${if (provider == "pinduoduo") "上方刷新会重新载入当前平台。" else "可刷新卡片；登录验证请在官方页面完成。"}")
                        }
                    }
                } catch (_: Exception) { projected.remove(view); tell("整理页面暂不可用，可在“更多”查看官方原始页面。") }
            } else if (attempt < 60) {
                handler.postDelayed({ inspect(view, provider, epoch, attempt + 1) }, 750)
            } else if (active(view)) tell("请完成官方登录或验证。页面已保留；若一直未显示，可刷新或在“更多”查看官方原始页面。")
        }
    }
    private fun refresh() {
        if (!usable) return
        closePopup()
        val web = browsers[selected] ?: run { select(selected); return }
        failed.remove(web)
        if (selected == "taobao" && projected.contains(web)) {
            web.evaluateJavascript("(function(){if(window.HandyCodeRefresh){HandyCodeRefresh();return true;}return false;})()") {
                if (active(web) && it != "true") web.loadUrl(ParcelWebPolicy.entry(selected))
            }
        } else { rawPages.remove(web); returnedOnce.remove(web); web.loadUrl(ParcelWebPolicy.entry(selected)) }
        tell("已请求刷新，请以官方页面显示的结果为准。")
    }
    private fun raw(identity: Boolean) {
        if (!usable) return
        closePopup()
        val web = browsers[selected] ?: return
        rawPages.add(web); projected.remove(web)
        web.loadUrl(if (selected == "taobao" && !identity) ParcelWebPolicy.TAOBAO_PARCELS else ParcelWebPolicy.entry(selected))
    }
    private fun menu() {
        AlertDialog.Builder(this).setTitle("取件设置").setItems(arrayOf("官方待取页面", "官方身份码页面", "重新整理页面", "清除快递登录", "开源说明")) { _, which ->
            when (which) {
                0 -> raw(false)
                1 -> raw(true)
                2 -> { browsers[selected]?.let { rawPages.remove(it); projected.remove(it) }; refresh() }
                3 -> if (usable) AlertDialog.Builder(this).setTitle("清除快递登录？")
                    .setMessage("清除本机淘宝与拼多多取件网页的登录和网页数据。教务、学习通、钱包以及官方 App 的登录不受影响。")
                    .setNegativeButton("取消", null).setPositiveButton("清除") { _, _ -> clearProfile() }.show()
                4 -> AlertDialog.Builder(this).setTitle("开源说明").setMessage(asset("LICENSE")).setPositiveButton("知道了", null).show()
            }
        }.show()
    }
    private fun clearProfile() {
        if (!usable || clearing) return
        if (!preferences.edit().putBoolean("reset_pending", true).commit()) { usable = false; tell("无法记录清理状态，请关闭后重试。"); return }
        clearing = true
        popup?.let { dispose(it) }; popup = null
        browsers.values.toList().forEach { dispose(it) }; browsers.clear(); frame.removeAllViews()
        handler.removeCallbacksAndMessages(null)
        tell("正在清除快递网页登录…")
        try {
            WebStorageCompat.deleteBrowsingData(WebStorage.getInstance()) {
                if (!preferences.edit().putBoolean("reset_pending", false).commit()) {
                    usable = false; tell("清理状态未保存，请关闭后重新打开。"); return@deleteBrowsingData
                }
                clearing = false
                if (!closed && !isFinishing) { select(selected); tell("已清除快递网页登录，请在官方页面重新登录。") }
            }
        } catch (_: Exception) { usable = false; tell("登录清理尚未完成，请关闭后重新打开。") }
    }
    private fun openOfficial() {
        try {
            val target = ParcelShortcutContract.target(selected, setOf("provider"))
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(target.uri)).setPackage(target.packageName))
        } catch (_: Exception) { tell("未能打开官方 App，请确认已安装，或继续使用下方网页。") }
    }
    private fun closePopup() {
        val child = popup ?: return
        popup = null; dispose(child)
        browsers[selected]?.let { attach(it) }
    }
    private fun dispose(view: WebView) {
        generations.remove(view); rawPages.remove(view); projected.remove(view); failed.remove(view)
        passedLogin.remove(view); returnedOnce.remove(view)
        (view.parent as? android.view.ViewGroup)?.removeView(view)
        view.stopLoading(); view.destroy()
    }
    @Suppress("DEPRECATION")
    private fun back() {
        if (clearing) { finish(); return }
        val current = popup ?: browsers[selected]
        if (current != null && ParcelWebPolicy.isEntry(selected, current.url) && projected.contains(current)) {
            current.evaluateJavascript("(function(){return !!(window.HandyPddLayout && HandyPddLayout.back());})()") {
                if (active(current) && it != "true") { if (popup != null) closePopup() else finish() }
            }
        } else if (current?.canGoBack() == true) current.goBack()
        else if (popup != null) closePopup() else finish()
    }
    @Deprecated("Legacy Android back dispatch") override fun onBackPressed() { back() }
    override fun onSaveInstanceState(out: Bundle) { out.putString("provider", selected); super.onSaveInstanceState(out) }
    override fun onResume() {
        super.onResume(); foreground = true
        (popup ?: browsers[selected])?.let { it.onResume(); inspect(it, selected, generations[it] ?: 0, 0) }
    }
    override fun onPause() {
        foreground = false; handler.removeCallbacksAndMessages(null)
        browsers.values.forEach { it.onPause() }; popup?.onPause()
        if (usable) CookieManager.getInstance().flush()
        super.onPause()
    }
    override fun onDestroy() {
        closed = true; handler.removeCallbacksAndMessages(null)
        popup?.let { dispose(it) }; popup = null
        browsers.values.toList().forEach { dispose(it) }; browsers.clear()
        super.onDestroy()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
