package org.handancampus.app.life

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.text.InputType
import android.view.WindowManager
import android.widget.*
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.academic.SchoolSessionVault
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name = "QuzhiCampus")
class QuzhiPlugin : Plugin() {
    companion object { private val lifecycle = QuzhiLifecycleFence() }
    private val owner = lifecycle.admit()
    private fun <T> owned(work: () -> T): T = lifecycle.owned(owner, work)
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val client = QuzhiClient()
    private val vault by lazy { SchoolSessionVault(context, "quzhi_wallet_v081", "handan.quzhi.wallet.v081", 262144) }
    private var state = JSONObject()
    private var loaded = false
    private var activeLogin: AlertDialog? = null
    private var cancelLogin: (() -> Unit)? = null
    private fun restoreState() = owned {
        if (!loaded) {
            state = try { vault.restore()?.let { JSONObject(it) } ?: JSONObject() } catch (_: Exception) { JSONObject() }
            loaded = true
        }
    }
    private fun currentMonth(): String = SimpleDateFormat("yyyy-MM", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }.format(Date())
    private fun session() = state.optJSONObject("session") ?: throw QuzhiFailure("AUTH")
    private fun publicState(): JSObject {
        val result = state.optJSONObject("snapshot")?.let { JSONObject(it.toString()) } ?: JSONObject()
        val session = state.optJSONObject("session")
        result.put("connected", session != null).put("expired", state.optBoolean("expired", false))
            .put("phone", if (session == null) "" else QuzhiProtocol.maskedPhone(session))
        return JSObject.fromJSONObject(result)
    }
    private fun code(error: Exception): String = if (error is QuzhiLifecycleCancelled) "CANCELLED" else (error as? QuzhiFailure)?.kind ?: "NETWORK"
    private fun message(code: String): String = when (code) {
        "CANCELLED" -> "操作已取消，请重新打开趣智校园"
        "PHONE" -> "请输入正确的手机号"
        "PASSWORD" -> "请输入趣智校园密码"
        "CREDENTIALS" -> "账号或密码未通过验证，请检查后重试"
        "AUTH" -> "趣智登录已失效，请重新连接"
        "VERIFY" -> "平台要求验证或稍后重试，请勿连续提交"
        "FORMAT" -> "平台返回的信息暂时无法识别，已保留上次数据"
        "UNVERIFIED_UNITS" -> "余额单位暂无法核对，已保留上次数据"
        "SERVICE" -> "趣智未完成这次请求，请稍后重试"
        "MONTH" -> "请选择有效月份"
        else -> "连接趣智失败，请检查网络后重试"
    }
    private fun run(call: PluginCall, work: () -> Unit) {
        if (!busy.compareAndSet(false, true)) { call.reject("趣智操作正在进行，请稍候", "BUSY"); return }
        try {
            executor.execute {
                try { restoreState(); work(); owned { call.resolve(publicState()) } }
                catch (e: Exception) { call.reject(message(code(e)), code(e)) }
                finally { busy.set(false) }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            busy.set(false); call.reject(message("CANCELLED"), "CANCELLED")
        }
    }
    @PluginMethod fun getSnapshot(call: PluginCall) = run(call) {}
    @PluginMethod fun logout(call: PluginCall) = run(call) { owned { vault.clear(); state = JSONObject() } }

    @PluginMethod fun refresh(call: PluginCall) = run(call) {
        val next = QuzhiRefresh.execute(owned { JSONObject(state.toString()) }, call.getString("month") ?: currentMonth(),
            { path, args -> client.request(path, args) }, { System.currentTimeMillis() })
        owned { vault.save(next.toString()); state = next }
    }

    /** Credentials are entered in native widgets, never passed through the JS bridge. */
    @PluginMethod fun login(call: PluginCall) {
        if (!busy.compareAndSet(false, true)) { call.reject("趣智操作正在进行，请稍候", "BUSY"); return }
        activity.runOnUiThread {
            try { restoreState() } catch (_: QuzhiLifecycleCancelled) {
                busy.set(false); call.reject(message("CANCELLED"), "CANCELLED"); return@runOnUiThread
            }
            val attempt = QuzhiLifecycleFence.Attempt(owner)
            val padding = (20 * context.resources.displayMetrics.density).toInt()
            val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(padding, 0, padding, 0) }
            fun label(text: String) = TextView(activity).apply { this.text = text; setPadding(0, padding / 2, 0, padding / 2) }
            content.addView(label("密码登录已有趣智校园账户。短信登录可能由平台创建新账户，请先阅读并确认提示。密码与验证码不保存。"))
            val phone = EditText(activity).apply { hint = "趣智校园手机号"; inputType = InputType.TYPE_CLASS_PHONE; setSingleLine(); filters = arrayOf(android.text.InputFilter.LengthFilter(11)) }
            val mode = Switch(activity).apply { text = "使用短信验证码"; isChecked = false }
            val secret = EditText(activity).apply { hint = "趣智校园密码"; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; setSingleLine(); filters = arrayOf(android.text.InputFilter.LengthFilter(128)) }
            val send = Button(activity).apply { text = "发送验证码"; visibility = android.view.View.GONE }
            val smsConsent = CheckBox(activity).apply { text = "若手机号未注册，趣智平台可能创建账户。我确认使用短信方式。"; visibility = android.view.View.GONE }
            val status = label("")
            content.addView(phone); content.addView(mode); content.addView(secret); content.addView(send); content.addView(smsConsent); content.addView(status)
            val dialog = AlertDialog.Builder(activity).setTitle("连接趣智校园").setView(content)
                .setPositiveButton("登录", null).setNegativeButton("取消", null).create()
            var inFlight = false
            var cancelled = false
            var finished = false
            fun cancel() {
                if (finished) return
                lifecycle.cancel(attempt)
                cancelled = true; finished = true
                phone.text.clear(); secret.text.clear()
                if (!inFlight) busy.set(false)
                call.reject("已取消登录", "CANCELLED")
            }
            fun enabled(value: Boolean) {
                inFlight = !value
                phone.isEnabled = value; secret.isEnabled = value; mode.isEnabled = value; smsConsent.isEnabled = value
                send.isEnabled = value; dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = value
            }
            mode.setOnCheckedChangeListener { _, sms ->
                secret.text.clear(); secret.hint = if (sms) "短信验证码" else "趣智校园密码"
                secret.inputType = if (sms) InputType.TYPE_CLASS_NUMBER else InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                send.visibility = if (sms) android.view.View.VISIBLE else android.view.View.GONE
                smsConsent.visibility = send.visibility; smsConsent.isChecked = false
                status.text = ""
            }
            activeLogin = dialog
            cancelLogin = { cancel() }
            dialog.setOnDismissListener { activeLogin = null; cancelLogin = null }
            dialog.setOnCancelListener { cancel() }
            dialog.setOnShowListener {
                dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener { cancel(); dialog.dismiss() }
                send.setOnClickListener {
                    val number = try { QuzhiProtocol.phone(phone.text.toString()) } catch (e: Exception) { status.text = message(code(e)); return@setOnClickListener }
                    val seconds = try { lifecycle.reserveSms(owner, number, android.os.SystemClock.elapsedRealtime()) }
                    catch (_: QuzhiLifecycleCancelled) { cancel(); dialog.dismiss(); return@setOnClickListener }
                    if (seconds > 0) { status.text = "请在 $seconds 秒后重新发送"; return@setOnClickListener }
                    // Cooldown starts before the request, including timeouts: no accidental repeated SMS.
                    enabled(false); status.text = "正在发送…"
                    try { owned { executor.execute {
                        var result = "验证码已发送，请查看短信"
                        try { client.request("user/verification/code/get", QuzhiProtocol.common + mapOf("telephone" to number, "secret" to QuzhiProtocol.smsSecret(number), "typeId" to "3", "platform" to "1")) }
                        catch (e: Exception) { result = message(code(e)) }
                        activity.runOnUiThread { if (cancelled || !lifecycle.isCurrent(owner)) { cancel(); dialog.dismiss(); busy.set(false) } else { enabled(true); status.text = result } }
                    } } } catch (_: QuzhiLifecycleCancelled) { cancel(); dialog.dismiss(); busy.set(false) }
                    catch (_: java.util.concurrent.RejectedExecutionException) { cancel(); dialog.dismiss(); busy.set(false) }
                }
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    val number = try { QuzhiProtocol.phone(phone.text.toString()) } catch (e: Exception) { status.text = message(code(e)); return@setOnClickListener }
                    val sms = mode.isChecked
                    if (sms && !smsConsent.isChecked) { status.text = "请先确认短信登录的账户创建提示，或切换为密码登录。"; return@setOnClickListener }
                    val value = secret.text.toString()
                    if (sms && !value.matches(Regex("[0-9]{4,8}"))) { status.text = "请输入短信中的验证码"; return@setOnClickListener }
                    if (!sms && value.isEmpty()) { status.text = "请输入趣智校园密码"; return@setOnClickListener }
                    enabled(false); status.text = "正在验证账户与余额…"
                    try { owned { executor.execute {
                        try {
                            val args = QuzhiProtocol.common + mapOf("telephone" to number) + if (sms) mapOf("smsCode" to value, "type" to "5") else mapOf("password" to QuzhiProtocol.password(value), "type" to "0", "identifier" to "")
                            val candidate = QuzhiProtocol.session(client.request(if (sms) "user/registerAndLogin" else "user/login", args, true), number)
                            val wallet = QuzhiProtocol.wallet(client.request("account/wallet", QuzhiProtocol.auth(candidate)))
                            activity.runOnUiThread {
                                if (cancelled || !lifecycle.isCurrent(owner)) { cancel(); dialog.dismiss(); busy.set(false); return@runOnUiThread }
                                try {
                                    lifecycle.commit(attempt) {
                                        // Adopt only after wallet verification. Different identities never inherit a snapshot.
                                        val old = state.optJSONObject("session")
                                        val same = old != null && listOf("userId", "accountId", "projectId", "telephone").all { old.optString(it) == candidate.optString(it) }
                                        val snapshot = if (same) state.optJSONObject("snapshot")?.let { JSONObject(it.toString()) } ?: JSONObject() else JSONObject()
                                        snapshot.put("wallet", wallet).put("walletUpdatedAt", System.currentTimeMillis()).put("issues", JSONObject())
                                        val next = JSONObject().put("session", candidate).put("snapshot", snapshot).put("expired", false)
                                        vault.save(next.toString()); state = next
                                        finished = true; phone.text.clear(); secret.text.clear(); dialog.dismiss()
                                        call.resolve(publicState()); busy.set(false)
                                    }
                                } catch (_: QuzhiLifecycleCancelled) { cancel(); dialog.dismiss(); busy.set(false) }
                                catch (_: Exception) { enabled(true); status.text = "无法安全保存登录，请重试" }
                            }
                        } catch (e: Exception) {
                            val error = message(code(e))
                            activity.runOnUiThread { if (cancelled || !lifecycle.isCurrent(owner)) { cancel(); dialog.dismiss(); busy.set(false) } else { enabled(true); status.text = error; secret.text.clear() } }
                        }
                    } } } catch (_: QuzhiLifecycleCancelled) { cancel(); dialog.dismiss(); busy.set(false) }
                    catch (_: java.util.concurrent.RejectedExecutionException) { cancel(); dialog.dismiss(); busy.set(false) }
                }
            }
            dialog.show()
        }
    }

    override fun handleOnDestroy() {
        lifecycle.dispose(owner)
        cancelLogin?.invoke()
        activeLogin?.dismiss()
        executor.shutdown()
        super.handleOnDestroy()
    }

    @PluginMethod fun openRecharge(call: PluginCall) {
        if (!busy.compareAndSet(false, true)) { call.reject("趣智操作正在进行，请稍候", "BUSY"); return }
        activity.runOnUiThread {
            try {
                owned {
                    restoreState(); session()
                    if (state.optBoolean("expired", false)) throw QuzhiFailure("AUTH")
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(QuzhiProtocol.RECHARGE)).setPackage("com.eg.android.AlipayGphone")
                    activity.startActivity(intent)
                    call.resolve(JSObject().put("opened", true))
                }
            } catch (e: android.content.ActivityNotFoundException) { call.reject("请先安装支付宝，再进入趣智充值页", "NO_ALIPAY") }
            catch (e: Exception) { call.reject(message(code(e)), code(e)) }
            finally { busy.set(false) }
        }
    }
}
