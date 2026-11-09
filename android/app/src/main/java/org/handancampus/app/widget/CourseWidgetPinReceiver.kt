package org.handancampus.app.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Explicit, private callback. UI verifies actual provider IDs instead of assuming success. */
class CourseWidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == PINNED) CourseWidgetProvider.updateAll(context)
    }
    companion object { const val PINNED = "org.handancampus.app.WIDGET_PINNED" }
}
