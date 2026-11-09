package org.handancampus.app.learning

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

/** Official HTTPS destinations only. Credentials never travel through the Vue bridge. */
object ChaoxingPolicy {
    const val HOME = "https://i.chaoxing.com/base"
    const val LOGIN = "https://passport2.chaoxing.com/login?refer=https%3A%2F%2Fi.chaoxing.com"
    const val COURSES = "https://mooc1-api.chaoxing.com/mycourse/backclazzdata"
    const val ALL_WORK = "https://mooc1-api.chaoxing.com/mooc-ans/mooc2/work/all-task"
    const val EXAMS = "https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examlist"
    const val NOTICES = "https://notice.chaoxing.com/pc/notice/getNoticeList"
    val origins = listOf("https://chaoxing.com", "https://passport2.chaoxing.com", "https://i.chaoxing.com", "https://mooc1-api.chaoxing.com", "https://mooc1.chaoxing.com", "https://mooc1-1.chaoxing.com", "https://mooc1-2.chaoxing.com", "https://mooc2-ans.chaoxing.com", "https://notice.chaoxing.com", "https://sso.chaoxing.com")
    fun allowed(url: String?): Boolean = try {
        val u = URI(url ?: "")
        u.scheme == "https" && u.userInfo == null && u.port in listOf(-1,443) && (u.host == "chaoxing.com" || u.host?.endsWith(".chaoxing.com") == true)
    } catch (_: Exception) { false }
    fun loginPage(url: String) = !allowed(url) || URI(url).host?.startsWith("passport") == true || URI(url).path.orEmpty().contains("/login", true)
    fun challenge(url: String, body: String) = url.contains("antispider", true) || body.contains("访问过于频繁") || body.contains("9010") && body.contains("验证码")
    fun query(url: String): Map<String,String> = try { (URI(url).rawQuery ?: "").split('&').filter { it.contains('=') }.associate { val p=it.split('=',limit=2); URLDecoder.decode(p[0],"UTF-8").lowercase() to URLDecoder.decode(p[1],"UTF-8") } } catch (_:Exception) { emptyMap() }
    fun absolute(raw: String, base: String): String? = try { val trimmed=raw.trim();val value=if(trimmed.startsWith("?"))base.substringBefore('?').substringBefore('#')+trimmed else URI(base).resolve(trimmed).toString(); if(allowed(value)) value else null } catch (_:Exception) { null }
    fun params(base: String, values: Map<String,String>) = base + (if(base.contains('?')) "&" else "?") + values.entries.joinToString("&") { URLEncoder.encode(it.key,"UTF-8")+"="+URLEncoder.encode(it.value,"UTF-8") }
    /** Use only previously supplied official URLs, otherwise open the official portal. */
    fun itemDestination(id:String,detail:String?,courses:List<LearningCourse>):String {
        require(id.matches(Regex("[0-9]{1,24}/[0-9]{1,24}/(?:homework|exam)/[0-9]{1,24}")))
        if(allowed(detail))return detail!!
        val key=id.split('/').take(2).joinToString("/")
        return courses.firstOrNull { it.key==key&&safeRead(it.url) }?.url ?: HOME
    }
    fun numeric(value: String) = value.matches(Regex("[0-9]{1,24}"))
    fun safeRead(url:String):Boolean {
        if(!allowed(url))return false
        val path=URI(url).path.lowercase()
        return listOf("/base","/mycourse/studentcourse","/mycourse/stu","/mycourse/backclazzdata","/visit/courselistdata","/mooc2-ans/visit/courselistdata","/visit/stucoursemiddle","/mooc-ans/visit/stucoursemiddle","/mooc2/work/all-task","/mooc-ans/mooc2/work/all-task","/mooc2/work/list","/mooc-ans/mooc2/work/list","/work/getallwork","/mooc-ans/work/getallwork","/mooc2/work/task","/mooc-ans/mooc2/work/task","/exam-ans/exam/test/examcode/examlist","/pc/notice/getnoticelist").any { path==it } || path.startsWith("/mooc2-ans/mycourse/") || path.startsWith("/mooc-ans/mycourse/")
    }
}
