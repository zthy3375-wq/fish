package org.handancampus.app.life

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.net.Uri

internal class BikeAndroidLauncher(private val host:Activity) {
    fun shortcut(provider:String,mode:String,target:String="app"):String {
        if(host.isFinishing||host.isDestroyed)return "cancelled"
        require(mode in setOf("scanner","home"))
        if(mode=="scanner")return dispatch(listOf(BikeCodes.scanner(provider)))
        val packageName=BikeCodes.homePackage(provider,target)
        return try {
            val manager=host.packageManager
            val intent=manager.getLaunchIntentForPackage(packageName)
            if(intent!=null)host.startActivity(intent)
            else if(Build.VERSION.SDK_INT>=33)manager.getLaunchIntentSenderForPackage(packageName).sendIntent(host,0,null,null,null)
            else return "unavailable"
            "home_requested"
        }catch(_:ActivityNotFoundException){"unavailable"}
        catch(_:IntentSender.SendIntentException){"unavailable"}
        catch(_:SecurityException){"blocked"}
    }
    fun launch(code:BikeCode,mode:String):String {
        if(host.isFinishing||host.isDestroyed)return "cancelled"
        return dispatch(BikeCodes.routes(code,mode))
    }
    private fun dispatch(routes:List<BikeRoute>):String {
        for(route in routes) {
            try {
                host.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(route.uri)).addCategory(Intent.CATEGORY_BROWSABLE))
                return route.status
            }catch(_:ActivityNotFoundException){ /* Only no handler permits the documented web fallback. */ }
            catch(_:SecurityException){return "blocked"}
        }
        return "unavailable"
    }
}
