package org.handancampus.app.life

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import org.handancampus.app.BuildConfig
import org.handancampus.app.R
import org.handancampus.app.academic.SchoolSessionVault
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class ParcelDirectoryActivity : AppCompatActivity() {
    private lateinit var refreshLayout: SwipeRefreshLayout
    private lateinit var scroll: ScrollView
    private lateinit var content: LinearLayout
    private val handler = Handler(Looper.getMainLooper())
    private val poll = Runnable { perform { poll() } }
    private var active = false
    private var busy = false
    private var settings = false
    private var captureLocked = false
    private var latest = JSONObject()
    private var shortcutMessage: String? = null
    private var compatibilityProvider: String? = null
    private var mainScroll = 0

    private val state get() = latest.optString("state")
    private val connected get() = latest.optBoolean("connected")
    private val hasPending get() = latest.has("userCode")
    private val snapshot get() = latest.optJSONArray("items")?.takeUnless { state in hiddenSnapshotStates }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        settings = savedInstanceState?.getBoolean("settings") ?: false
        mainScroll = savedInstanceState?.getInt("mainScroll") ?: 0
        // The parcel cards and the compact toolbar share a simple light canvas.
        // Software rendering avoids a blank first row on older Android renderers.
        window.decorView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        @Suppress("DEPRECATION")
        window.statusBarColor = backgroundColor
        @Suppress("DEPRECATION")
        window.navigationBarColor = backgroundColor
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val root = FrameLayout(this).apply { setBackgroundColor(backgroundColor) }
        content = column().apply {
            setPadding(dp(10), 0, dp(10), dp(18))
        }
        scroll = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
            addView(content, FrameLayout.LayoutParams(-1, -2))
        }
        refreshLayout = SwipeRefreshLayout(this).apply {
            setColorSchemeColors(blue)
            setOnRefreshListener { refresh() }
            addView(scroll, FrameLayout.LayoutParams(-1, -1))
        }
        root.addView(refreshLayout, FrameLayout.LayoutParams(-1, -1))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            root.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(root)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = back()
        })
        render()
        if (!settings) scroll.post { scroll.scrollTo(0, mainScroll) }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("settings", settings)
        outState.putInt("mainScroll", if (settings) mainScroll else scroll.scrollY)
        super.onSaveInstanceState(outState)
    }

    override fun onResume() {
        super.onResume()
        active = true
        perform { if (hasPending) poll() else refresh(false) }
    }

    override fun onPause() {
        active = false
        handler.removeCallbacks(poll)
        super.onPause()
    }

    private fun back() {
        if (settings) showSettings(false) else finish()
    }

    private fun showSettings(show: Boolean) {
        if (show == settings) return
        if (show) mainScroll = scroll.scrollY
        settings = show
        render(keepScroll = false)
        if (!show) scroll.post { scroll.scrollTo(0, mainScroll) }
    }

    private fun addHeader() {
        val header = row().apply {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(58)
        }
        val title = text(if (settings) "取件设置" else "校园取件", 25, titleColor, bold = true)
        ViewCompat.setAccessibilityHeading(title, true)
        header.addView(iconButton(R.drawable.parcel_arrow_back, "返回", titleColor) { back() },
            LinearLayout.LayoutParams(dp(44), dp(48)).apply { marginStart = -dp(10) })
        header.addView(title, LinearLayout.LayoutParams(0, -2, 1f).apply {
            marginStart = dp(4)
            marginEnd = dp(7)
        })
        if (!settings) {
            header.addView(iconButton(R.drawable.parcel_settings, "设置", titleColor) { showSettings(true) },
                LinearLayout.LayoutParams(dp(46), dp(48)).apply { marginEnd = -dp(10) })
        }
        header.addTo(content)
        refreshLayout.isEnabled = !settings
    }

    private fun refresh() {
        if (settings) {
            refreshLayout.isRefreshing = false
            return
        }
        perform { if (hasPending) poll() else refresh(true) }
        if (!busy) refreshLayout.isRefreshing = false
    }

    private fun perform(operation: ParcelDirectory.() -> JSONObject) {
        if (!active || busy) return
        busy = true
        handler.removeCallbacks(poll)
        render()
        queue.execute {
            val result = runCatching {
                directory()?.operation() ?: JSONObject().put("state", "unconfigured")
            }.getOrNull()
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                latest = result ?: JSONObject(latest.toString()).put("state", "unavailable")
                busy = false
                refreshLayout.isRefreshing = false
                render()
                if (active && hasPending) handler.postDelayed(poll, 5000)
            }
        }
    }

    private fun directory(): ParcelDirectory? {
        engine?.let { return it }
        if (!BuildConfig.DEBUG || !BuildConfig.PARCEL_PILOT) return null
        val origin = ParcelDirectory.approvedOrigin(BuildConfig.PARCEL_DIRECTORY_ORIGIN) ?: return null
        val client = BuildConfig.PARCEL_DIRECTORY_CLIENT.takeIf(String::isNotBlank) ?: return null
        val vault = SchoolSessionVault(applicationContext, "parcel_directory_v1", "handan.parcel.directory.v1", 3_050_000)
        return ParcelDirectory(origin, client, {
            vault.restore()?.let {
                val stored = JSONObject(it)
                if (stored.optString("origin") == origin.toString() && stored.optString("client") == client) stored.getString("value")
                else { vault.clear(); null }
            }
        }, { vault.save(JSONObject().put("origin", origin.toString()).put("client", client).put("value", it).toString()) },
            vault::clear).also { engine = it }
    }

    private fun openProviderPage(uri: ParcelDirectory.() -> URI?, missing: String) {
        perform {
            val verified = uri()
            runOnUiThread {
                if (!active || isFinishing) return@runOnUiThread
                if (verified == null) dialog("暂时无法打开", missing)
                else runCatching {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(verified.toString())).addCategory(Intent.CATEGORY_BROWSABLE))
                }.onFailure { dialog("暂时无法打开", "请检查手机浏览器后重试。") }
            }
            state()
        }
    }

    private fun render(keepScroll: Boolean = true) {
        val offset = if (keepScroll) scroll.scrollY else 0
        val privateData = !settings && snapshot != null || settings && hasPending
        if (privateData != captureLocked) {
            if (privateData) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            captureLocked = privateData
        }
        content.removeAllViews()
        addHeader()
        if (settings) renderSettings() else renderMain()
        scroll.post { scroll.scrollTo(0, offset) }
    }

    private fun renderMain() {
        val parcels = snapshot
        val overview = column().apply {
            background = rounded(overviewColor, 18)
            setPadding(dp(18), dp(17), dp(18), dp(17))
            minimumHeight = dp(140)
        }
        text("邯郸学院菜鸟驿站", 16, muted).addTo(overview)
        val summary = if (parcels != null) {
            row().apply {
                gravity = Gravity.BOTTOM
                addView(text(parcels.length().toString(), 36, blue, bold = true))
                addView(text("件快递待领取", 19, blue), LinearLayout.LayoutParams(-2, -2).apply {
                    marginStart = dp(9)
                    bottomMargin = dp(4)
                })
            }
        } else text(if (busy) "正在同步" else "待取件数量未知", 25, blue, bold = true)
        summary.addTo(overview, gap = 12)
        val phone = latest.optString("maskedPhone").takeIf(String::isNotBlank)
        val status = text(listOfNotNull(phone?.let { "手机号 $it" }, syncLabel()).joinToString(" · "), 14, overviewDetail)
        status.addTo(overview, gap = 12)
        ViewCompat.setAccessibilityLiveRegion(status, View.ACCESSIBILITY_LIVE_REGION_POLITE)
        overview.addTo(content)

        if (parcels != null && state !in setOf("ready", "empty") && !busy) {
            text("正在显示上次同步的记录", 13, muted).addTo(content, gap = 12)
        }
        if (parcels != null && parcels.length() > 0) {
            addParcels(parcels)
        } else {
            val card = whiteCard()
            val (title, detail) = emptyCopy(parcels)
            text(title, 16, ink, bold = true).addTo(card)
            text(detail, 14, muted).addTo(card, gap = 6)
            if (!busy && state in setOf("disconnected", "expired", "rejected", "denied", "forbidden")) {
                action("前往取件设置", blue, overviewColor) { showSettings(true) }.addTo(card, gap = 10)
            }
            card.addTo(content, gap = 14)
        }
        val links = row().apply {
            addView(shortcut("淘宝出库码", "taobao", orange, paleOrange), LinearLayout.LayoutParams(0, -2, 1f))
            addView(shortcut("拼多多出库码", "pinduoduo", red, paleRed), LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(9) })
        }
        links.addTo(content, gap = 14)
        shortcutMessage?.let {
            val message = text(it, 14, muted)
            ViewCompat.setAccessibilityLiveRegion(message, View.ACCESSIBILITY_LIVE_REGION_POLITE)
            message.addTo(content, gap = 10)
        }
        compatibilityProvider?.let { provider ->
            action("使用系统兼容方式打开", blue, overviewColor) { launchShortcut(provider, system = true) }.addTo(content, gap = 8)
        }
    }

    private fun addParcels(parcels: JSONArray) {
        for (index in 0 until parcels.length()) {
            val item = parcels.getJSONObject(index)
            val card = whiteCard().apply { minimumHeight = dp(94) }
            val heading = row().apply { gravity = Gravity.TOP }
            val carrier = item.getString("carrier")
            heading.addView(text(carriers[carrier] ?: carrier.uppercase(Locale.ROOT), 16, muted),
                LinearLayout.LayoutParams(0, -2, 1f))
            val arrival = item.optLong("arrivedAt").takeIf { it > 0 }?.let(::dateLabel) ?: "入库时间未提供"
            heading.addView(text(arrival, 16, muted).apply { gravity = Gravity.END }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(8) })
            heading.addTo(card)

            val code = item.optString("pickupCode").takeIf(String::isNotBlank)
            val controls = row().apply { gravity = Gravity.CENTER_VERTICAL }
            controls.addView(text(code ?: "取件码暂未提供", if (code == null) 15 else 34, ink, bold = code != null).apply {
                if (code != null) {
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                    maxLines = 3
                    ViewCompat.setAccessibilityHeading(this, true)
                }
            }, LinearLayout.LayoutParams(0, -2, 1f))
            if (code != null) {
                controls.addView(action("复制", muted, Color.WHITE, stroke = border) {
                    copy("取件码", code, sensitive = true)
                }, LinearLayout.LayoutParams(dp(65), -2).apply { marginStart = dp(9) })
            }
            controls.addTo(card, gap = 3)
            card.addTo(content, gap = 14)
        }
    }

    private fun renderSettings() {
        val account = whiteCard()
        text("账号授权", 17, ink, bold = true).addTo(account)
        text(when {
            state == "unconfigured" -> "未配置取件服务"
            hasPending -> "等待服务商确认授权"
            connected -> "已授权"
            state in authorizationErrors -> "授权失效"
            else -> "未授权"
        }, 14, muted).addTo(account, gap = 6)
        when {
            state == "unconfigured" -> action("查看授权说明", blue, overviewColor) {
                dialog("账号授权", "当前版本尚未配置取件服务。接通后，在服务商页面完成账号授权。")
            }.addTo(account, gap = 10)
            hasPending -> {
                text(latest.getString("userCode"), 24, ink, bold = true).addTo(account, gap = 8)
                action("打开授权网页", blue, overviewColor) {
                    openProviderPage(ParcelDirectory::verificationUri, "本次授权已过期，请重新发起。")
                }.apply { isEnabled = !busy }.addTo(account, gap = 8)
                action("取消授权", muted, backgroundColor) { perform { disconnect() } }
                    .apply { isEnabled = !busy }.addTo(account, gap = 8)
            }
            connected -> action("断开授权", red, paleRed) {
                AlertDialog.Builder(this).setTitle("断开授权？").setMessage("会清除这台手机上的授权和取件缓存。")
                    .setNegativeButton("取消", null).setPositiveButton("断开") { _, _ -> perform { disconnect() } }.show()
            }.apply { isEnabled = !busy }.addTo(account, gap = 10)
            else -> action(if (state in authorizationErrors) "重新授权" else "授权查询包裹", blue, overviewColor) {
                perform { begin() }
            }.apply { isEnabled = !busy && state.isNotEmpty() }.addTo(account, gap = 10)
        }
        account.addTo(content)

        val phone = whiteCard()
        text("手机号绑定", 17, ink, bold = true).addTo(phone)
        text(latest.optString("maskedPhone").ifBlank { "当前未取得绑定信息" }, 14, muted).addTo(phone, gap = 6)
        action("管理绑定手机号", blue, overviewColor) {
            when {
                latest.optBoolean("canManagePhone") -> openProviderPage(ParcelDirectory::phoneManagementUri, "服务商暂未提供手机号管理入口。")
                state == "unconfigured" -> dialog("手机号绑定", "接通取件服务后，可由服务商验证和管理手机号。")
                !connected -> dialog("手机号绑定", "请先完成账号授权。")
                else -> dialog("手机号绑定", "当前服务商未提供手机号管理入口。")
            }
        }.apply { isEnabled = !busy }.addTo(phone, gap = 10)
        phone.addTo(content, gap = 12)

        val sync = whiteCard()
        text("同步状态", 17, ink, bold = true).addTo(sync)
        text(syncLabel(), 14, muted).addTo(sync, gap = 6)
        val last = latest.optLong("updatedAt").takeIf { it > 0 }
        text(last?.let { "最近成功同步  ${dateLabel(it)}" } ?: "尚无成功同步记录", 14, muted).addTo(sync, gap = 4)
        action("检查同步", blue, overviewColor) {
            if (state == "unconfigured") dialog("同步不可用", "取件服务尚未配置。")
            else if (hasPending) perform { poll() }
            else if (!connected) dialog("同步不可用", "请先完成账号授权。")
            else perform { refresh(true) }
        }.apply { isEnabled = !busy }.addTo(sync, gap = 10)
        sync.addTo(content, gap = 12)

        val diagnostics = whiteCard()
        text("脱敏诊断", 17, ink, bold = true).addTo(diagnostics)
        text("包含版本、连接和同步状态。", 14, muted).addTo(diagnostics, gap = 6)
        action("查看诊断", blue, overviewColor) {
            val report = listOf(
                "版本  ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                "Android  ${android.os.Build.VERSION.SDK_INT}",
                "数据源  " + if (providerConfigured()) "已配置" else "未配置",
                "账号  " + if (connected) "已授权" else "未授权",
                "状态  " + state.ifBlank { "initializing" },
                "成功同步记录  " + if (latest.has("updatedAt")) "有" else "无",
            ).joinToString("\n")
            AlertDialog.Builder(this).setTitle("脱敏诊断").setMessage(report)
                .setNegativeButton("关闭", null).setPositiveButton("复制诊断") { _, _ -> copy("取件诊断", report) }.show()
        }.addTo(diagnostics, gap = 10)
        diagnostics.addTo(content, gap = 12)
    }

    private fun syncLabel(): String = if (busy) "正在同步" else when (state) {
        "" -> "正在读取本机状态"
        "unconfigured" -> "未配置数据源"
        "disconnected" -> "未授权"
        "pending" -> "等待授权"
        "waiting" -> "等待首次同步"
        "empty", "ready" -> "已同步"
        "denied" -> "已取消授权"
        "expired", "rejected" -> "授权失效"
        "forbidden" -> "账号无查询权限"
        "rateLimited" -> "同步受限，请稍后重试"
        "incomplete" -> "同步失败 · 列表不完整"
        else -> "同步失败"
    }

    private fun emptyCopy(parcels: JSONArray?): Pair<String, String> = when {
        busy -> "正在检查取件状态" to "请稍候。"
        state == "unconfigured" -> "取件数据源未配置" to "暂时无法同步待取包裹。出库时可打开下方官方入口。"
        state == "disconnected" -> "尚未授权查询" to "在取件设置完成账号授权后，即可同步包裹。"
        state in authorizationErrors -> "授权已失效" to "请在取件设置重新授权。"
        state == "denied" -> "已取消授权" to "可在取件设置重新发起授权。"
        state == "forbidden" -> "账号无查询权限" to "请在取件设置检查账号授权。"
        state == "pending" -> "等待账号授权" to "请在取件设置打开授权网页。"
        state == "waiting" -> "等待首次同步" to "下拉检查待取包裹。"
        state == "rateLimited" -> "同步请求受限" to "请稍后下拉重试。"
        state == "incomplete" -> "包裹列表未同步完整" to "请稍后下拉重试。"
        state == "empty" && parcels != null -> "暂无待取快递" to "有新包裹入库后，下拉即可刷新。"
        else -> "暂时无法同步" to "请检查网络或稍后下拉重试。"
    }

    private fun launchShortcut(provider: String, system: Boolean = false) {
        val name = if (provider == "taobao") "淘宝" else "拼多多"
        val target = if (system) ParcelShortcutContract.target(provider, setOf("provider", "mode"), "system")
            else ParcelShortcutContract.target(provider, setOf("provider"))
        val launcher = ParcelAndroidLauncher(this)
        val result = ParcelShortcutContract.launch(target, object : ParcelLaunchHost {
            override fun isActive() = active && !isFinishing && !isDestroyed
            override fun open(target: ParcelShortcutTarget, route: ParcelLaunchRoute) = launcher.open(target, route)
        })
        compatibilityProvider = if (!system && result in listOf(ParcelLaunchStatus.UNAVAILABLE, ParcelLaunchStatus.APP_OPENED)) provider else null
        shortcutMessage = when (result) {
            ParcelLaunchStatus.OPENED -> "已请求打开${name}出库码。"
            ParcelLaunchStatus.APP_OPENED -> "已打开${name}，请在官方 App 内进入出库码。"
            ParcelLaunchStatus.WEB_OPENED -> "已请求打开${name}官方网页。"
            ParcelLaunchStatus.SYSTEM_OPENED -> "已交给系统打开${name}链接。"
            ParcelLaunchStatus.CANCELLED -> "已取消打开${name}。"
            ParcelLaunchStatus.UNAVAILABLE -> "暂时无法打开${name}出库码。"
        }
        render()
    }

    private fun shortcut(label: String, provider: String, color: Int, surface: Int) = column().apply {
        gravity = Gravity.CENTER
        minimumHeight = dp(86)
        setPadding(dp(5), dp(12), dp(5), dp(12))
        background = pressable(surface, 14)
        contentDescription = label
        ViewCompat.setImportantForAccessibility(this, ViewCompat.IMPORTANT_FOR_ACCESSIBILITY_YES)
        ViewCompat.setAccessibilityDelegate(this, object : androidx.core.view.AccessibilityDelegateCompat() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: androidx.core.view.accessibility.AccessibilityNodeInfoCompat) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.Button"
            }
        })
        addView(icon(R.drawable.parcel_qr, color), LinearLayout.LayoutParams(dp(21), dp(21)))
        text(label, 16, color, bold = true).apply {
            gravity = Gravity.CENTER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }.addTo(this, gap = 9)
        isFocusable = true
        setOnClickListener { launchShortcut(provider) }
    }

    private fun providerConfigured() = BuildConfig.DEBUG && BuildConfig.PARCEL_PILOT &&
        ParcelDirectory.approvedOrigin(BuildConfig.PARCEL_DIRECTORY_ORIGIN) != null &&
        BuildConfig.PARCEL_DIRECTORY_CLIENT.isNotBlank()

    private fun copy(label: String, value: String, sensitive: Boolean = false) {
        val clip = ClipData.newPlainText(label, value)
        if (sensitive && android.os.Build.VERSION.SDK_INT >= 24) {
            clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
        }
        getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
        if (android.os.Build.VERSION.SDK_INT < 33) android.widget.Toast.makeText(this, "已复制$label", android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun dateLabel(value: Long): String {
        val zone = TimeZone.getTimeZone("Asia/Shanghai")
        val today = Calendar.getInstance(zone)
        val input = Calendar.getInstance(zone).apply { timeInMillis = value }
        fun sameDay() = today.get(Calendar.YEAR) == input.get(Calendar.YEAR) &&
            today.get(Calendar.DAY_OF_YEAR) == input.get(Calendar.DAY_OF_YEAR)
        val prefix = if (sameDay()) "今天 " else {
            today.add(Calendar.DAY_OF_YEAR, -1)
            if (sameDay()) "昨天 " else ""
        }
        val format = SimpleDateFormat(if (prefix.isEmpty()) "M月d日 HH:mm" else "HH:mm", Locale.SIMPLIFIED_CHINESE)
        format.timeZone = zone
        return prefix + format.format(value)
    }

    private fun dialog(title: String, detail: String) {
        AlertDialog.Builder(this).setTitle(title).setMessage(detail).setPositiveButton("好的", null).show()
    }

    private fun dp(value: Int) = (resources.displayMetrics.density * value).roundToInt()
    private fun column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun row() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
    private fun whiteCard() = column().apply {
        background = rounded(Color.WHITE, 14)
        setPadding(dp(14), dp(13), dp(14), dp(13))
    }
    private fun View.addTo(group: LinearLayout, gap: Int = 0) {
        group.addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(gap) })
    }
    private fun rounded(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
        if (stroke != null) setStroke(dp(1), stroke)
    }
    private fun pressable(color: Int, radius: Int, stroke: Int? = null) = RippleDrawable(
        ColorStateList.valueOf(0x17213757), rounded(color, radius, stroke), rounded(Color.WHITE, radius),
    )
    private fun text(label: String, size: Int, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = label
        textSize = size.toFloat()
        setTextColor(color)
        includeFontPadding = false
        if (bold) typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private fun action(label: String, color: Int, fill: Int, stroke: Int? = null, onClick: () -> Unit) =
        androidx.appcompat.widget.AppCompatButton(this).apply {
            text = label
            textSize = 15f
            setAllCaps(false)
            setTextColor(color)
            minimumHeight = dp(44)
            minHeight = dp(44)
            minWidth = 0
            minimumWidth = 0
            setPadding(dp(6), dp(6), dp(6), dp(6))
            stateListAnimator = null
            background = pressable(fill, if (stroke == null) 11 else 22, stroke)
            setOnClickListener { onClick() }
        }
    private fun icon(resource: Int, color: Int) = ImageView(this).apply {
        setImageResource(resource)
        imageTintList = ColorStateList.valueOf(color)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        scaleType = ImageView.ScaleType.FIT_CENTER
    }
    private fun iconButton(resource: Int, label: String, color: Int, click: () -> Unit) = FrameLayout(this).apply {
        contentDescription = label
        isFocusable = true
        background = pressable(Color.TRANSPARENT, 12)
        addView(icon(resource, color), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        setOnClickListener { click() }
    }

    companion object {
        private val queue = Executors.newSingleThreadExecutor()
        private var engine: ParcelDirectory? = null
        private val hiddenSnapshotStates = setOf("unconfigured", "expired", "rejected", "forbidden")
        private val authorizationErrors = setOf("expired", "rejected")
        private val backgroundColor = Color.rgb(244, 246, 250)
        private val overviewColor = Color.rgb(230, 237, 253)
        private val titleColor = Color.rgb(43, 46, 49)
        private val ink = Color.rgb(35, 56, 89)
        private val muted = Color.rgb(87, 92, 99)
        private val overviewDetail = Color.rgb(75, 107, 161)
        private val blue = Color.rgb(35, 72, 132)
        private val orange = Color.rgb(180, 59, 5)
        private val paleOrange = Color.rgb(252, 240, 228)
        private val red = Color.rgb(184, 27, 29)
        private val paleRed = Color.rgb(252, 236, 235)
        private val border = Color.rgb(211, 214, 218)
        private val carriers = mapOf(
            "zto" to "中通快递", "zhongtong" to "中通快递", "yto" to "圆通快递", "yuantong" to "圆通快递",
            "yunda" to "韵达快递", "sto" to "申通快递", "shentong" to "申通快递", "sf" to "顺丰速运", "shunfeng" to "顺丰速运",
            "jd" to "京东物流", "jdwl" to "京东物流", "ems" to "邮政 EMS", "jtexpress" to "极兔速递", "jt" to "极兔速递",
        )
    }
}
