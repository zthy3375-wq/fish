package org.handancampus.app.analytics

import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.BuildConfig
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@CapacitorPlugin(name="AnonymousAnalytics")
class AnalyticsPlugin: Plugin() {
    private val worker=Executors.newSingleThreadExecutor()
    private val sending=AtomicBoolean(false)
    private val lock=Any()
    @Volatile private var lastAttempt=0L
    @Volatile private var destroyed=false
    private val prefs get()=context.getSharedPreferences("anonymous_analytics_v1",0)
    private fun day()=SimpleDateFormat("yyyy-MM-dd",Locale.US).apply { timeZone=TimeZone.getTimeZone("Asia/Shanghai") }.format(Date())
    private fun state()=JSObject().put("choice",prefs.getString("choice","unset"))
        .put("deletePending",prefs.getBoolean("delete_pending",false)).put("lastSent",prefs.getLong("last_sent",0))
    @PluginMethod fun getState(call:PluginCall){call.resolve(state())}
    @PluginMethod fun setEnabled(call:PluginCall){
        val enabled=call.getBoolean("enabled")
        if(enabled==null){call.reject("请选择是否参与匿名统计");return}
        synchronized(lock){
            if(enabled&&prefs.getBoolean("delete_pending",false)){call.reject("请先完成历史记录删除");return}
            val edit=prefs.edit().putString("choice",if(enabled)"on" else "off")
            if(enabled){
                if(!prefs.contains("id"))edit.putString("id",UUID.randomUUID().toString()).putString("token",UUID.randomUUID().toString().replace("-","")+UUID.randomUUID().toString().replace("-",""))
                edit.putBoolean("dirty",true)
            } else edit.putBoolean("dirty",false)
            edit.apply()
        }
        call.resolve(state());if(enabled)send(true)
    }
    @PluginMethod fun record(call:PluginCall){
        val feature=call.getString("feature") ?: ""
        if(feature !in AnalyticsContract.features){call.reject("不支持的统计项目");return}
        synchronized(lock){
            if(prefs.getString("choice","")=="on"&&!prefs.getBoolean("delete_pending",false)) {
                val counters=AnalyticsContract.increment(prefs.getString("counters",null),day(),feature)
                prefs.edit().putString("counters",counters.toString()).putBoolean("dirty",true).apply()
            }
        }
        call.resolve(state())
    }
    @PluginMethod fun flush(call:PluginCall){call.resolve(state());send(false)}
    @PluginMethod fun deleteData(call:PluginCall){
        synchronized(lock){prefs.edit().putString("choice","off").putBoolean("delete_pending",true).putBoolean("dirty",false).remove("counters").apply()}
        call.resolve(state());send(true)
    }
    private fun request(action:String,id:String,token:String,body:JSONObject):Pair<Int,JSONObject>{
        val c=URL(AnalyticsContract.ENDPOINT+"/"+action).openConnection() as HttpURLConnection
        c.requestMethod="POST";c.connectTimeout=8000;c.readTimeout=8000;c.instanceFollowRedirects=false;c.doOutput=true
        c.setRequestProperty("User-Agent","Hanyuantong/${BuildConfig.VERSION_NAME} Android")
        c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("Authorization","Bearer $token")
        val bytes=body.put("id",id).toString().toByteArray(Charsets.UTF_8);c.setFixedLengthStreamingMode(bytes.size)
        try{
            c.outputStream.use {it.write(bytes)};val status=c.responseCode
            val stream=if(status in 200..299)c.inputStream else c.errorStream
            val response=stream?.use { input ->
                val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(1024)
                while(true){val n=input.read(buffer);if(n<0)break;require(out.size()+n<=4096);out.write(buffer,0,n)}
                out.toByteArray().toString(Charsets.UTF_8)
            } ?: "{}"
            return Pair(status,try{JSONObject(response)}catch(_:Exception){JSONObject()})
        }finally{c.disconnect()}
    }
    private fun send(force:Boolean){
        if(destroyed||(!force&&System.currentTimeMillis()-lastAttempt<300000)||!sending.compareAndSet(false,true))return
        lastAttempt=System.currentTimeMillis()
        worker.execute{
            try{
                val id=prefs.getString("id",null);val token=prefs.getString("token",null)
                if(prefs.getBoolean("delete_pending",false)){
                    val success=if(id==null||token==null)true else request("delete",id,token,JSONObject()).let{it.first==200&&it.second.optBoolean("ok")}
                    if(success)synchronized(lock){prefs.edit().remove("id").remove("token").remove("enrolled").remove("last_sent").putBoolean("delete_pending",false).apply()}
                    return@execute
                }
                if(prefs.getString("choice","")!="on"||id==null||token==null)return@execute
                val snapshot=synchronized(lock){AnalyticsContract.counters(prefs.getString("counters",null),day())}
                val lastDay=prefs.getString("sent_day","")
                if(!force&&!prefs.getBoolean("dirty",false)&&lastDay==day()&&prefs.getInt("sent_version",0)==BuildConfig.VERSION_CODE)return@execute
                if(!prefs.getBoolean("enrolled",false)||prefs.getString("backend","")!=AnalyticsContract.ENDPOINT){
                    val result=request("enroll",id,token,JSONObject())
                    if(result.first!=200||!result.second.optBoolean("ok"))return@execute
                    prefs.edit().putBoolean("enrolled",true).putString("backend",AnalyticsContract.ENDPOINT).apply()
                }
                if(prefs.getString("choice","")!="on"||prefs.getBoolean("delete_pending",false))return@execute
                val payload=JSONObject(snapshot.toString()).put("version",BuildConfig.VERSION_NAME).put("versionCode",BuildConfig.VERSION_CODE)
                val result=request("record",id,token,payload)
                if(result.first==401){prefs.edit().putBoolean("enrolled",false).apply();return@execute}
                if(result.first==200&&result.second.optBoolean("ok"))synchronized(lock){
                    val clean=AnalyticsContract.counters(prefs.getString("counters",null),day()).toString()==snapshot.toString()
                    prefs.edit().putString("sent_day",snapshot.getString("day")).putInt("sent_version",BuildConfig.VERSION_CODE).putLong("last_sent",System.currentTimeMillis()).putBoolean("dirty",!clean).apply()
                }
            }catch(_:Exception){/* Best effort: never surface analytics network failures in campus flows. */}
            finally{sending.set(false)}
        }
    }
    override fun handleOnDestroy(){destroyed=true;worker.shutdownNow();super.handleOnDestroy()}
}
