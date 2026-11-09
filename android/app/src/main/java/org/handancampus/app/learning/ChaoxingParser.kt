package org.handancampus.app.learning

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.text.SimpleDateFormat
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone
import java.net.URLDecoder

data class LearningCourse(val courseId:String,val classId:String,val cpi:String,val name:String,val teacher:String,val url:String) { val key get()="$courseId/$classId" }
data class LearningRecord(val id:String,val courseId:String,val classId:String,val workId:String,val kind:String,val title:String,val course:String,val status:String,val statusText:String,val deadline:String?,val startAt:String?,val timeText:String,val description:String,val url:String)
data class ParsedWork(val records:List<LearningRecord>,val recognized:Boolean,val complete:Boolean,val rejected:Int)

/** Research-derived parsers. Acceptance requires observed server structure; empty HTML is never "zero work". */
object ChaoxingParser {
    private val datePattern=Regex("(20\\d{2})[-/年](\\d{1,2})[-/月](\\d{1,2})(?:日)?[ T\\s]+(\\d{1,2}):(\\d{2})(?::\\d{2})?")
    fun dates(text:String):List<String> = datePattern.findAll(text).mapNotNull { m ->
        try { val p=m.groupValues; val calendar=GregorianCalendar(TimeZone.getTimeZone("Asia/Shanghai"),Locale.ROOT).apply { clear();isLenient=false;set(p[1].toInt(),p[2].toInt()-1,p[3].toInt(),p[4].toInt(),p[5].toInt()) };SimpleDateFormat("yyyy-MM-dd'T'HH:mm",Locale.ROOT).apply { timeZone=calendar.timeZone }.format(calendar.time) } catch (_:Exception) { null }
    }.toList()
    fun deadline(text:String):String? {
        val label=Regex("(?:截止(?:时间)?|结束(?:时间)?)[：:\\s]*([^\\n]{0,80})").find(text)?.groupValues?.get(1)
        if(label!=null)return dates(label).firstOrNull()
        val range=Regex("(?:作答时间|起止时间)[：:\\s]*([^\\n]{0,120})").find(text)?.groupValues?.get(1) ?: return null
        return dates(range).takeIf { it.size>=2 }?.last()
    }
    fun status(raw:String):String = when {
        Regex("未提交|未交|待做|待提交|未完成|未开始|待考试|待重做|未作答|打回|退回").containsMatchIn(raw) -> "pending"
        Regex("已提交|待批阅|待批改|未批阅|已批阅|已批改|已完成|已交|已交卷|已结束.*已交").containsMatchIn(raw) -> "submitted"
        Regex("已截止|已过期|已关闭|已结束").containsMatchIn(raw) -> "closed"
        else -> "unknown"
    }
    fun hidden(html:String,id:String):String = Jsoup.parse(html).getElementById(id)?.attr("value") ?: ""
    fun menu(html:String,base:String):String? {
        val doc=Jsoup.parse(html,base)
        for(a in doc.select("a[data],a[href]"))if(a.text().contains("作业")) {
            val raw=if(a.attr("data").isNotBlank())a.attr("data") else a.attr("href")
            val target=ChaoxingPolicy.absolute(raw,base)
            if(target!=null&&ChaoxingPolicy.safeRead(target)&&java.net.URI(target).path.contains("work",true))return target
        }
        return null
    }
    /** A supplied list iframe is a read target, never a guessed endpoint. */
    fun workFrame(html:String,base:String):String? = Jsoup.parse(html,base).select("iframe[src]").asSequence()
        .mapNotNull { ChaoxingPolicy.absolute(it.attr("src"),base) }
        .firstOrNull { it!=base&&ChaoxingPolicy.safeRead(it)&&java.net.URI(it).path.lowercase() in listOf("/mooc2/work/list","/mooc-ans/mooc2/work/list","/work/getallwork","/mooc-ans/work/getallwork") }
    fun courses(html:String,base:String):List<LearningCourse> {
        val doc=Jsoup.parse(html,base);val out=linkedMapOf<String,LearningCourse>()
        for(el in doc.select("[courseid],a[href*=stucoursemiddle]")) {
            val holder=el.closest("li.course,li.courseItem,.course-item,li") ?: el.parent() ?: el
            val raw=el.attr("href").ifBlank { holder.selectFirst("a[href*=stucoursemiddle]")?.attr("href") ?: "" }
            val url=ChaoxingPolicy.absolute(raw,base);val q=ChaoxingPolicy.query(url ?: "")
            val cid=el.attr("courseid").ifBlank { q["courseid"] ?: "" };val clazz=el.attr("clazzid").ifBlank { q["clazzid"] ?: "" };val cpi=el.attr("personid").ifBlank { q["cpi"] ?: "" }
            val name=holder.selectFirst(".course-name,.courseName,h3 a,h3,.title")?.let { it.attr("title").ifBlank { it.text() } } ?: ""
            if(!ChaoxingPolicy.numeric(cid)||!ChaoxingPolicy.numeric(clazz)||!ChaoxingPolicy.numeric(cpi)||name.isBlank())continue
            val teacher=holder.selectFirst("p.color3,p.overHidden2,.teacher")?.let { it.attr("title").ifBlank { it.text() } } ?: ""
            val entry=url?.takeIf { ChaoxingPolicy.safeRead(it) } ?: ChaoxingPolicy.params("https://mooc1.chaoxing.com/visit/stucoursemiddle",mapOf("courseid" to cid,"clazzid" to clazz,"cpi" to cpi))
            val c=LearningCourse(cid,clazz,cpi,name.take(200),teacher.take(150),entry);out[c.key]=c
        }
        return out.values.toList()
    }
    fun work(html:String,base:String,course:LearningCourse?=null,kind:String="homework"):ParsedWork {
        val doc=Jsoup.parse(html,base);val out=linkedMapOf<String,LearningRecord>();var rejected=0
        val rows=doc.select("li[data*=work],[onclick*=goTask],li:has(a.inspectTask),a[data-workid]")
        for(row in rows) {
            val raw=row.attr("data").ifBlank { row.selectFirst("a[href*=work],a[data*=work]")?.let { it.attr("href").ifBlank { it.attr("data") } } ?: "" }
            val decoded=try { if(raw.startsWith("https://")||raw.startsWith("http://")||raw.startsWith("/"))raw else URLDecoder.decode(raw.replace("+","%2B"),"UTF-8") } catch (_:Exception) { raw }
            val url=decoded.takeIf { it.isNotBlank() }?.let { ChaoxingPolicy.absolute(it,base) };val q=ChaoxingPolicy.query(url ?: "")
            val cid=q["courseid"] ?: course?.courseId ?: "";val clazz=q["classid"] ?: q["clazzid"] ?: course?.classId ?: ""
            val inspect=row.selectFirst("a.inspectTask,a[data-workid]")
            val wid=q["workid"] ?: row.attr("data-workid").ifBlank { inspect?.attr("data-workid").orEmpty().ifBlank { inspect?.attr("data").orEmpty() } };val label=row.attr("aria-label").split(';')
            val title=(row.selectFirst(".overHidden2.fl,.task-title,.title,a.inspectTask,.right-content p:not(.status)")?.text() ?: label.firstOrNull().orEmpty()).trim()
            val explicit=row.select(".status,.work-status,.workStatus,.task-status,.pt5,.time,em,span").map { it.text().trim() }.filter { status(it)!="unknown" && it.length<=100 && !it.contains("截止时间") && !it.contains("开始时间") }
            val aria=label.drop(1).joinToString(";").trim()
            val statusText=(row.selectFirst(".status,.work-status,.workStatus,.task-status")?.text()?.takeIf { status(it)!="unknown" } ?: aria.takeIf { status(it)!="unknown" } ?: explicit.firstOrNull() ?: "提交状态未知").take(100)
            if((url!=null&&!ChaoxingPolicy.safeRead(url))||!listOf(cid,clazz,wid).all(ChaoxingPolicy::numeric)||title.isBlank()){rejected++;continue}
            val rawTime=row.select(".time,.pt5,.remaining,.fl span").joinToString("\n") { it.text() }.ifBlank { row.text() }.take(1000)
            val name=course?.name ?: row.selectFirst(".courseName,.course-name")?.text().orEmpty()
            val item=LearningRecord("$cid/$clazz/$kind/$wid",cid,clazz,wid,kind,title.take(200),name.take(200),status(statusText),statusText.take(100),deadline(rawTime),null,rawTime,"",url.orEmpty())
            out[item.id]=item
        }
        // Ignore template/script text and hidden placeholders; an unknown blank page is not zero work.
        val visible=doc.clone();visible.select("script,style,template,[hidden],[style*=display:none],[style*=display: none]").remove()
        val text=visible.text()+" "+visible.select("img[alt]").joinToString(" "){it.attr("alt")}
        val emptyText=Regex("(?:暂无|没有|还没有|尚无)(?:相关|任何|发布的|布置的)?作业|(?:老师|教师)(?:还未|尚未|未)发布作业|暂无任务").containsMatchIn(text)
        val blocked=Regex("请.*登录|验证码|访问过于频繁|加载失败|系统异常").containsMatchIn(text)
        val zeroList=total(html)==0&&visible.select(".bottomList,.task-list").isNotEmpty()
        val empty=rows.isEmpty()&&!blocked&&(emptyText||zeroList)
        val recognized=out.isNotEmpty()||empty
        val next=doc.select("a[rel=next],a.next:not(.disabled),.pagingNext:not(.disabled),.nextPage:not(.disabled)").any { it.attr("aria-disabled")!="true" && !it.hasClass("disabled") }
        val total=total(html)
        val incomplete=(total!=null&&total>out.size)||(out.size>=20&&total==null)
        return ParsedWork(out.values.toList(),recognized,recognized&&!next&&!incomplete&&rejected==0,rejected)
    }
    /** Follow only real server-provided read links; never guess pagination signatures or parameters. */
    fun nextPage(html:String,base:String):String? {
        val doc=Jsoup.parse(html,base)
        return doc.select("a[rel=next],a.next,.pagingNext,.nextPage,a:matchesOwn(^下一页$)").asSequence()
            .filter { !it.hasClass("disabled")&&it.attr("aria-disabled")!="true"&&it.parents().none { p->p.hasClass("disabled") } }
            .mapNotNull { ChaoxingPolicy.absolute(it.attr("href"),base) }
            .firstOrNull { it!=base&&ChaoxingPolicy.safeRead(it)&&java.net.URI(it).path==java.net.URI(base).path }
    }
    fun total(html:String):Int? {
        val el=Jsoup.parse(html).selectFirst("#totalCount,input[name=totalCount],input[name=total],#total") ?: return null
        return el.attr("value").ifBlank { el.text() }.toIntOrNull()?.takeIf { it>=0 }
    }
    private fun machineDate(value:String):String? {
        dates(value).firstOrNull()?.let { return it }
        val raw=value.trim();if(!raw.matches(Regex("[0-9]{10}|[0-9]{13}")))return null
        val millis=try { raw.toLong()*(if(raw.length==10)1000 else 1) }catch(_:Exception){return null}
        if(millis !in 946684800000L..4102444799999L)return null
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm",Locale.ROOT).apply { timeZone=TimeZone.getTimeZone("Asia/Shanghai") }.format(java.util.Date(millis))
    }
    fun enrich(item:LearningRecord,html:String):LearningRecord {
        val doc=Jsoup.parse(html);val machineEnd=doc.selectFirst("input#endTime,input#workEndTime")?.attr("value")?.let(::machineDate);val machineStart=doc.selectFirst("input#startTime,input#workStartTime")?.attr("value")?.let(::machineDate);doc.select("script,style,form input,input,textarea").remove()
        val text=doc.body().text();val display=doc.select(".workTitle,.work-title,.mark_info,.workInfo,.answerTime,.time").joinToString("\n") { it.text() }.ifBlank { text.take(2000) }
        // Missing years are intentionally left unknown; never infer the current year.
        val end=machineEnd ?: deadline(display) ?: deadline(text)
        val start=machineStart ?: Regex("(?:开始时间|作答时间)[：:\\s]*(.{0,50})").find(display)?.groupValues?.get(1)?.let { dates(it).firstOrNull() }
        return item.copy(deadline=end ?: item.deadline,startAt=start,timeText=display.take(1000),description=doc.selectFirst(".workDescription,.work-description,.workTitle")?.text()?.take(4000) ?: "")
    }
    fun exams(html:String,base:String):ParsedWork {
        val doc=Jsoup.parse(html,base);val headers=doc.select("th").map { it.text() };val items=mutableListOf<LearningRecord>();var rejected=0
        for(row in doc.select("tr.dataTr")) {
            val cells=row.select("td");fun cell(pattern:String):String { val index=headers.indexOfFirst { Regex(pattern).containsMatchIn(it) };return if(index in cells.indices)cells[index].text() else "" }
            val a=row.selectFirst("a[href]");val url=a?.attr("abs:href");val q=ChaoxingPolicy.query(url ?: "");val id=q["testid"] ?: q["examid"] ?: row.attr("data-examid")
            val cid=q["courseid"].orEmpty();val clazz=q["classid"] ?: q["clazzid"].orEmpty();val title=cell("考试名称|试卷名称")
            if(url==null||!ChaoxingPolicy.allowed(url)||!listOf(id,cid,clazz).all(ChaoxingPolicy::numeric)||title.isBlank()){rejected++;continue}
            val time=cell("考试时间|起止时间");val dates=dates(time);val rawStatus=cell("状态")
            items+=LearningRecord("$cid/$clazz/exam/$id",cid,clazz,id,"exam",title,cell("课程"),status(rawStatus),rawStatus.ifBlank { "未知" },if(dates.size>=2)dates.last() else null,dates.firstOrNull(),time,"",url)
        }
        val empty=doc.text().contains("暂无考试")||doc.text().contains("没有考试")
        return ParsedWork(items,items.isNotEmpty()||empty,rejected==0&&(items.isNotEmpty()||empty),rejected)
    }
}
