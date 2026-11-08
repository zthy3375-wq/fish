package org.handancampus.app.life

import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.text.InputType
import android.view.WindowManager
import android.widget.*
import androidx.activity.result.ActivityResult
import com.getcapacitor.*
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import com.journeyapps.barcodescanner.ScanOptions
import com.journeyapps.barcodescanner.ScanIntentResult
import org.handancampus.app.academic.SchoolSessionVault
import org.json.JSONObject
import org.json.JSONArray
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name="PangguaiCampus")
class PangguaiPlugin : Plugin() {
    companion object { private val fence=QuzhiLifecycleFence() }
    private val owner=fence.admit()
    private val executor=Executors.newSingleThreadExecutor()
    private val busy=AtomicBoolean(false)
    private val api=PangguaiClient()
    private val vault by lazy { SchoolSessionVault(context,"pangguai_native_v083","handan.pangguai.native.v083",524288) }
    private var state=JSONObject();private var loaded=false
    private var scannedDevice:JSONObject?=null
    private var laundryQuote:JSONObject?=null
    private var loginDialog:AlertDialog?=null
    private var cancelLogin:(()->Unit)?=null
    private fun <T> owned(work:()->T):T=fence.owned(owner,work)
    private fun restore()=owned { if(!loaded){state=vault.restore()?.let{JSONObject(it)} ?: JSONObject();loaded=true} }
    private fun save(next:JSONObject)=owned {vault.save(next.toString());state=next}
    private fun snapshot():JSObject=owned {
        val result=state.optJSONObject("snapshot")?.let {JSONObject(it.toString())} ?: JSONObject()
        val phone=state.optString("phone")
        result.put("connected",state.optString("token").isNotBlank()).put("expired",state.optBoolean("expired"))
            .put("phone",if(phone.length==11)phone.take(3)+"****"+phone.takeLast(4) else "")
        PangguaiLaundry.view(state.optJSONObject("laundry"))?.let{result.put("laundry",it)}
        JSObject.fromJSONObject(result)
    }
    private fun reject(call:PluginCall,e:Exception){val code=if(e is QuzhiLifecycleCancelled)"CANCELLED" else (e as? PangguaiFailure)?.kind ?: "NETWORK";call.reject(message(code),code)}
    private fun message(code:String)=when(code){
        "PHONE"->"请输入正确的手机号";"AUTH","ACCOUNT"->"胖乖登录已失效，请重新连接"
        "VERIFY"->"平台要求验证或稍后重试，请在官方页面完成验证后再试"
        "FORMAT","PARTIAL"->"信息未完整取得，已保留上次数据"
        "QR"->"未识别为胖乖设备二维码，请扫描机身上的设备码"
        "NO_ALIPAY"->"请先安装支付宝，再为商户钱包充值";"DEVICE"->"设备资料不匹配或暂未支持";"CANCELLED"->"已取消"
        "SERVICE"->"平台暂未完成请求，请稍后重试";else->"连接失败，请检查网络后重试"
    }
    private fun work(call:PluginCall, action:()->JSObject){
        if(!busy.compareAndSet(false,true)){call.reject("正在处理，请稍候","BUSY");return}
        try{executor.execute {try{restore();val result=action();owned {call.resolve(result)}}catch(e:Exception){reject(call,e)}finally{busy.set(false)}}}
        catch(e:Exception){busy.set(false);reject(call,e)}
    }
    @PluginMethod fun getSnapshot(call:PluginCall)=work(call){snapshot()}
    @PluginMethod fun refresh(call:PluginCall)=work(call){
        val source=owned{JSONObject(state.toString())}
        save(PangguaiRefresh.execute(source,{p,v,t->api.request(p,v,t)},{System.currentTimeMillis()}));snapshot()
    }
    @PluginMethod fun logout(call:PluginCall)=work(call){owned{vault.clear();state=JSONObject();scannedDevice=null;laundryQuote=null};snapshot()}
    @PluginMethod fun login(call:PluginCall){
        if(!busy.compareAndSet(false,true)){call.reject("正在处理，请稍候","BUSY");return}
        val host=activity
        if(host==null||host.isFinishing){busy.set(false);call.reject("已取消","CANCELLED");return}
        host.runOnUiThread {
            if(!fence.isCurrent(owner)||host.isFinishing){busy.set(false);call.reject("已取消","CANCELLED");return@runOnUiThread}
            val attempt=QuzhiLifecycleFence.Attempt(owner)
            val box=LinearLayout(host).apply{orientation=LinearLayout.VERTICAL;setPadding(40,8,40,12)}
            val phone=EditText(host).apply{hint="胖乖手机号";inputType=InputType.TYPE_CLASS_PHONE;setSingleLine();filters=arrayOf(android.text.InputFilter.LengthFilter(11))}
            val code=EditText(host).apply{hint="短信验证码";inputType=InputType.TYPE_CLASS_NUMBER;setSingleLine();filters=arrayOf(android.text.InputFilter.LengthFilter(8))}
            val consent=CheckBox(host).apply{text="同意胖乖用户协议与隐私政策；未注册手机号可能由平台创建账户。"}
            val policy=Button(host).apply{text="查看胖乖协议与隐私政策";setOnClickListener{AlertDialog.Builder(host).setItems(arrayOf("用户协议","隐私政策")){_,which->
                val url=if(which==0)"https://h5.qiekj.com/user/UserAgreement/UserAgreement" else "https://h5.qiekj.com/user/privacyPolicy/privacyPolicy"
                try{host.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(url)))}catch(_:Exception){}
            }.show()}}
            val send=Button(host).apply{text="获取验证码"};val status=TextView(host)
            listOf(phone,code,consent,policy,send,status).forEach{box.addView(it)}
            val scroll=ScrollView(host).apply{addView(box)}
            val dialog=AlertDialog.Builder(host).setTitle("连接胖乖生活").setView(scroll).setPositiveButton("登录",null).setNegativeButton("取消",null).create()
            var finished=false;var inFlight=false
            fun cancel(){if(finished)return;finished=true;fence.cancel(attempt);phone.text.clear();code.text.clear();if(!inFlight)busy.set(false);call.reject("已取消","CANCELLED")}
            fun enabled(value:Boolean){inFlight=!value;phone.isEnabled=value;code.isEnabled=value;consent.isEnabled=value;send.isEnabled=value;dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled=value}
            fun submit(sms:Boolean){
                if(inFlight||finished)return
                if(!consent.isChecked){status.text="请先阅读并同意胖乖协议";return}
                val number=try{PangguaiProtocol.phone(phone.text.toString())}catch(_:Exception){status.text=message("PHONE");return}
                val verify=code.text.toString()
                if(!sms&&!verify.matches(Regex("[0-9]{4,8}"))){status.text="请输入短信中的验证码";return}
                if(sms){val remaining=try{fence.reserveSms(owner,number,android.os.SystemClock.elapsedRealtime())}catch(_:Exception){cancel();dialog.dismiss();return};if(remaining>0){status.text="请在 $remaining 秒后重试";return}}
                enabled(false);status.text=if(sms)"正在发送…" else "正在验证账户…"
                try{executor.execute {
                    try{
                        var candidate:JSONObject?=null
                        if(sms)api.request("common/sms/sendCode",mapOf("phone" to number,"template" to "reg"))
                        else {
                            val data=api.request("user/reg",mapOf("phone" to number,"verify" to verify,"channel" to "android_app")) as? JSONObject ?: throw PangguaiFailure("FORMAT")
                            val token=PangguaiProtocol.required(data,"token")
                            val profile=PangguaiProtocol.profile(api.request("user/info",token=token),number)
                            val firstSnapshot=JSONObject().put("balance",profile.opt("balance"))
                            if(!profile.isNull("balance"))firstSnapshot.put("walletUpdatedAt",System.currentTimeMillis())
                            val next=JSONObject().put("id",profile.getString("id")).put("phone",number).put("token",token).put("snapshot",firstSnapshot)
                            restore()
                            if(state.optString("id")==profile.getString("id"))state.optJSONObject("laundry")?.let{next.put("laundry",it)}
                            candidate=next
                        }
                        host.runOnUiThread {
                            if(finished||!fence.isCurrent(owner)){busy.set(false);return@runOnUiThread}
                            if(sms){enabled(true);status.text="验证码已发送"}
                            else{try{fence.commit(attempt){save(candidate ?: throw PangguaiFailure("FORMAT"));scannedDevice=null;laundryQuote=null};finished=true;phone.text.clear();code.text.clear();busy.set(false);dialog.dismiss();call.resolve(snapshot())}catch(e:Exception){enabled(true);status.text=message((e as? PangguaiFailure)?.kind ?: "NETWORK")}}
                        }
                    }catch(e:Exception){host.runOnUiThread {if(finished||!fence.isCurrent(owner)){busy.set(false);return@runOnUiThread};enabled(true);status.text=message((e as? PangguaiFailure)?.kind ?: "NETWORK")}}
                }}catch(_:Exception){cancel();busy.set(false);dialog.dismiss()}
            }
            dialog.setOnCancelListener{cancel()};dialog.setOnDismissListener{loginDialog=null;cancelLogin=null}
            dialog.setOnShowListener{
                dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener{cancel();dialog.dismiss()}
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener{submit(false)};send.setOnClickListener{submit(true)}
            }
            loginDialog=dialog;cancelLogin={cancel()};dialog.show()
        }
    }
    @PluginMethod fun scan(call:PluginCall){
        if(!busy.compareAndSet(false,true)){call.reject("正在处理，请稍候","BUSY");return}
        activity.runOnUiThread {
            try{
                restore();if(state.optString("token").isBlank()||state.optBoolean("expired"))throw PangguaiFailure("AUTH")
                val options=ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt("扫描胖乖设备码 · 扫码不会扣款").setBeepEnabled(false).setOrientationLocked(false)
                startActivityForResult(call,options.createScanIntent(context),"scanned")
            }catch(e:Exception){busy.set(false);reject(call,e)}
        }
    }
    @ActivityCallback private fun scanned(call:PluginCall?,result:ActivityResult){
        busy.set(false);if(call==null)return
        val raw=ScanIntentResult.parseActivityResult(result.resultCode,result.data).contents
        if(raw==null){call.reject("已取消扫码","CANCELLED");return}
        readDevice(call,raw)
    }
    private fun readDevice(call:PluginCall,raw:String)=work(call){
        val fields=PangguaiProtocol.deviceCode(raw);val token=owned{state.getString("token")}
        val scan=api.request("goods/scan/v2",fields,token) as? JSONObject ?: throw PangguaiFailure("FORMAT")
        val id=PangguaiProtocol.required(scan,"id")
        val detail=api.request("goods/normal/details",mapOf("goodsId" to id),token) as? JSONObject ?: throw PangguaiFailure("FORMAT")
        val skus=api.request("goods/normal/skus",mapOf("goodsId" to id),token) as? JSONArray ?: throw PangguaiFailure("FORMAT")
        val publicDevice=PangguaiProtocol.device(scan,detail,skus)
        scannedDevice=JSONObject(publicDevice.toString()).put("imei",PangguaiProtocol.text(detail,"imei"))
            .put("routeShopId",PangguaiProtocol.text(scan,"shopId")).put("shopId",PangguaiProtocol.text(detail,"shopId"))
            .put("isBluetooth",PangguaiProtocol.text(detail,"isBluetooth"))
        laundryQuote=null
        JSObject.fromJSONObject(publicDevice)
    }
    private fun laundry():PangguaiLaundry {
        val token=state.optString("token")
        if(token.isBlank()||state.optBoolean("expired"))throw PangguaiFailure("AUTH")
        return PangguaiLaundry(request={path,fields->api.request(path,fields,token)},
            persist={session->val next=JSONObject(state.toString()).put("laundry",session);save(next)},
            alive={owned{Unit}},alipay={params->
                val host=activity
                if(host==null||host.isFinishing)throw PangguaiFailure("CANCELLED")
                com.alipay.sdk.app.PayTask(host).payV2(params,true)
                Unit
            })
    }
    @PluginMethod fun quoteLaundry(call:PluginCall)=work(call){
        laundryQuote=null
        val engine=laundry()
        val q=if(call.getBoolean("existing",false)==true)engine.quoteExisting(state.optJSONObject("laundry") ?: throw PangguaiFailure("FORMAT"))
        else engine.quote(scannedDevice ?: throw PangguaiFailure("DEVICE"),call.getString("skuId") ?: throw PangguaiFailure("FORMAT"))
        laundryQuote=q;JSObject.fromJSONObject(q)
    }
    @PluginMethod fun startLaundry(call:PluginCall)=work(call){
        val q=laundryQuote ?: throw PangguaiFailure("QUOTE_EXPIRED")
        if(q.optString("id")!=call.getString("quoteId"))throw PangguaiFailure("QUOTE_EXPIRED")
        val method=call.getString("method") ?: throw PangguaiFailure("PAY_CHANNEL")
        laundryQuote=null // single use, even when a response is lost
        val engine=laundry()
        if(q.has("sessionId"))engine.payExisting(state.optJSONObject("laundry") ?: throw PangguaiFailure("FORMAT"),q,method)
        else engine.start(scannedDevice ?: throw PangguaiFailure("DEVICE"),q,method,state.optJSONObject("laundry"))
        snapshot()
    }
    @PluginMethod fun pollLaundry(call:PluginCall)=work(call){
        val session=state.optJSONObject("laundry") ?: return@work snapshot()
        laundry().poll(session);snapshot()
    }
    @PluginMethod fun cancelLaundry(call:PluginCall)=work(call){
        val session=state.optJSONObject("laundry") ?: throw PangguaiFailure("FORMAT")
        if(call.getString("sessionId")!=session.optString("id"))throw PangguaiFailure("ORDER_MISMATCH")
        laundry().cancel(session);snapshot()
    }
    @PluginMethod fun openRecharge(call:PluginCall)=work(call){
        val id=call.getString("merchantId") ?: throw PangguaiFailure("FORMAT")
        val rows=state.optJSONObject("snapshot")?.optJSONArray("tickets") ?: throw PangguaiFailure("AUTH")
        if(state.optBoolean("expired")||(0 until rows.length()).none{rows.getJSONObject(it).optString("id")==id})throw PangguaiFailure("ACCOUNT")
        val page="user/recharge/buyGold/buyGold?shopId="+Uri.encode(id)
        val intent=Intent(Intent.ACTION_VIEW,Uri.parse("alipays://platformapi/startapp?appId=2018072460764274&page="+Uri.encode(page))).setPackage("com.eg.android.AlipayGphone")
        // The caller's explicit account/merchant confirmation precedes this request. No payment is submitted here.
        try{owned { activity.startActivity(intent) }}catch(_:android.content.ActivityNotFoundException){throw PangguaiFailure("NO_ALIPAY")};JSObject().put("opened",true)
    }
    override fun handleOnDestroy(){fence.dispose(owner);cancelLogin?.invoke();loginDialog?.dismiss();executor.shutdown();super.handleOnDestroy()}
}
