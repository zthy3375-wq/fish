package org.handancampus.app.life

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri

internal class BikeAndroidLauncher(private val host:Activity) {
    fun launch(code:BikeCode,mode:String):String {
        if(host.isFinishing||host.isDestroyed)return "cancelled"
        for(route in BikeCodes.routes(code,mode)) {
            try {
                host.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(route.uri)).addCategory(Intent.CATEGORY_BROWSABLE))
                return route.status
            }catch(_:ActivityNotFoundException){ /* Only no handler permits the documented web fallback. */ }
            catch(_:SecurityException){return "blocked"}
        }
        return "unavailable"
    }
}
