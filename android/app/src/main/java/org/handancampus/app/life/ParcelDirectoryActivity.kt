package org.handancampus.app.life

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import org.handancampus.app.BuildConfig
import org.handancampus.app.academic.SchoolSessionVault
import org.json.JSONObject
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

class ParcelDirectoryActivity : AppCompatActivity() {
    private lateinit var content: LinearLayout
    private val handler = Handler(Looper.getMainLooper())
    private val tick = Runnable { perform { poll() } }
    private var active = false
    private var busy = false
    private var latest = JSONObject()
    private lateinit var status: TextView
    private val copyLabel = "复制取件码"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG || !BuildConfig.PARCEL_PILOT) {
            finish()
            return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val inset = (20 * resources.displayMetrics.density).toInt()
        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(inset, inset, inset, inset)
        }
        setContentView(ScrollView(this).apply { addView(content) })
        status = TextView(this).apply { accessibilityLiveRegion = TextView.ACCESSIBILITY_LIVE_REGION_POLITE }
        render()
    }

    override fun onResume() {
        super.onResume()
        if (!::content.isInitialized) return
        active = true
        perform { if (verificationUri() == null) refresh(false) else poll() }
    }

    override fun onPause() {
        active = false
        handler.removeCallbacks(tick)
        super.onPause()
    }

    private fun perform(operation: ParcelDirectory.() -> JSONObject) {
        if (busy || !active) return
        busy = true
        status.text = "正在连接…"
        handler.removeCallbacks(tick)
        queue.execute {
            val result = try { directory()?.operation() ?: JSONObject().put("state", "unconfigured") }
                catch (_: Exception) { JSONObject(latest.toString()).put("state", "unavailable") }
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                busy = false
                latest = result
                render()
                if (active && result.has("userCode")) handler.postDelayed(tick, 5000)
            }
        }
    }

    private fun directory(): ParcelDirectory? {
        if (engine != null) return engine
        val origin = ParcelDirectory.approvedOrigin(BuildConfig.PARCEL_DIRECTORY_ORIGIN) ?: return null
        val client = BuildConfig.PARCEL_DIRECTORY_CLIENT.takeIf { it.isNotBlank() } ?: return null
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

    private fun openPage() {
        // The URI is kept in the native client and always validated against the configured HTTPS origin.
        perform {
            verificationUri()?.let { uri ->
                runOnUiThread {
                    if (active && !isFinishing) runCatching {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri.toString())).addCategory(Intent.CATEGORY_BROWSABLE))
                    }.onFailure { status.text = "无法打开授权网页" }
                }
            }
            state()
        }
    }

    private fun render() {
        content.removeAllViews()
        button("返回") { finish() }
        title("待取包裹 · 联调", 25)
        content.addView(status)
        val state = latest.optString("state")
        status.text = when (state) {
            "unconfigured" -> "本测试包尚未配置获准提供待取列表的数据源。"
            "disconnected" -> "连接包裹数据源后可在此同步待取包裹。"
            "pending" -> "请在授权网页完成验证，返回后自动检查。"
            "waiting" -> "授权已保存，等待首次同步。"
            "empty" -> "暂无待取包裹。"
            "ready" -> "已同步待取包裹。"
            "denied" -> "你取消了本次授权。"
            "expired", "rejected" -> "授权已过期，请重新授权。"
            "rateLimited" -> "服务限制请求频率，请稍后重试。"
            "forbidden" -> "此账号没有包裹查询权限。"
            "incomplete" -> "服务没有返回完整列表。"
            "unavailable" -> "暂时无法同步，请稍后重试。"
            else -> "正在读取本机授权…"
        }
        if (state.isEmpty() || state == "unconfigured") return
        if (latest.has("userCode")) {
            title(latest.getString("userCode"), 24)
            button("打开授权网页") { openPage() }
            button("取消授权") { perform { disconnect() } }
            return
        }
        if (latest.optBoolean("connected")) {
            button("同步待取包裹") { perform { refresh(true) } }
            if (latest.has("updatedAt") && state !in listOf("expired", "rejected", "forbidden")) {
                val date = DateFormat.getDateTimeInstance().format(Date(latest.getLong("updatedAt")))
                title("最近成功同步 $date", 13)
                val list = latest.getJSONArray("items")
                for (index in 0 until list.length()) {
                    val item = list.getJSONObject(index)
                    val station = item.optString("station")
                    if (station.isNotBlank()) title(station, 16)
                    val code = item.optString("pickupCode")
                    title(code.ifBlank { "数据源暂未返回取件码" }, if (code.isBlank()) 15 else 30)
                    title(item.getString("trackingNumber"), 13)
                    if (code.isNotBlank()) button(copyLabel) {
                        val clip = ClipData.newPlainText("取件码", code)
                        if (android.os.Build.VERSION.SDK_INT >= 24) {
                            clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
                        }
                        getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                        status.text = "已复制取件码"
                    }
                }
            }
            button("断开连接") {
                AlertDialog.Builder(this).setMessage("断开连接会清除本机的授权和包裹缓存。")
                    .setNegativeButton("取消", null).setPositiveButton("断开") { _, _ -> perform { disconnect() } }.show()
            }
        } else {
            button("授权查询包裹") { perform { begin() } }
        }
    }

    private fun title(value: String, size: Int) {
        content.addView(TextView(this).apply {
            text = value
            textSize = size.toFloat()
            if (size >= 24) setTypeface(typeface, Typeface.BOLD)
            setPadding(0, (12 * resources.displayMetrics.density).toInt(), 0, 0)
        })
    }

    private fun button(value: String, action: () -> Unit) {
        content.addView(Button(this).apply { text = value; setOnClickListener { action() } })
    }

    companion object {
        private val queue = Executors.newSingleThreadExecutor()
        private var engine: ParcelDirectory? = null
    }
}
