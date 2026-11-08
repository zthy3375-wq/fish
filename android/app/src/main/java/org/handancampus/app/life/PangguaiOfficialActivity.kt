package org.handancampus.app.life

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.webkit.*
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicBoolean

/** A visible, constrained official browser. No bridge is installed in the provider's WebView. */
class PangguaiOfficialActivity : Activity() {
    companion object { const val PAGE_EXTRA = "pangguai_official_page" }
    @Volatile private var web: WebView? = null
    @Volatile private var viewGeneration = 0L
    private lateinit var browserContainer: FrameLayout
    private lateinit var identity: TextView
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private lateinit var back: Button
    private lateinit var clear: Button
    private lateinit var miniApp: Button
    private val routeButtons = mutableListOf<Button>()
    private var page = PangguaiPage.WALLET
    private var failed = false
    private var closed = false
    private var leftForAlipay = false
    private var confirmation: AlertDialog? = null
    private var backCallback: OnBackInvokedCallback? = null
    private val resourceRestricted = AtomicBoolean(false)
    private val profileListener: (PangguaiProfilePhase) -> Unit = { renderProfileState(it) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        page = try {
            PangguaiOfficialPolicy.page(savedInstanceState?.getString(PAGE_EXTRA) ?: intent.getStringExtra(PAGE_EXTRA))
        } catch (_: Exception) { finish(); return }
        leftForAlipay = savedInstanceState?.getBoolean("left_for_alipay", false) ?: false
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
            setOnApplyWindowInsetsListener { view, insets ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val edges = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                    view.setPadding(edges.left, edges.top, edges.right, edges.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                }
                insets
            }
        }
        val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        back = button("返回") { goBackOrClose() }
        header.addView(back, LinearLayout.LayoutParams(dp(64), dp(48)))
        identity = TextView(this).apply {
            text = "胖乖官方页面\nh5.qiekj.com"
            textSize = 13f
            setTextColor(Color.rgb(30, 41, 59))
            gravity = android.view.Gravity.CENTER_VERTICAL
        }
        header.addView(identity, LinearLayout.LayoutParams(0, dp(48), 1f))
        header.addView(button("关闭") { finish() }, LinearLayout.LayoutParams(dp(64), dp(48)))
        root.addView(header)
        val routes = LinearLayout(this)
        listOf("登录" to PangguaiPage.LOGIN, "钱包" to PangguaiPage.WALLET, "运营商" to PangguaiPage.OPERATORS).forEach { (label, target) ->
            val route = button(label) { navigate(target) }
            routeButtons.add(route)
            routes.addView(route, LinearLayout.LayoutParams(0, dp(44), 1f))
        }
        clear = button("清除会话") { confirmDiscard() }
        routes.addView(clear, LinearLayout.LayoutParams(0, dp(44), 1f))
        root.addView(routes)
        root.addView(TextView(this).apply {
            text = "关闭不等于退出。可清除本机胖乖独立网页数据，不影响教务，也不会解除官方账号绑定。"
            textSize = 11f
            setTextColor(Color.DKGRAY)
            setPadding(dp(12), dp(4), dp(12), dp(4))
        })
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
        root.addView(progress, LinearLayout.LayoutParams(-1, dp(3)))
        status = TextView(this).apply {
            textSize = 11f
            setTextColor(Color.DKGRAY)
            setPadding(dp(12), dp(4), dp(12), dp(4))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        root.addView(status)
        browserContainer = FrameLayout(this)
        root.addView(browserContainer, LinearLayout.LayoutParams(-1, 0, 1f))
        miniApp = button("无法继续？打开支付宝胖乖小程序") { confirmMiniApp() }
        root.addView(miniApp, LinearLayout.LayoutParams(-1, dp(48)))
        setContentView(root)
        root.requestApplyInsets()
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback = OnBackInvokedCallback { goBackOrClose() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback!!)
        }
        // Must precede EVERY android.webkit API, including debugging and feature detection.
        PangguaiProfileSession.initialize(applicationContext)
        PangguaiProfileSession.observe(profileListener)
        if (PangguaiProfileSession.phase == PangguaiProfilePhase.READY &&
            (savedInstanceState?.getBoolean("show_official_page", true) ?: true)) navigate(page)
    }

    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        textSize = 12f
        isAllCaps = false
        minWidth = 0
        setPadding(dp(4), 0, dp(4), 0)
        setOnClickListener { if (!closed && !isFinishing) action() }
    }

    @Suppress("DEPRECATION")
    private fun configureWebView(web: WebView) {
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            // Preserve the system UA. Pretending to be the official App selects unusable native bridges.
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            saveFormData = false
            mediaPlaybackRequiresUserGesture = true
            setGeolocationEnabled(false)
            if (Build.VERSION.SDK_INT >= 26) safeBrowsingEnabled = true
        }
        if (Build.VERSION.SDK_INT >= 26) web.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        // This process's isolated profile only. Never change the main process's school CookieManager.
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
        web.setDownloadListener { _, _, _, _, _ ->
            if (current(web)) tell("此窗口不下载文件或安装应用，请手动使用胖乖官方 App 或小程序。")
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, value: Int) {
                if (!current(view)) return
                progress.progress = value
                progress.visibility = if (value >= 100 || failed) View.GONE else View.VISIBLE
            }
            override fun onConsoleMessage(message: ConsoleMessage?): Boolean = true
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) {
                callback.invoke(origin, false, false)
                if (current(web)) tell("此窗口不提供定位权限，请在官方 App 或小程序中继续。")
            }
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                callback.onReceiveValue(null)
                if (current(view)) tell("此窗口不上传文件，请在官方 App 或小程序中继续。")
                return true
            }
            override fun onCreateWindow(view: WebView, dialog: Boolean, gesture: Boolean, result: android.os.Message): Boolean {
                if (current(view)) tell("此窗口不打开新窗口，请使用上方钱包或运营商入口，或改用官方小程序。")
                return false
            }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!current(view)) return true
                val allowed = if (request.isForMainFrame) PangguaiOfficialPolicy.allowsNavigation(request.url.toString())
                    else PangguaiOfficialPolicy.allowsResource(request.url.toString(), false)
                if (!allowed && request.isForMainFrame) blockedNavigation()
                return !allowed
            }
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                if (!current(view)) return true
                if (PangguaiOfficialPolicy.allowsNavigation(url)) return false
                blockedNavigation()
                return true
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (!current(view)) return blockedResponse()
                if (PangguaiOfficialPolicy.allowsResource(request.url.toString(), request.isForMainFrame)) return null
                if (request.isForMainFrame) runOnUiThread { if (current(view)) blockedNavigation() }
                else if (resourceRestricted.compareAndSet(false, true)) runOnUiThread { if (current(view)) restrictedResourceMessage() }
                return blockedResponse()
            }
            override fun onPageStarted(view: WebView, url: String, icon: Bitmap?) {
                if (!current(view)) return
                val host = PangguaiOfficialPolicy.navigationHost(url)
                if (host == null) { view.stopLoading(); blockedNavigation(); return }
                identity.text = "胖乖官方页面\n$host"
                failed = false
                resourceRestricted.set(false)
                tell("正在载入官方页面…如需登录，请在官方页面自行完成。")
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (!current(view)) return
                if (!failed && PangguaiOfficialPolicy.allowsNavigation(url)) {
                    if (resourceRestricted.get()) restrictedResourceMessage()
                    else tell("余额、登录与充值结果请以官方页面为准。登录后未返回？可点上方钱包或运营商。")
                }
                back.contentDescription = if (view.canGoBack()) "返回上一官方页面" else "关闭胖乖官方页面"
            }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel()
                if (!current(view)) return
                view.stopLoading()
                loadError("官方页面证书验证失败，已停止连接。请稍后重试或使用官方 App。")
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (current(view) && request.isForMainFrame) loadError("官方页面暂时无法连接。可点上方入口重试，或使用官方 App。")
            }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (current(view) && request.isForMainFrame) loadError("官方服务暂不可用。可点上方入口重试，或使用官方 App。")
            }
        }
    }

    private fun navigate(target: PangguaiPage) {
        if (closed || isFinishing) return
        page = target
        failed = false
        var view = web
        if (view == null) {
            val token = PangguaiProfileSession.claimView() ?: return
            viewGeneration = token
            try {
                // Session initialization already set the isolated data suffix before this call.
                WebView.setWebContentsDebuggingEnabled(false)
                view = WebView(this)
                web = view
                val owned = view
                PangguaiProfileSession.registerView(token) { disposeBrowser(owned) }
                configureWebView(view)
                browserContainer.removeAllViews()
                browserContainer.addView(view, FrameLayout.LayoutParams(-1, -1))
            } catch (_: Exception) {
                destroyCurrentView()
                tell("无法创建安全网页窗口，请使用下方官方小程序。")
                return
            }
        }
        if (current(view)) view.loadUrl(target.url)
    }

    private fun current(view: WebView): Boolean = !closed && web === view && PangguaiProfileSession.ownsView(viewGeneration)

    private fun blockedResponse() = WebResourceResponse("text/plain", "UTF-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)))

    private fun destroyCurrentView() {
        PangguaiProfileSession.releaseView(viewGeneration)
    }

    private fun disposeBrowser(previous: WebView) {
        web = null // Fence callbacks before stopping or destroying the old view.
        // The controller retains this reference until all disposal steps succeed.
        previous.stopLoading()
        (previous.parent as? ViewGroup)?.removeView(previous)
        previous.destroy()
    }

    private fun renderProfileState(phase: PangguaiProfilePhase) {
        if (closed || !::browserContainer.isInitialized) return
        val usable = phase == PangguaiProfilePhase.READY || phase == PangguaiProfilePhase.IN_USE
        routeButtons.forEach { it.isEnabled = usable }
        clear.isEnabled = PangguaiProfileSession.canReset
        back.isEnabled = phase != PangguaiProfilePhase.CLEARING
        miniApp.isEnabled = phase != PangguaiProfilePhase.CLEARING
        if (phase == PangguaiProfilePhase.CLEARING) {
            confirmation?.dismiss()
        }
        if (web != null) return
        progress.visibility = View.GONE
        val message = when (phase) {
            PangguaiProfilePhase.CLEARING -> "正在清除本机胖乖独立网页数据，暂时不能重开。可关闭窗口，清理状态会保留。"
            PangguaiProfilePhase.BLOCKED -> if (PangguaiProfileSession.canReset)
                "本机网页数据清理尚未确认完成，已暂停内嵌页面。可重试清除会话，或改用官方小程序。"
                else "本机网页数据清理仍未确认完成，已暂停内嵌页面。请先使用官方小程序，稍后重新打开本应用再试。"
            PangguaiProfilePhase.UNSUPPORTED, PangguaiProfilePhase.UNINITIALIZED -> "此设备暂不支持安全的独立网页会话。内嵌页面需要 Android 9 及以上和支持完整清理的系统 WebView，请使用下方官方小程序。"
            else -> "请选择上方钱包或运营商打开官方页面。清除本机网页数据不等于官方账号解绑，也不会退出支付宝。"
        }
        browserContainer.removeAllViews()
        browserContainer.addView(TextView(this).apply {
            text = message; textSize = 14f; setTextColor(Color.DKGRAY)
            gravity = android.view.Gravity.CENTER; setPadding(dp(20), dp(20), dp(20), dp(20))
        }, FrameLayout.LayoutParams(-1, -1))
        tell(if (phase == PangguaiProfilePhase.READY && PangguaiProfileSession.hasCompletedReset) "已清除本机胖乖独立网页数据；未执行官方解绑或服务器退出。" else message)
    }

    private fun confirmDiscard() {
        if (confirmation != null || !clear.isEnabled) return
        confirmation = AlertDialog.Builder(this)
            .setTitle("清除本机胖乖网页会话？")
            .setMessage("将关闭当前页面，清除胖乖独立网页的 Cookie、网页存储与缓存。不会清除教务或趣智数据，也不会解除官方账号绑定、取消订单或退出支付宝。")
            .setNegativeButton("取消", null)
            .setPositiveButton("清除") { _, _ -> PangguaiProfileSession.reset() }
            .create().apply { setOnDismissListener { confirmation = null }; show() }
    }

    private fun blockedNavigation() {
        tell("此链接或支付跳转暂不支持，已停止跳转。可继续查看官方页面，或点击下方按钮自行打开支付宝胖乖小程序。")
    }

    private fun restrictedResourceMessage() {
        tell("部分网页资源暂不支持。若登录、验证码或充值无法继续，请使用胖乖官方 App 或下方小程序；不要反复提交。")
    }

    private fun loadError(message: String) {
        failed = true
        progress.visibility = View.GONE
        tell(message)
    }

    private fun tell(message: String) { if (!closed) status.text = message }

    /** The only external destination is a compiled, fixed mini-app entry, never a provider-supplied URI. */
    private fun confirmMiniApp() {
        if (confirmation != null || PangguaiProfileSession.phase == PangguaiProfilePhase.CLEARING) return
        confirmation = AlertDialog.Builder(this)
            .setTitle("打开支付宝胖乖生活小程序？")
            .setMessage("支付宝小程序的登录账号与此网页独立，不会转移网页会话。请核对手机号/账户、实际运营商和金额后自行确认付款。本应用不会自动充值，也不能判断是否到账。")
            .setNegativeButton("取消") { _, _ -> tell("已取消打开支付宝。") }
            .setPositiveButton("打开支付宝") { _, _ -> launchMiniApp() }
            .setOnCancelListener { tell("已取消打开支付宝。") }
            .create().apply {
                setOnDismissListener { confirmation = null }
                show()
            }
    }

    @Suppress("DEPRECATION")
    private fun launchMiniApp() {
        if (closed || isFinishing || isDestroyed || PangguaiProfileSession.phase == PangguaiProfilePhase.CLEARING) return
        val target = Intent(Intent.ACTION_VIEW, Uri.parse(PangguaiOfficialPolicy.ALIPAY_MINI_APP))
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage(PangguaiOfficialPolicy.ALIPAY_PACKAGE)
        try {
            packageManager.getApplicationInfo(PangguaiOfficialPolicy.ALIPAY_PACKAGE, 0)
            val resolved = packageManager.resolveActivity(target, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo
            if (resolved == null || resolved.packageName != PangguaiOfficialPolicy.ALIPAY_PACKAGE ||
                !resolved.exported || !resolved.enabled || !resolved.applicationInfo.enabled) {
                tell("支付宝暂时无法打开此入口，请手动进入胖乖官方 App 或支付宝胖乖生活小程序。")
                return
            }
            startActivity(target)
            leftForAlipay = true
            tell("已请求打开支付宝，请在官方小程序核对运营商、金额与付款结果。")
        } catch (_: PackageManager.NameNotFoundException) {
            tell("未检测到支付宝，请手动进入胖乖官方 App，或先安装官方支付宝。")
        } catch (_: Exception) {
            tell("暂时无法打开支付宝，请手动进入胖乖官方 App 或支付宝胖乖生活小程序。")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val next = try { PangguaiOfficialPolicy.page(intent.getStringExtra(PAGE_EXTRA)) } catch (_: Exception) { return }
        setIntent(intent)
        navigate(next)
    }

    private fun goBackOrClose() {
        val view = web
        if (view != null && current(view) && view.canGoBack()) view.goBack() else finish()
    }

    @Deprecated("Legacy back dispatch for Android 12 and below")
    override fun onBackPressed() { goBackOrClose() }

    override fun onResume() {
        super.onResume()
        web?.takeIf { current(it) }?.onResume()
        if (leftForAlipay && ::status.isInitialized) {
            leftForAlipay = false
            if (PangguaiProfileSession.phase in setOf(PangguaiProfilePhase.READY, PangguaiProfilePhase.IN_USE))
                tell("已返回本应用，返回不代表充值成功。请在官方钱包或小程序核对余额与订单，未确认前不要重复付款。")
        }
    }

    override fun onPause() {
        web?.takeIf { current(it) }?.onPause()
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        // Retain only our fixed page ID; never serialize provider URLs, forms or WebView history.
        outState.putString(PAGE_EXTRA, page.id)
        outState.putBoolean("left_for_alipay", leftForAlipay)
        outState.putBoolean("show_official_page", web != null)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        closed = true
        confirmation?.dismiss()
        confirmation = null
        if (Build.VERSION.SDK_INT >= 33) backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        PangguaiProfileSession.removeObserver(profileListener)
        destroyCurrentView()
        super.onDestroy()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
