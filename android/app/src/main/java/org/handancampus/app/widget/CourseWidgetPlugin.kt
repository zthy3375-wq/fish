package org.handancampus.app.widget

import android.content.Context
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONObject

@CapacitorPlugin(name = "CourseWidget")
class CourseWidgetPlugin : Plugin() {
    @PluginMethod fun publish(call: PluginCall) {
        val value = call.getString("snapshot") ?: ""
        try { require(value.toByteArray().size <= 524288); WidgetSchedule(JSONObject(value)) }
        catch (_: Exception) { call.reject("课表小组件数据无效"); return }
        activity.runOnUiThread {
            context.getSharedPreferences("course_widget", Context.MODE_PRIVATE).edit().putString("snapshot", value).putLong("updated", System.currentTimeMillis()).apply()
            CourseWidgetProvider.updateAll(context)
            call.resolve()
        }
    }
    @PluginMethod fun pin(call: PluginCall) {
        val manager = android.appwidget.AppWidgetManager.getInstance(context)
        val supported = manager.isRequestPinAppWidgetSupported
        val requested = supported && manager.requestPinAppWidget(android.content.ComponentName(context, CourseWidgetProvider::class.java), null, null)
        call.resolve(JSObject().put("requested", requested))
    }
    @PluginMethod fun target(call: PluginCall) {
        val date = activity.intent?.getStringExtra("widget_date") ?: ""
        activity.intent?.removeExtra("widget_date")
        call.resolve(JSObject().put("date", date))
    }
}
