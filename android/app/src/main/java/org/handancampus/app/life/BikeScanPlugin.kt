package org.handancampus.app.life

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.result.ActivityResult
import androidx.core.content.ContextCompat
import com.getcapacitor.*
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import com.journeyapps.barcodescanner.ScanOptions
import com.journeyapps.barcodescanner.ScanIntentResult
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name="BikeScan")
class BikeScanPlugin:Plugin() {
    private val busy=AtomicBoolean(false)
    private var epoch=0
    private var scanEpoch=0
    private var ticket=""
    private var code:BikeCode?=null
    private var destroyed=false

    @PluginMethod fun scan(call:PluginCall) {
        if(call.data.length()!=0){call.reject("扫码参数无效","ARGUMENT");return}
        if(!busy.compareAndSet(false,true)){call.reject("正在处理，请稍候","BUSY");return}
        val host=activity
        if(host==null){busy.set(false);call.reject("已取消扫码","CANCELLED");return}
        host.runOnUiThread {
            try {
                if(destroyed||host.isFinishing||host.isDestroyed)throw IllegalStateException()
                epoch++;scanEpoch=epoch;ticket="";code=null
                val options=ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                    .setPrompt("扫描哈啰或美团车身二维码").setBeepEnabled(false)
                    .setCaptureActivity(CampusScanActivity::class.java).setOrientationLocked(true)
                startActivityForResult(call,options.createScanIntent(context),"scanned")
            }catch(_:Exception){busy.set(false);call.reject("相机暂未打开，请检查权限后重试","CAMERA")}
        }
    }
    @ActivityCallback private fun scanned(call:PluginCall?,result:ActivityResult) {
        busy.set(false)
        if(call==null)return
        if(destroyed||scanEpoch!=epoch){call.reject("已取消扫码","CANCELLED");return}
        val raw=ScanIntentResult.parseActivityResult(result.resultCode,result.data).contents
        if(raw==null){
            val denied=ContextCompat.checkSelfPermission(context,Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED
            call.reject(if(denied)"请允许相机权限后重试" else "已取消扫码",if(denied)"PERMISSION" else "CANCELLED");return
        }
        val parsed=try{BikeCodes.parse(raw)}catch(_:Exception){call.reject("暂不支持这个车码，请扫描哈啰或美团单车车身码","QR");return}
        code=parsed;ticket=UUID.randomUUID().toString()
        call.resolve(JSObject().put("ticket",ticket).put("provider",parsed.provider).put("number",parsed.number))
    }
    @PluginMethod fun open(call:PluginCall)=withCode(call,setOf("ticket","mode")){bike->
        val mode=call.getString("mode")
        if(mode !in setOf("use","web","scanner")){call.reject("打开方式无效","ARGUMENT");return@withCode}
        val host=activity
        val status=if(host==null)"cancelled" else BikeAndroidLauncher(host).launch(bike,mode!!)
        call.resolve(JSObject().put("status",status))
    }
    @PluginMethod fun copyNumber(call:PluginCall)=withCode(call,setOf("ticket")){bike->
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("单车编号",bike.number))
        call.resolve(JSObject().put("status","copied"))
    }
    private fun withCode(call:PluginCall,keys:Set<String>,action:(BikeCode)->Unit) {
        if(call.data.keys().asSequence().toSet()!=keys){call.reject("请求参数无效","ARGUMENT");return}
        if(!busy.compareAndSet(false,true)){call.reject("正在处理，请稍候","BUSY");return}
        val host=activity
        if(host==null){busy.set(false);call.reject("已取消","CANCELLED");return}
        host.runOnUiThread {
            try {
                val bike=code
                if(destroyed||bike==null||ticket.isBlank()||call.getString("ticket")!=ticket){call.reject("车码已失效，请重新扫码","STALE");return@runOnUiThread}
                action(bike)
            }catch(_:Exception){call.reject("暂未完成，请重试","UNAVAILABLE")}
            finally{busy.set(false)}
        }
    }
    @PluginMethod fun clear(call:PluginCall) {
        val clear={epoch++;code=null;ticket="";call.resolve()}
        val host=activity
        if(host==null)clear() else host.runOnUiThread{clear()}
    }
    override fun handleOnDestroy(){destroyed=true;epoch++;code=null;ticket="";super.handleOnDestroy()}
}
