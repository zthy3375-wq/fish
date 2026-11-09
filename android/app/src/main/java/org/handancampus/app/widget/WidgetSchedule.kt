package org.handancampus.app.widget

import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit

internal class WidgetSchedule(val json: JSONObject) {
    val monday = LocalDate.parse(json.getString("monday"))
    val weekCount = json.getInt("weekCount")
    init {
        require(monday.dayOfWeek.value == 1 && weekCount in 1..60)
        val courses = json.getJSONArray("courses")
        require(courses.length() <= 2000)
        for (i in 0 until courses.length()) {
            val c = courses.getJSONObject(i)
            require(c.getInt("day") in 1..7)
            for (key in listOf("name", "room", "teacher", "color")) require(c.getString(key).length <= 300)
            for (key in listOf("start", "end")) require(Regex("([01]\\d|2[0-3]):[0-5]\\d").matches(c.getString(key)))
            require(c.getString("start") < c.getString("end"))
            val weeks = c.getJSONArray("weeks")
            require(weeks.length() <= 60)
            for (j in 0 until weeks.length()) require(weeks.getInt(j) in 1..60)
        }
    }
    fun week(day: LocalDate) = Math.floorDiv(ChronoUnit.DAYS.between(monday, day), 7).toInt() + 1
    fun courses(day: LocalDate): List<JSONObject> {
        val week = week(day)
        if (week !in 1..weekCount) return emptyList()
        val all = json.getJSONArray("courses")
        return (0 until all.length()).map { all.getJSONObject(it) }.filter { c ->
            c.getInt("day") == day.dayOfWeek.value && (0 until c.getJSONArray("weeks").length()).any { c.getJSONArray("weeks").getInt(it) == week }
        }.sortedBy { it.getString("start") }
    }
    fun remaining(now: LocalDateTime) = courses(now.toLocalDate()).filter { it.getString("end") > now.toLocalTime().toString().take(5) }
    fun status(course: JSONObject, now: LocalDateTime): String {
        val start = now.toLocalDate().atTime(java.time.LocalTime.parse(course.getString("start")))
        val end = now.toLocalDate().atTime(java.time.LocalTime.parse(course.getString("end")))
        if (now >= end) return "已结束"
        if (now >= start) return "上课中"
        val minutes = (java.time.Duration.between(now, start).seconds + 59) / 60
        return if (minutes <= 120) "还有 "+minutes+" 分钟" else "待上课"
    }
}
