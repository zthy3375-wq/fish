package org.handancampus.app.widget
import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
class WidgetScheduleTest {
 private fun model(): WidgetSchedule = WidgetSchedule(JSONObject("""{"monday":"2026-09-14","weekCount":19,"courses":[{"name":"数学","room":"D101","teacher":"教师","color":"blue","day":1,"weeks":[9,11],"start":"14:30","end":"15:55"},{"name":"英语","room":"D102","teacher":"教师","color":"green","day":1,"weeks":[9],"start":"08:00","end":"09:25"}]}"""))
 @Test fun weekAndSundayRollover(){val m=model();assertEquals(9,m.week(LocalDate.parse("2026-11-09")));assertEquals(9,m.week(LocalDate.parse("2026-11-15")));assertEquals(10,m.week(LocalDate.parse("2026-11-16")));assertEquals(0,m.week(LocalDate.parse("2026-09-13")))}
 @Test fun oddWeeksAndOrdering(){val m=model();assertEquals(listOf("英语","数学"),m.courses(LocalDate.parse("2026-11-09")).map{it.getString("name")});assertTrue(m.courses(LocalDate.parse("2026-11-16")).isEmpty());assertEquals(1,m.courses(LocalDate.parse("2026-11-23")).size)}
 @Test fun statusBoundaries(){val m=model();val c=m.courses(LocalDate.parse("2026-11-09"))[1];assertEquals("还有 25 分钟",m.status(c,LocalDateTime.parse("2026-11-09T14:05:00")));assertEquals("上课中",m.status(c,LocalDateTime.parse("2026-11-09T14:30:00")));assertEquals("已结束",m.status(c,LocalDateTime.parse("2026-11-09T15:55:00")))}
 @Test fun prioritizesRemaining(){val m=model();assertEquals(1,m.remaining(LocalDateTime.parse("2026-11-09T09:25:00")).size);assertTrue(m.remaining(LocalDateTime.parse("2026-11-09T16:00:00")).isEmpty())}
 @Test fun noInventedOutsideTerm(){assertTrue(model().courses(LocalDate.parse("2027-12-13")).isEmpty())}
 @Test fun invalidSnapshotRejected(){try{WidgetSchedule(JSONObject("""{"monday":"2026-09-15","weekCount":19,"courses":[]}"""));fail()}catch(_:IllegalArgumentException){}}
}
