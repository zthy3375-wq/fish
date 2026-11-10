package org.handancampus.app.life

import android.app.Application
import android.content.Context

/** Select the dedicated WebView directory before content providers or any WebKit initialization. */
class PangguaiProfileApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        ParcelWebProfile.configure(base)
        PangguaiProfileSession.configureDataDirectory(base)
    }
}
