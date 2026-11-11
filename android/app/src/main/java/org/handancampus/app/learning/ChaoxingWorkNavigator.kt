package org.handancampus.app.learning

import java.net.URI

data class LearningPage(val url: String, val body: String)

/** Reads only supplied official course/list frames. No Javascript or guessed frame URLs. */
object ChaoxingWorkNavigator {
    fun entry(
        course: LearningCourse,
        read: (String, String) -> LearningPage,
        visited: (LearningPage) -> Unit = {}
    ): LearningPage? {
        val pending = java.util.ArrayDeque<Pair<String, String>>()
        val seen = mutableSetOf<String>()
        pending.add(course.url to ChaoxingPolicy.HOME)
        var count = 0
        while (pending.isNotEmpty() && count < 4) {
            val (url, referer) = pending.removeFirst()
            if (!seen.add(url)) continue
            count++
            val page = read(url, referer)
            visited(page)
            if (ChaoxingPolicy.workList(page.url)) return page
            val target = ChaoxingParser.menu(page.body, page.url, course)
                ?: ChaoxingParser.workFrame(page.body, page.url, course)
                ?: signedList(page, course)
            if (target != null) return read(target, page.url).also(visited)
            ChaoxingParser.courseFrames(page.body, page.url, course)
                .filter { it !in seen }.forEach { pending.add(it to page.url) }
        }
        return null
    }

    private fun signedList(page: LearningPage, course: LearningCourse): String? {
        val workEnc = ChaoxingParser.hidden(page.body, "workEnc")
        if (workEnc.isBlank()) return null
        // Existing desktop contract: workEnc is not interchangeable with enc.
        return ChaoxingPolicy.params("https://mooc1.chaoxing.com/mooc2/work/list", mapOf(
            "courseId" to course.courseId, "classId" to course.classId,
            "cpi" to course.cpi, "ut" to "s", "enc" to workEnc,
            "openc" to ChaoxingParser.hidden(page.body, "openc"),
            "stuenc" to ChaoxingParser.hidden(page.body, "enc"), "isdisplaytable" to "2"
        ))
    }

    fun unwrap(
        first: LearningPage,
        course: LearningCourse,
        read: (String, String) -> LearningPage
    ): LearningPage {
        var page = first
        val seen = mutableSetOf(page.url)
        repeat(3) {
            val frame = ChaoxingParser.workFrame(page.body, page.url, course) ?: return page
            if (!seen.add(frame)) return page
            page = read(frame, page.url)
        }
        return page
    }

    fun accessDenied(html: String): Boolean {
        val doc = org.jsoup.Jsoup.parse(html)
        doc.select("script,style,template,[hidden],[style*=display:none],[style*=display: none]").remove()
        return Regex("没有此页面访问权限|无权访问此课程|您没有访问权限|课程已删除|课程不存在")
            .containsMatchIn(doc.text())
    }
}
