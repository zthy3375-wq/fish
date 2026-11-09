package org.handancampus.app.widget

import android.app.*
import android.appwidget.*
import android.content.*
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.handancampus.app.MainActivity
import org.handancampus.app.R
import org.json.JSONObject
import java.time.*
import java.time.format.DateTimeFormatter

class CourseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { updateAll(context) }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) { updateAll(context) }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(REFRESH, Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) updateAll(context)
    }
    override fun onDisabled(context: Context) { (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(refreshIntent(context)) }
    companion object {
        private const val REFRESH = "org.handancampus.app.WIDGET_REFRESH"
        private val zone = ZoneId.of("Asia/Shanghai")
        private fun refreshIntent(context: Context) = PendingIntent.getBroadcast(context, 61, Intent(context, CourseWidgetProvider::class.java).setAction(REFRESH), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun clear(context: Context) {
            context.getSharedPreferences("course_widget", Context.MODE_PRIVATE).edit().clear().apply()
            updateAll(context)
        }
        private fun open(context: Context, date: LocalDate) = PendingIntent.getActivity(context, date.toEpochDay().toInt(), Intent(context, MainActivity::class.java).putExtra("widget_date", date.toString()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CourseWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val prefs = context.getSharedPreferences("course_widget", Context.MODE_PRIVATE)
            val model = runCatching { WidgetSchedule(JSONObject(prefs.getString("snapshot", "")!!)).takeIf { it.json.optBoolean("ready", true) } }.getOrNull()
            val now = ZonedDateTime.now(zone).toLocalDateTime()
            val day = now.toLocalDate()
            for (id in ids) {
                val options = manager.getAppWidgetOptions(id)
                val portrait = context.resources.configuration.orientation != android.content.res.Configuration.ORIENTATION_LANDSCAPE
                val height = options.getInt(if(portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 150)
                val width = options.getInt(if(portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 300)
                val views = if(android.os.Build.VERSION.SDK_INT >= 31){
                    val sizes = options.getParcelableArrayList<android.util.SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    if(!sizes.isNullOrEmpty()) RemoteViews(sizes.take(16).associateWith { size -> render(context,model,prefs.getLong("updated",0),now,size.width.toInt(),size.height.toInt()) })
                    else render(context,model,prefs.getLong("updated",0),now,width,height)
                }else render(context,model,prefs.getLong("updated",0),now,width,height)
                manager.updateAppWidget(id,views)
            }
            // Inexact boundary alarm plus OS periodic updates: no new exact-alarm permission.
            val next = mutableListOf(day.plusDays(1).atStartOfDay())
            model?.courses(day)?.forEach { c -> for(k in listOf("start","end")) { val t=day.atTime(LocalTime.parse(c.getString(k)));if(t>now)next.add(t) } }
            val due = minOf(next.minOrNull()!!, now.plusMinutes(30)).atZone(zone).toInstant().toEpochMilli()
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(AlarmManager.RTC, due, refreshIntent(context))
        }
        /** Content wraps naturally even when an existing launcher slot remains tall. */
        internal fun render(context: Context, model: WidgetSchedule?, updated: Long, now: LocalDateTime, width: Int, height: Int): RemoteViews {
                val scale = context.resources.configuration.fontScale.coerceAtLeast(1f)
                val tiny = height < 130
                val compact = height < 220
                val showFooter = height >= 180
                val overhead = 62 + 16 * scale + if(showFooter) 16 * scale else 0f
                val rowHeight = (if(tiny) 40 else if(compact) 52 else 78) * scale
                val limit = ((height - overhead) / rowHeight).toInt().coerceIn(1, 4)
                val root = RemoteViews(context.packageName, R.layout.course_widget)
                val day = now.toLocalDate()
                val week = model?.week(day)
                root.setViewVisibility(R.id.widget_updated, if(showFooter) View.VISIBLE else View.GONE)
                root.setTextViewText(R.id.widget_date, day.format(DateTimeFormatter.ofPattern("M.d"))+" · "+(if (week != null && week in 1..(model?.weekCount ?: 0)) "第"+week+"周" else if(model == null) "未同步" else "学期外"))
                root.setOnClickPendingIntent(R.id.widget_refresh, refreshIntent(context))
                root.setOnClickPendingIntent(R.id.widget_root, open(context, day))
                root.setTextViewText(R.id.widget_updated, if(model == null) "打开邯院通同步课表" else "本地课表 · 更新于 "+Instant.ofEpochMilli(updated).atZone(zone).format(DateTimeFormatter.ofPattern("M/d HH:mm")))
                for (offset in 0..1) {
                    val date = day.plusDays(offset.toLong())
                    val column = if (offset == 0) R.id.widget_today else R.id.widget_tomorrow
                    val heading = if (offset == 0) R.id.widget_today_label else R.id.widget_tomorrow_label
                    root.setOnClickPendingIntent(heading, open(context, date))
                    root.removeAllViews(column)
                    val all = model?.courses(date).orEmpty()
                    val pending = if(offset == 0) model?.remaining(now).orEmpty() else all
                    if(offset == 0 && all.isNotEmpty() && pending.isEmpty()) root.setTextViewText(heading, "今天 · 已结束")
                    val visible = if (offset == 0 && pending.isEmpty()) all.takeLast(limit) else pending.take(limit)
                    if (visible.isEmpty()) {
                        val empty = RemoteViews(context.packageName, R.layout.course_widget_empty)
                        empty.setTextViewText(R.id.widget_empty, if(model == null) "等待同步" else if(model.week(date) !in 1..model.weekCount) "学期外暂无课程" else if(offset == 0) "今天没有课程" else "明天没有课程")
                        empty.setOnClickPendingIntent(R.id.widget_empty, open(context, date));root.addView(column, empty)
                    }
                    for (c in visible) {
                        val ended = offset == 0 && model!!.status(c,now)=="已结束"
                        val row = RemoteViews(context.packageName, if(ended) R.layout.course_widget_row_ended else R.layout.course_widget_row)
                        val status = if(offset == 0) model!!.status(c,now) else ""
                        val prefix = if(compact && status == "上课中") "上课中 · " else if(compact && status.startsWith("还有 ")) status.removePrefix("还有 ").removeSuffix(" 分钟")+"分后 · " else ""
                        row.setTextViewText(R.id.widget_course_name, prefix+c.getString("name"))
                        row.setInt(R.id.widget_course_name, "setMaxLines", if(compact) 1 else 2)
                        row.setTextViewText(R.id.widget_course_place, c.optString("room").ifBlank { "教室待定" }+(if(width >= 330 && c.optString("teacher").isNotBlank()) " · "+c.optString("teacher") else ""))
                        row.setViewVisibility(R.id.widget_course_place, if(tiny) View.GONE else View.VISIBLE)
                        row.setTextViewText(R.id.widget_course_time, c.getString("start")+"–"+c.getString("end")+(if(tiny) " · "+c.optString("room").ifBlank { "教室待定" } else ""))
                        row.setInt(R.id.widget_course_time, "setMaxLines", 1)
                        row.setTextViewText(R.id.widget_course_status, if(offset == 0) model!!.status(c, now) else "")
                        row.setViewVisibility(R.id.widget_course_status, if(offset == 0 && !compact) View.VISIBLE else View.GONE)
                        row.setInt(R.id.widget_course_color, "setBackgroundColor", when(c.optString("color")) { "blue" -> 0xff478bf5.toInt(); "green" -> 0xff35bd97.toInt(); "orange" -> 0xffe9a04c.toInt(); else -> 0xff9c7be9.toInt() })
                        row.setContentDescription(R.id.widget_course_row, c.getString("name")+" "+c.optString("room")+" "+c.optString("teacher")+" "+c.getString("start"))
                        row.setOnClickPendingIntent(R.id.widget_course_row, open(context, date));root.addView(column, row)
                    }
                    val more = pending.size-visible.size
                    if(more > 0){
                        val extra = RemoteViews(context.packageName, R.layout.course_widget_empty)
                        extra.setTextViewText(R.id.widget_empty, "还有 "+more+" 节 ›")
                        extra.setOnClickPendingIntent(R.id.widget_empty, open(context,date));root.addView(column,extra)
                    }
                }
                return root
        }
    }
}
