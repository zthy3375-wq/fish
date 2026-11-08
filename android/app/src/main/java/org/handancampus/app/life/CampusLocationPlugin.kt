package org.handancampus.app.life

import android.Manifest
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback

/** One foreground fix; no stored location, background service or account transmission. */
@CapacitorPlugin(name="CampusLocation", permissions=[Permission(alias="location", strings=[Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION])])
class CampusLocationPlugin : Plugin(), LocationListener {
 private val handler=Handler(Looper.getMainLooper())
 private var pending:PluginCall?=null
 private var best:Location?=null
 private val manager get()=context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
 private val deadline=Runnable { finish() }
 @PluginMethod fun locate(call:PluginCall) {
  if(getPermissionState("location")!=PermissionState.GRANTED && androidx.core.content.ContextCompat.checkSelfPermission(context,Manifest.permission.ACCESS_COARSE_LOCATION)!=android.content.pm.PackageManager.PERMISSION_GRANTED){requestPermissionForAlias("location",call,"locationPermission");return}
  activity.runOnUiThread { start(call) }
 }
 @PermissionCallback private fun locationPermission(call:PluginCall){
  if(androidx.core.content.ContextCompat.checkSelfPermission(context,Manifest.permission.ACCESS_COARSE_LOCATION)!=android.content.pm.PackageManager.PERMISSION_GRANTED){call.reject("定位权限未开启","PERMISSION_DENIED");return}
  activity.runOnUiThread { start(call) }
 }
 @Suppress("MissingPermission") private fun start(call:PluginCall){
  if(pending!=null){call.reject("正在定位，请稍候","BUSY");return}
  pending=call;best=null
  try{
   val providers=listOf(LocationManager.GPS_PROVIDER,LocationManager.NETWORK_PROVIDER).filter{manager.isProviderEnabled(it)}
   if(providers.isEmpty()){stop("请开启手机定位服务");return}
   for(p in providers) manager.requestLocationUpdates(p,1000L,0f,this,Looper.getMainLooper())
   handler.postDelayed(deadline,25000)
  }catch(_:Exception){stop("定位暂不可用，请检查权限与定位服务")}
 }
 override fun onLocationChanged(location:Location){
  if(pending==null || !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy<=0)return
  val age=(SystemClock.elapsedRealtimeNanos()-location.elapsedRealtimeNanos)/1000000
  if(age<0||age>15000)return
  if(best==null || location.accuracy<best!!.accuracy)best=Location(location)
  if(location.accuracy<=15f)finish()
 }
 private fun finish(){
  val call=pending?:return;val fix=best
  cleanup()
  if(fix==null){call.reject("暂未获得当前位置，请到室外重试","NO_FIX");return}
  call.resolve(JSObject().put("latitude",fix.latitude).put("longitude",fix.longitude).put("accuracy",fix.accuracy.toDouble()).put("timestamp",fix.time))
 }
 private fun stop(message:String){val call=pending;cleanup();call?.reject(message,"CANCELLED")}
 private fun cleanup(){handler.removeCallbacks(deadline);try{manager.removeUpdates(this)}catch(_:Exception){};pending=null;best=null}
 @PluginMethod fun cancel(call:PluginCall){activity.runOnUiThread{stop("定位已停止");call.resolve()}}
 override fun handleOnPause(){stop("已离开前台，定位停止");super.handleOnPause()}
 override fun handleOnDestroy(){cleanup();super.handleOnDestroy()}
 override fun onProviderEnabled(provider:String){}
 override fun onProviderDisabled(provider:String){}
 @Deprecated("Legacy Android callback") override fun onStatusChanged(provider:String?,status:Int,extras:Bundle?){}
}
