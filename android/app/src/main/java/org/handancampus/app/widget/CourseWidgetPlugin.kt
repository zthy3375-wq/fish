package org.handancampus.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONArray
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
    private fun ids(manager: AppWidgetManager) =
        manager.getAppWidgetIds(ComponentName(context, CourseWidgetProvider::class.java))
    @PluginMethod fun status(call: PluginCall) {
        try {
            val manager = AppWidgetManager.getInstance(context)
            call.resolve(JSObject().put("supported", manager.isRequestPinAppWidgetSupported)
                .put("ids", JSONArray(ids(manager).toList())))
        } catch (_: Exception) { call.reject("暂时无法检查桌面小组件") }
    }
    @PluginMethod fun pin(call: PluginCall) {
        activity.runOnUiThread {
            try {
                val manager = AppWidgetManager.getInstance(context)
                val baseline = ids(manager)
                val supported = manager.isRequestPinAppWidgetSupported
                val callback = PendingIntent.getBroadcast(context, 62,
                    Intent(context, CourseWidgetPinReceiver::class.java).setAction(CourseWidgetPinReceiver.PINNED),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val requested = supported && manager.requestPinAppWidget(
                    ComponentName(context, CourseWidgetProvider::class.java), null, callback)
                // A true return value confirms only that the launcher accepts requests.
                call.resolve(JSObject().put("requested", requested).put("baselineIds", JSONArray(baseline.toList())))
            } catch (_: Exception) { call.reject("桌面未能接收添加请求，请手动添加") }
        }
    }
    @PluginMethod fun openHome(call: PluginCall) {
        activity.runOnUiThread {
            try {
                activity.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                call.resolve()
            } catch (_: Exception) { call.reject("请使用手机主页手势返回桌面") }
        }
    }
    @PluginMethod fun target(call: PluginCall) {
        val date = activity.intent?.getStringExtra("widget_date") ?: ""
        activity.intent?.removeExtra("widget_date")
        call.resolve(JSObject().put("date", date))
    }
}
