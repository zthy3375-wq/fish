package org.handancampus.app.analytics

import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.BuildConfig
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

@CapacitorPlugin(name="AnonymousAnalytics")
class AnalyticsPlugin: Plugin() {
    private val worker=Executors.newSingleThreadExecutor()
    private val prefs get()=context.getSharedPreferences("anonymous_analytics_v1",0)
    private fun state()=JSObject().put("hasHistory",prefs.contains("id")).put("deletePending",prefs.getBoolean("delete_pending",false))
    @PluginMethod fun getState(call:PluginCall){call.resolve(state())}

    @PluginMethod fun deleteData(call:PluginCall){
        worker.execute {
            try {
                val id=prefs.getString("id",null)
                val token=prefs.getString("token",null)
                if(id!=null&&token!=null){
                    check(prefs.edit().putBoolean("delete_pending",true).putString("choice","off").remove("counters").commit())
                    val result=request("delete",id,token,JSONObject())
                    check(result.first==200 && result.second.optBoolean("ok"))
                    check(prefs.edit().clear().commit())
                }
                call.resolve(state())
            }catch(e:Exception){call.reject("历史记录暂未删除，请联网重试")}
        }
    }
    private fun request(action:String,id:String,token:String,body:JSONObject):Pair<Int,JSONObject>{
        val c=URL(AnalyticsContract.ENDPOINT+"/"+action).openConnection() as HttpURLConnection
        c.requestMethod="POST";c.connectTimeout=8000;c.readTimeout=8000;c.instanceFollowRedirects=false;c.doOutput=true
        c.setRequestProperty("User-Agent","Hanyuantong/${BuildConfig.VERSION_NAME} Android")
        c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("X-Hyt-Token",token)
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
    override fun handleOnDestroy(){worker.shutdown();super.handleOnDestroy()}
}
