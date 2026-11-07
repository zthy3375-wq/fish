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
        val label=Regex("(?:截止(?:时间)?|结束(?:时间)?|提交时间)[：:\\s]*([^\\n]{0,80})").find(text)?.groupValues?.get(1)
        if(label!=null)return dates(label).firstOrNull()
        val range=Regex("(?:作答时间|起止时间)[：:\\s]*([^\\n]{0,120})").find(text)?.groupValues?.get(1) ?: return null
        return dates(range).takeIf { it.size>=2 }?.last()
    }
    fun status(raw:String):String = when {
        Regex("未提交|未交|待做|待提交|未完成|未开始|待考试|待重做|打回|退回").containsMatchIn(raw) -> "pending"
        Regex("已提交|待批阅|已批阅|已完成|已交|已交卷|已结束.*已交").containsMatchIn(raw) -> "submitted"
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
        val rows=doc.select("li[data*=work],li[onclick*=goTask],li:has(a.inspectTask),a[data-workid]")
        for(row in rows) {
            val raw=row.attr("data").ifBlank { row.selectFirst("a[href*=work],a[data*=work]")?.let { it.attr("href").ifBlank { it.attr("data") } } ?: "" }
            val decoded=try { URLDecoder.decode(raw,"UTF-8") } catch (_:Exception) { raw }
            val url=ChaoxingPolicy.absolute(decoded,base);val q=ChaoxingPolicy.query(url ?: "")
            val cid=q["courseid"] ?: course?.courseId ?: "";val clazz=q["classid"] ?: q["clazzid"] ?: course?.classId ?: ""
            val wid=q["workid"] ?: row.attr("data-workid");val label=row.attr("aria-label").split(';')
            val title=(row.selectFirst(".overHidden2.fl,.task-title,.title")?.text() ?: label.firstOrNull().orEmpty()).trim()
            val statusText=(row.selectFirst(".status")?.text() ?: label.getOrNull(1).orEmpty()).trim().ifBlank { "未知" }
            if(url==null||!ChaoxingPolicy.safeRead(url)||!listOf(cid,clazz,wid).all(ChaoxingPolicy::numeric)||title.isBlank()){rejected++;continue}
            val rawTime=row.select(".time,.pt5,.remaining,.fl span").joinToString("\n") { it.text() }.ifBlank { row.text() }.take(1000)
            val name=course?.name ?: row.selectFirst(".courseName,.course-name")?.text().orEmpty()
            val item=LearningRecord("$cid/$clazz/$kind/$wid",cid,clazz,wid,kind,title.take(200),name.take(200),status(statusText),statusText.take(100),deadline(rawTime),null,rawTime,"",url)
            out[item.id]=item
        }
        val empty=Regex("暂无作业|没有作业|暂无任务|没有相关作业").containsMatchIn(doc.text())
        val recognized=out.isNotEmpty()||empty
        val next=doc.select("a[rel=next],a.next:not(.disabled),.pagingNext:not(.disabled),.nextPage:not(.disabled)").any { it.attr("aria-disabled")!="true" && it.attr("href")!="#" }
        return ParsedWork(out.values.toList(),recognized,recognized&&!next&&rejected==0,rejected)
    }
    fun enrich(item:LearningRecord,html:String):LearningRecord {
        val doc=Jsoup.parse(html);doc.select("script,style,form input,input,textarea").remove()
        val text=doc.body().text();val display=doc.select(".workTitle,.work-title,.mark_info,.workInfo,.answerTime,.time").joinToString("\n") { it.text() }.ifBlank { text.take(2000) }
        // Missing years are intentionally left unknown; never infer the current year.
        val end=deadline(display) ?: deadline(text)
        val start=Regex("(?:开始时间|作答时间)[：:\\s]*(.{0,50})").find(display)?.groupValues?.get(1)?.let { dates(it).firstOrNull() }
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
