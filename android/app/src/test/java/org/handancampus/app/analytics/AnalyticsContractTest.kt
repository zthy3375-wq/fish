package org.handancampus.app.analytics
import org.junit.Test
import org.junit.Assert.*
class AnalyticsContractTest {
 @Test fun discardsUnknownFieldsAndPreviousDays(){val raw="""{"day":"2026-11-08","features":{"water":2,"studentId":123},"password":"secret"}""";val today=AnalyticsContract.counters(raw,"2026-11-08");assertEquals(2,today.getJSONObject("features").getInt("water"));assertFalse(today.toString().contains("student"));assertFalse(today.toString().contains("password"));assertEquals(0,AnalyticsContract.counters(raw,"2026-11-09").getJSONObject("features").length())}
 @Test fun capsCountsAndRecoversMalformedState(){assertEquals(1,AnalyticsContract.increment("bad","2026-11-08","tasks").getJSONObject("features").getInt("tasks"));val raw="""{"day":"2026-11-08","features":{"tasks":1000}}""";assertEquals(1000,AnalyticsContract.increment(raw,"2026-11-08","tasks").getJSONObject("features").getInt("tasks"))}
 @Test(expected=IllegalArgumentException::class) fun rejectsUnlistedEventNames(){AnalyticsContract.increment(null,"2026-11-08","studentId")}
}
