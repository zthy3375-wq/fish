package org.handancampus.app.life

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.os.Build

/** Android adapter: try dispatch, rather than using query visibility as an installation verdict. */
internal class ParcelAndroidLauncher(private val activity:Activity) {
    fun open(target:ParcelShortcutTarget,route:ParcelLaunchRoute):Boolean { return try {
        when(route){
            ParcelLaunchRoute.APP_HOME->{
                val manager=activity.packageManager
                val launch=manager.getLaunchIntentForPackage(target.packageName)
                if(launch!=null)activity.startActivity(launch)
                else if(Build.VERSION.SDK_INT>=33)manager.getLaunchIntentSenderForPackage(target.packageName).sendIntent(activity,0,null,null,null)
                else return false
            }
            else->{
                val uri=if(route==ParcelLaunchRoute.WEB_LINK)target.webUri else target.uri
                val intent=Intent(Intent.ACTION_VIEW,Uri.parse(uri)).addCategory(Intent.CATEGORY_BROWSABLE)
                if(route==ParcelLaunchRoute.APP_LINK)intent.setPackage(target.packageName)
                activity.startActivity(intent)
            }
        };true
    }catch(_:ActivityNotFoundException){false}
    catch(_:IntentSender.SendIntentException){false}
    }
}
