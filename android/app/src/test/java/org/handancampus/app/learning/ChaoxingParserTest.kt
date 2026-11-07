package org.handancampus.app.learning

import org.junit.Test
import org.junit.Assert.*

class ChaoxingParserTest {
    private val course=LearningCourse("12","34","56","人工测试课程","测试教师","https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=12&clazzid=34&cpi=56")
    @Test fun destinationsAndReadPathsAreRestricted(){
        assertTrue(ChaoxingPolicy.allowed(ChaoxingPolicy.LOGIN));assertTrue(ChaoxingPolicy.safeRead(ChaoxingPolicy.ALL_WORK))
        for(url in listOf("http://i.chaoxing.com/base","https://i.chaoxing.com.evil.test/base","https://i.chaoxing.com@evil.test/base","https://evilchaoxing.com/","file:///data/data/","https://i.chaoxing.com:444/base"))assertFalse(ChaoxingPolicy.allowed(url))
        assertFalse(ChaoxingPolicy.safeRead("https://mooc1.chaoxing.com/work/addStudentWork"));assertFalse(ChaoxingPolicy.safeRead("https://mooc1.chaoxing.com/work/submit"));assertTrue(ChaoxingPolicy.loginPage("about:blank"))
    }
    @Test fun fullDatesAreValidatedAndMissingYearsAreUnknown(){
        assertEquals("2026-11-07T18:30",ChaoxingParser.deadline("截止时间：2026-11-7 18:30"))
        assertNull(ChaoxingParser.deadline("截止时间：11-07 18:30"));assertNull(ChaoxingParser.deadline("提交时间：2026-11-07 18:30"));assertNull(ChaoxingParser.deadline("截止时间：2026-02-30 12:00"))
        assertEquals("2027-01-02T09:00",ChaoxingParser.deadline("作答时间：2026-12-31 08:00 至 2027-01-02 09:00"))
    }
    @Test fun submissionNeverComesFromLocalCompletionOrClosedDeadline(){
        assertEquals("pending",ChaoxingParser.status("未提交，已截止"));assertEquals("submitted",ChaoxingParser.status("已提交 待批阅"));assertEquals("closed",ChaoxingParser.status("已截止"));assertEquals("unknown",ChaoxingParser.status("未知状态"));assertEquals("pending",ChaoxingParser.status("已提交后打回重做"))
    }
    @Test fun nativeWorkIdsAndSignedLinksComeFromTheActualRow(){
        val html="""<ul><li onclick="goTask(this);" data="https%3A%2F%2Fmooc1.chaoxing.com%2Fmooc-ans%2Fmooc2%2Fwork%2Ftask%3FcourseId%3D12%26classId%3D34%26workId%3D78%26enc%3DTEST_ONLY" aria-label="实验报告;待做"><p class="overHidden2 fl">实验报告</p><p class="status fl">待做</p><span class="time">截止时间：2026-11-08 18:00</span></li></ul>"""
        val parsed=ChaoxingParser.work(html,course.url,course);assertTrue(parsed.complete);assertEquals(1,parsed.records.size);assertEquals("12/34/homework/78",parsed.records[0].id);assertEquals("2026-11-08T18:00",parsed.records[0].deadline);assertTrue(parsed.records[0].url.contains("TEST_ONLY"))
    }
    @Test fun emptyAndIncompletePagesAreNotSuccessfulZeroTasks(){
        assertFalse(ChaoxingParser.work("<h1>加载中</h1>",course.url,course).recognized)
        assertTrue(ChaoxingParser.work("<div>暂无作业</div>",course.url,course).complete)
        val malformed="""<li onclick="goTask(this);" data="https://evil.test/work/task?workId=1"><p class="overHidden2 fl">不能跟随</p></li>"""
        val result=ChaoxingParser.work(malformed,course.url,course);assertEquals(1,result.rejected);assertFalse(result.complete)
    }
    @Test fun dynamicWorkSignaturesAreOnlyReadFromTheCoursePage(){
        assertEquals("TEST_PAGE_VALUE",ChaoxingParser.hidden("<input id='workEnc' value='TEST_PAGE_VALUE'>","workEnc"));assertEquals("",ChaoxingParser.hidden("<input id='enc' value='unrelated'>","workEnc"))
        assertNull(ChaoxingParser.menu("<a href='https://evil.test/'>作业</a>",course.url))
    }
    @Test fun htmlCourseParsingKeepsTeacherAndClassIdentity(){
        val html="""<li class="course"><a href="https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=12&amp;clazzid=34&amp;cpi=56"><h3 class="course-name" title="人工课程">人工课程</h3></a><p class="line2 color3" title="测试教师">测试教师</p></li>"""
        val list=ChaoxingParser.courses(html,course.url);assertEquals(1,list.size);assertEquals("测试教师",list[0].teacher);assertEquals("12/34",list[0].key)
    }
    @Test fun signedOriginalLinksNeverCrossThePublicBridge(){
        val item=LearningRecord("12/34/homework/78","12","34","78","homework","人工任务","人工课程","pending","待做",null,null,"时间未知","","https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?enc=TEST_SECRET_ONLY")
        val json=ChaoxingBridge.record(item);assertFalse(json.toString().contains("TEST_SECRET_ONLY"));assertFalse(json.has("url"));assertFalse(json.has("cpi"));assertTrue(json.isNull("deadline"));assertTrue(json.getBoolean("hasLink"))
    }

    @Test fun alreadyAbsoluteSignedUrlsKeepTheirEncodedQueryBytes(){
        val url="https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?courseId=12&amp;classId=34&amp;workId=78&amp;enc=TEST%2BONLY"
        val html="<li onclick='goTask(this);' data='$url' aria-label='人工作业;待做'><p class='overHidden2 fl'>人工作业</p></li>"
        assertTrue(ChaoxingParser.work(html,course.url,course).records[0].url.contains("TEST%2BONLY"))
    }

    @Test fun machineProvidedFullTimeWinsWithoutGuessingTheYearOfDisplayedText(){
        val item=LearningRecord("12/34/homework/78","12","34","78","homework","人工任务","人工课程","pending","待做",null,null,"11-08 18:00","",course.url)
        val result=ChaoxingParser.enrich(item,"<input id='endTime' value='2026-11-08 18:00'><div class='answerTime'>作答时间：11-01 18:00 至 11-08 18:00</div>")
        assertEquals("2026-11-08T18:00",result.deadline)
    }

}
