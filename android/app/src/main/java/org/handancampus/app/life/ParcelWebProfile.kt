package org.handancampus.app.life

import android.app.Application
import android.content.Context
import android.os.Build
import android.webkit.WebView

/** Dedicated process/directory, chosen before providers or WebKit can initialize. */
object ParcelWebProfile {
    var configured = false
        private set
    fun configure(context: Context) {
        if (Build.VERSION.SDK_INT < 28 || Application.getProcessName() != context.packageName + ":parcel_web") return
        try { WebView.setDataDirectorySuffix("parcel_web"); configured = true } catch (_: Exception) { configured = false }
    }
}
