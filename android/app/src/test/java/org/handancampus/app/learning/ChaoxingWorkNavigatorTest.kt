package org.handancampus.app.learning

import org.junit.Assert.*
import org.junit.Test

/** Synthetic official page shapes; these do not establish a real account's compatibility. */
class ChaoxingWorkNavigatorTest {
    private val course = LearningCourse("12", "34", "56", "人工课程", "测试教师",
        "https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=12&clazzid=34&cpi=56")
    private val list = "https://mooc1.chaoxing.com/mooc2/work/list?courseId=12&classId=34&enc=TEST%2BONLY"

    @Test fun readsCourseFrameBeforeUsingItsActualWorkSignature() {
        val frame = "https://mooc1.chaoxing.com/mooc-ans/mycourse/studentcourse?courseid=12&clazzid=34"
        val requests = mutableListOf<Pair<String, String>>()
        val result = ChaoxingWorkNavigator.entry(course, { url, referer ->
            requests += url to referer
            when (url) {
                course.url -> LearningPage(url, "<iframe src='$frame'></iframe>")
                frame -> LearningPage(url, "<input name='workEnc' value='REAL_PAGE_TEST'><input name='enc' value='DIFFERENT_TEST'>")
                else -> LearningPage(url, "<div>暂无作业</div>")
            }
        })!!
        assertEquals(3, requests.size)
        assertEquals(course.url, requests[1].second)
        assertEquals(frame, requests[2].second)
        assertEquals("REAL_PAGE_TEST", ChaoxingPolicy.query(result.url)["enc"])
        assertEquals("DIFFERENT_TEST", ChaoxingPolicy.query(result.url)["stuenc"])
        assertTrue(ChaoxingParser.work(result.body, result.url, course).complete)
    }

    @Test fun encodedMenuIsDecodedOnceAndAbsoluteSignatureEscapesStayIntact() {
        val encoded = java.net.URLEncoder.encode(list, "UTF-8")
        assertEquals(list, ChaoxingParser.menu("<a data='$encoded' href='javascript:;'>作业</a>", course.url, course))
        assertEquals(list, ChaoxingParser.menu("<a data='workMenu' href='${list.replace("&", "&amp;")}'>作业</a>", course.url, course))
        assertEquals("TEST+ONLY", ChaoxingPolicy.query(ChaoxingParser.menu("<a data='$encoded'>作业</a>",course.url)!!)["enc"])
    }

    @Test fun ignoresOtherClassesWritePathsAndExternalCourseFrames() {
        for (url in listOf("https://evil.test/mooc2/work/list", list.replace("classId=34", "classId=90"),
            "https://mooc1.chaoxing.com/work/submit", "https://mooc1.chaoxing.com/mooc2/work/task?workId=78")) {
            assertNull(ChaoxingParser.menu("<a href='$url'>作业</a>",course.url,course))
            assertNull(ChaoxingParser.workFrame("<iframe src='$url'></iframe>",course.url,course))
        }
        assertTrue(ChaoxingParser.courseFrames("<iframe src='https://evil.test/mooc-ans/mycourse/studentcourse'></iframe>",course.url,course).isEmpty())
    }

    @Test fun nestedListFramesUseImmediateParentRefererAndStopOnCycles() {
        val one = "$list&page=1"
        val two = "$list&page=2"
        val calls = mutableListOf<Pair<String,String>>()
        val result = ChaoxingWorkNavigator.unwrap(LearningPage(one,"<iframe src='$two'></iframe>"),course) {url,ref ->
            calls += url to ref
            LearningPage(url,"<iframe src='$one'></iframe>")
        }
        assertEquals(two,result.url)
        assertEquals(listOf(two to one),calls)
        assertFalse(ChaoxingParser.work(result.body,result.url,course).recognized)
    }

    @Test fun courseShellAndMissingSignatureNeverMeanNoHomework() {
        var calls=0
        val result=ChaoxingWorkNavigator.entry(course,{url,_->calls++;LearningPage(url,"<iframe src='${course.url}'></iframe><script>const hint='暂无作业'</script>")})
        assertNull(result)
        assertEquals(1,calls)
        assertEquals("",ChaoxingParser.hidden("<input id='enc' value='NOT_A_WORK_SIGNATURE'>","workEnc"))
    }

    @Test fun courseFrameTraversalHasAHardRequestBudget() {
        var calls=0
        assertNull(ChaoxingWorkNavigator.entry(course,{url,_->
            calls++
            LearningPage(url,"<iframe src='/mooc-ans/mycourse/studentcourse?courseid=12&amp;clazzid=34&amp;page=$calls'></iframe>")
        }))
        assertEquals(4,calls)
    }

    @Test fun directRedirectToListIsParsedWithoutRequestingItAgain() {
        var calls=0
        val page=ChaoxingWorkNavigator.entry(course,{_,_->calls++;LearningPage(list,"<p>老师尚未发布作业</p>")})!!
        assertEquals(1,calls)
        assertTrue(ChaoxingParser.work(page.body,page.url,course).complete)
    }

    @Test fun permissionFailureDoesNotBecomeASuccessfulEmptyList() {
        val html="<p>没有此页面访问权限</p><p>暂无作业</p>"
        assertTrue(ChaoxingWorkNavigator.accessDenied(html))
        assertFalse(ChaoxingParser.work(html,list,course).recognized)
        assertFalse(ChaoxingWorkNavigator.accessDenied("<script>const msg='没有此页面访问权限'</script><p>暂无作业</p>"))
    }

    @Test fun recordsFromAnotherClassCannotEnterTheSelectedCourseSnapshot() {
        val html="<li onclick='goTask(this)' data='https://mooc1.chaoxing.com/mooc2/work/task?courseId=12&amp;classId=90&amp;workId=78' aria-label='人工作业;待做'></li>"
        val parsed=ChaoxingParser.work(html,list,course)
        assertEquals(1,parsed.rejected)
        assertTrue(parsed.records.isEmpty())
        assertFalse(parsed.complete)
    }
}
