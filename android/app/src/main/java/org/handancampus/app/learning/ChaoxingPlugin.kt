package org.handancampus.app.learning

import android.app.Dialog
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.webkit.*
import android.widget.*
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import org.handancampus.app.academic.SchoolSessionVault
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.io.ByteArrayInputStream

private class LearningFailure(val reason:String,val records:List<LearningRecord> = emptyList()):Exception(reason)
private data class LearningPage(val url:String,val body:String)

/** A separate native connector. Remote pages have no Capacitor/JavascriptInterface bridge. */
@CapacitorPlugin(name="ChaoxingClient")
class ChaoxingPlugin:Plugin() {
    private val executor=Executors.newSingleThreadExecutor()
    private val handler=Handler(Looper.getMainLooper())
    private val cookies get()=CookieManager.getInstance()
    private val vault by lazy { SchoolSessionVault(context,"chaoxing_session_v070","handan.chaoxing.session.v070",2000000) }
    private var state=JSONObject()
    private var loaded=false
    private val sessionLock=Any()
    private val visited=java.util.concurrent.ConcurrentHashMap<String,Boolean>()
    private fun observe(url:String){if(ChaoxingPolicy.allowed(url)&&visited.size<64)visited["https://"+URI(url).host]=true}
    private var call:PluginCall?=null
    private var web:WebView?=null
    private var dialog:Dialog?=null
    @Volatile private var generation=0
    private var workerToken=0
    private var agent=""
    private var lastRequestAt=0L
    private var diagnostics=JSONObject()
    private var coursesRejected=0
    private fun checkActive(){if(workerToken!=generation||Thread.currentThread().isInterrupted)throw LearningFailure("CANCELLED")}
    private var probing=false
    private var plan=listOf<LearningCourse>()
    private var knownCourses=listOf<LearningCourse>()
    private var planAccount=""
    private fun hash(value:String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString(""){"%02x".format(it)}.take(24)
    private fun account():String {
        val header=cookies.getCookie(ChaoxingPolicy.HOME).orEmpty()
        val uid=header.split(';').map { it.trim().split('=',limit=2) }.find { it.size==2&&it[0]=="_uid" }?.get(1).orEmpty()
        if(!ChaoxingPolicy.numeric(uid))throw LearningFailure("AUTH")
        return hash(uid)
    }
    private fun loadState(){if(loaded)return;state=try { JSONObject(vault.restore() ?: "{}") }catch(_:Exception){JSONObject()};state.optJSONArray("origins")?.let { a -> for(i in 0 until a.length())observe(a.optString(i)) };val saved=state.optJSONArray("scanPlan");if(saved!=null){plan=(0 until minOf(saved.length(),200)).mapNotNull { i->val c=saved.optJSONObject(i) ?: return@mapNotNull null;val cid=c.optString("courseId");val clazz=c.optString("classId");val cpi=c.optString("cpi");val url=c.optString("url");if(listOf(cid,clazz,cpi).all(ChaoxingPolicy::numeric)&&ChaoxingPolicy.safeRead(url))LearningCourse(cid,clazz,cpi,c.optString("name"),c.optString("teacher"),url) else null };planAccount=state.optString("planAccount")};loaded=true}
    private fun saveState(){synchronized(sessionLock){checkActive();state.put("scanPlan",JSONArray().apply{plan.forEach { c->put(JSONObject().put("courseId",c.courseId).put("classId",c.classId).put("cpi",c.cpi).put("name",c.name).put("teacher",c.teacher).put("url",c.url)) }}).put("planAccount",planAccount);state.put("origins",JSONArray(visited.keys.toList()));val raw=state.toString();if(raw.length>1900000)throw LearningFailure("LIMIT");vault.save(raw);cookies.flush()}}
    private fun failureResult(reason:String):JSONObject {val result=JSONObject().put("session",if(reason in listOf("AUTH","ACCOUNT_CHANGED"))"expired" else "unknown").put("code",reason);try{result.put("accountKey",account())}catch(_:Exception){};return result}
    private fun bindAccount(key:String){loadState();if(state.optString("account")!=key){state=JSONObject().put("account",key);knownCourses=emptyList();plan=emptyList()}}
    private fun rememberChallenge(show:String,read:String,form:Map<String,String>?=null,referer:String=ChaoxingPolicy.HOME){
        loadState();if(ChaoxingVerification.remember(state,show,read,form,referer))saveState()
    }
    private fun request(start:String,form:Map<String,String>?=null,referer:String=ChaoxingPolicy.HOME):LearningPage {
        if(!ChaoxingPolicy.safeRead(start))throw LearningFailure("URL")
        var url=start;var post=form
        for(step in 0..6){
            checkActive()
            if(!ChaoxingPolicy.safeRead(url))throw LearningFailure("URL")
            val wait=1200L-(android.os.SystemClock.elapsedRealtime()-lastRequestAt);if(wait>0)Thread.sleep(wait);checkActive();lastRequestAt=android.os.SystemClock.elapsedRealtime()
            observe(url)
            val connection=URL(url).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects=false;connection.connectTimeout=15000;connection.readTimeout=20000
                connection.setRequestProperty("User-Agent",agent);connection.setRequestProperty("Accept","text/html,application/json;q=0.9,*/*;q=0.8")
                connection.setRequestProperty("Referer",if(ChaoxingPolicy.allowed(referer))referer else ChaoxingPolicy.HOME)
                cookies.getCookie(url)?.let { connection.setRequestProperty("Cookie",it) }
                val requestForm=post
                if(requestForm!=null){if(url!=ChaoxingPolicy.NOTICES&&url!="https://mooc1-1.chaoxing.com/visit/courselistdata")throw LearningFailure("METHOD");connection.requestMethod="POST";connection.doOutput=true;connection.setRequestProperty("Content-Type","application/x-www-form-urlencoded");connection.outputStream.use { it.write(ChaoxingPolicy.params("",requestForm).substring(1).toByteArray()) }}
                val code=connection.responseCode
                diagnostics.put("host",URI(url).host).put("path",URI(url).path).put("httpStatus",code)
                synchronized(sessionLock){checkActive();connection.headerFields.filter { it.key?.equals("Set-Cookie",true)==true }.values.flatten().forEach { cookies.setCookie(url,it) }}
                if(code in 300..399){val target=ChaoxingPolicy.absolute(connection.getHeaderField("Location").orEmpty(),url) ?: throw LearningFailure("URL");if(ChaoxingPolicy.loginPage(target))throw LearningFailure("AUTH");if(ChaoxingPolicy.challenge(target,"")){rememberChallenge(target,start,form,referer);throw LearningFailure("VERIFY")};url=target;post=null;continue}
                if(code==401)throw LearningFailure("AUTH")
                if(code==429)throw LearningFailure("RATE_LIMIT")
                if(code==403)throw LearningFailure("HTTP_$code")
                if(code !in 200..299)throw LearningFailure("HTTP_$code")
                val bytes=connection.inputStream.use { input -> val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);while(out.size()<=1500000){val n=input.read(buffer);if(n<0)break;out.write(buffer,0,n)};out.toByteArray() };if(bytes.size>1500000)throw LearningFailure("LIMIT")
                val body=String(bytes,Charsets.UTF_8)
                if(code==202||ChaoxingPolicy.challenge(url,body)){rememberChallenge(url,start,form,referer);throw LearningFailure("VERIFY")}
                if(Jsoup.parse(body).select("input[type=password]").isNotEmpty())throw LearningFailure("AUTH")
                return LearningPage(url,body)
            } finally { connection.disconnect() }
        }
        throw LearningFailure("REDIRECT")
    }
    private fun fetchCourses():List<LearningCourse> {
        val page=try { request(ChaoxingPolicy.COURSES) }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY","CANCELLED","RATE_LIMIT"))throw e;LearningPage(ChaoxingPolicy.COURSES,"")}catch(_:Exception){LearningPage(ChaoxingPolicy.COURSES,"")}
        val json=try { JSONObject(page.body) }catch(_:Exception){null}
        diagnostics.put("courseKeys",JSONArray(json?.keys()?.asSequence()?.toList()?.take(20) ?: emptyList<String>()))
        if(json?.has("result")==true&&json.optString("result") !in listOf("1","true"))throw LearningFailure(if(json.toString().contains("请先登录"))"AUTH" else "COURSES_SCHEMA")
        val channels=json?.optJSONArray("channelList");coursesRejected=0
        if(channels!=null){
            diagnostics.put("courseChannels",channels.length())
            val courses=linkedMapOf<String,LearningCourse>()
            for(i in 0 until channels.length()){
                val content=channels.optJSONObject(i)?.optJSONObject("content") ?: continue
                val list=content.optJSONObject("course")?.optJSONArray("data") ?: continue
                for(j in 0 until list.length()){
                    val row=list.optJSONObject(j) ?: continue
                    val cid=row.optString("id");val clazz=content.optString("id");val cpi=content.optString("cpi");val name=row.optString("name")
                    if(!listOf(cid,clazz,cpi).all(ChaoxingPolicy::numeric)||name.isBlank()){coursesRejected++;continue}
                    val entry=ChaoxingPolicy.params("https://mooc1.chaoxing.com/visit/stucoursemiddle",mapOf("courseid" to cid,"clazzid" to clazz,"cpi" to cpi))
                    val c=LearningCourse(cid,clazz,cpi,name.take(200),(row.opt("teacherfactor") as? String ?: "").take(150),entry);courses[c.key]=c
                }
            }
            if(channels.length()>0&&courses.isEmpty())throw LearningFailure("COURSES_SCHEMA")
            return courses.values.toList().takeIf { it.size<=200 } ?: throw LearningFailure("LIMIT")
        }
        val base=request(ChaoxingPolicy.HOME)
        val fid=Regex("[\"']?fid[\"']?\\s*[:=]\\s*[\"']?(\\d+)").find(base.body)?.groupValues?.get(1)
        val html=if(fid==null)request("https://mooc1-1.chaoxing.com/visit/courselistdata",mapOf("courseType" to "1","courseFolderId" to "0","courseFolderSize" to "-1","digest" to "_all")) else request(ChaoxingPolicy.params("https://mooc2-ans.chaoxing.com/mooc2-ans/visit/courselistdata",mapOf("courseType" to "1","courseFid" to fid,"courseTeacherid" to "0","courseOrderBy" to "0")))
        val list=ChaoxingParser.courses(html.body,html.url)
        if(list.isEmpty()&&!Regex("暂无课程|没有课程").containsMatchIn(Jsoup.parse(html.body).text()))throw LearningFailure("COURSES_SCHEMA")
        return list
    }
    private fun publicCourses(courses:List<LearningCourse>)=JSONArray().apply { courses.forEach { put(JSONObject().put("courseId",it.courseId).put("classId",it.classId).put("name",it.name).put("teacher",it.teacher)) } }
    private fun record(item:LearningRecord):JSONObject {
        val urls=state.optJSONObject("urls") ?: JSONObject().also { state.put("urls",it) };if(ChaoxingPolicy.allowed(item.url))urls.put(item.id,item.url)
        return ChaoxingBridge.record(item)
    }
    private fun courseWork(course:LearningCourse):ParsedWork {
        diagnostics.put("stage","course-entry")
        val page=request(course.url)
        diagnostics.put("stage","work-list")
        val menu=ChaoxingParser.menu(page.body,page.url)
        val target=menu ?: run {
            val workEnc=ChaoxingParser.hidden(page.body,"workEnc");diagnostics.put("workEncInputs",if(workEnc.isBlank())0 else 1);if(workEnc.isBlank())throw LearningFailure("WORK_ENC")
            val openc=ChaoxingParser.hidden(page.body,"openc");val enc=ChaoxingParser.hidden(page.body,"enc")
            ChaoxingPolicy.params("https://mooc1.chaoxing.com/mooc2/work/list",mapOf("courseId" to course.courseId,"classId" to course.classId,"cpi" to course.cpi,"ut" to "s","openc" to openc,"enc" to workEnc,"stuenc" to enc,"isdisplaytable" to "2"))
        }
        var targetPage=target;val records=linkedMapOf<String,LearningRecord>();val visitedPages=mutableSetOf<String>();var recognized=false;var complete=false;var rejected=0
        for(pageIndex in 0 until 15){
            if(!visitedPages.add(targetPage))break
            val works=try{val shell=request(targetPage,referer=page.url);val frame=ChaoxingParser.workFrame(shell.body,shell.url);if(frame!=null)request(frame,referer=shell.url) else shell}catch(e:LearningFailure){throw LearningFailure(e.reason,records.values.toList())};val parsed=ChaoxingParser.work(works.body,works.url,course)
            recognized=recognized||parsed.recognized;rejected+=parsed.rejected
            if(!parsed.recognized){val dom=Jsoup.parse(works.body);diagnostics.put("workHost",URI(works.url).host).put("workPath",URI(works.url).path).put("workContainers",dom.select(".bottomList,.task-list").size).put("workFrames",dom.select("iframe[src]").size).put("workTaskHandlers",dom.select("[onclick*=goTask]").size).put("workRows",dom.select("li").size).put("workLinks",dom.select("a.inspectTask,li[data]").size).put("workRejected",parsed.rejected);throw LearningFailure("WORK_SCHEMA",records.values.toList())}
            val added=parsed.records.count { it.id !in records };parsed.records.forEach { records[it.id]=it }
            val next=ChaoxingParser.nextPage(works.body,works.url)
            val total=ChaoxingParser.total(works.body)
            complete=rejected==0&&next==null&&(parsed.complete||total!=null&&records.size==total)
            if(next==null||added==0&&pageIndex>0)break
            targetPage=next;Thread.sleep(900)
        }
        return ParsedWork(records.values.toList(),recognized,complete,rejected)
    }
    private fun sync(cursor:Int,force:Boolean,selected:Set<String>):JSONObject {
        checkActive();if(cursor<0||cursor>200)throw LearningFailure("CURSOR");loadState();val key=account();bindAccount(key)
        val result=JSONObject().put("session","valid").put("accountKey",key);val items=JSONArray();val outcomes=JSONArray()
        val scope=selected.sorted().joinToString(",")
        val resuming=planAccount==key&&state.optString("scanScope")==scope&&state.optInt("resumeCursor",-1)==cursor
        var checkpoint=cursor
        try {
        if(cursor==0&&!resuming){
            knownCourses=fetchCourses();if(account()!=key)throw LearningFailure("ACCOUNT_CHANGED")
            result.put("courses",publicCourses(knownCourses)).put("coursesComplete",coursesRejected==0)
            val stamps=state.optJSONObject("stamps") ?: JSONObject().also { state.put("stamps",it) }
            // The all-task feed can contain only unfinished work or its first page. Always check courses for submitted/history records.
            if(selected.isEmpty())return result.put("code","COURSE_SELECTION").put("nextCursor",JSONObject.NULL)
            plan=ChaoxingScanPlan.select(knownCourses,selected,knownCourses.associate { it.key to stamps.optLong(it.key,0) },force,System.currentTimeMillis());planAccount=key;state.put("scanScope",scope)

        }else if(planAccount!=key||state.optString("scanScope")!=scope)throw LearningFailure("PLAN_EXPIRED")
        state.remove("resumeCursor")
        // Two courses per batch, paced reads. Publish each successful batch before continuing.
        for((offset,course) in plan.drop(cursor).take(1).withIndex()){
            checkpoint=cursor+offset
            try {val parsed=courseWork(course);parsed.records.forEach { items.put(record(it)) };val ok=parsed.complete
                outcomes.put(JSONObject().put("key",course.key).put("status",if(ok)"ok" else "partial").put("count",parsed.records.size).put("complete",ok));if(ok)state.getJSONObject("stamps").put(course.key,System.currentTimeMillis())
            }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY","RATE_LIMIT","CANCELLED"))throw e;e.records.forEach { items.put(record(it)) };outcomes.put(JSONObject().put("key",course.key).put("status","error").put("code",e.reason))}catch(_:Exception){outcomes.put(JSONObject().put("key",course.key).put("status","error").put("code","NETWORK"))}
            checkpoint++
        }
        val next=checkpoint
        if(next>=plan.size){
            try { val page=request(ChaoxingPolicy.EXAMS);val parsed=ChaoxingParser.exams(page.body,page.url);if(!parsed.recognized)throw LearningFailure("EXAMS_SCHEMA");result.put("exams",JSONObject().put("status",if(parsed.complete)"ok" else "partial").put("items",JSONArray().apply{parsed.records.forEach { put(record(it)) }})) }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY","RATE_LIMIT"))throw e;result.put("exams",JSONObject().put("status","error").put("code",e.reason))}catch(_:Exception){result.put("exams",JSONObject().put("status","error").put("code","NETWORK"))}
            try { val page=request(ChaoxingPolicy.NOTICES,mapOf("type" to "0","notice_type" to "0","lastValue" to "","sort" to "0","folderUUID" to "","kw" to ""));val j=JSONObject(page.body);if(!j.optBoolean("status"))throw LearningFailure("NOTICES_SCHEMA");val list=j.optJSONObject("notices")?.optJSONArray("list") ?: throw LearningFailure("NOTICES_SCHEMA");val data=JSONArray()
                for(i in 0 until minOf(list.length(),100)){val n=list.optJSONObject(i) ?: continue;val id=n.optString("id").ifBlank { n.optString("noticeId") };val title=n.optString("title");if(id.isBlank()||title.isBlank())continue;data.put(JSONObject().put("id",id.take(100)).put("title",title.take(200)).put("content",Jsoup.parse(n.optString("content")).text().take(6000)).put("sender",n.optString("sendName").take(100)).put("publishedText",n.optString("sendTime").ifBlank { n.optString("insertTime") }.take(100)))}
                result.put("notices",JSONObject().put("status","ok").put("data",data))
            }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY","RATE_LIMIT"))throw e;result.put("notices",JSONObject().put("status","error").put("code",e.reason))}catch(_:Exception){result.put("notices",JSONObject().put("status","error").put("code","NETWORK"))}
        }
        if(account()!=key)throw LearningFailure("ACCOUNT_CHANGED")
        if(next<plan.size)state.put("resumeCursor",next) else state.remove("resumeCursor")
        saveState()
        return result.put("plannedCount",plan.size).put("completedCount",next).put("items",items).put("courseResults",outcomes).put("nextCursor",if(next<plan.size)next else JSONObject.NULL).put("remainingCount",maxOf(0,plan.size-next))
        }catch(e:LearningFailure){
            if(e.reason !in listOf("VERIFY","RATE_LIMIT"))throw e
            e.records.forEach { items.put(record(it)) }
            state.put("resumeCursor",checkpoint);saveState()
            // Return collected rows before suspending. A verification challenge is never a successful empty scan.
            return result.put("plannedCount",plan.size).put("completedCount",checkpoint).put("items",items).put("courseResults",outcomes).put("code",e.reason).put("resumeCursor",checkpoint).put("remainingCount",maxOf(0,plan.size-checkpoint)).put("nextCursor",JSONObject.NULL)
        }
    }
    private fun begin(next:PluginCall,job:()->JSONObject){activity.runOnUiThread {
        if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread};call=next;val token=++generation
        if(agent.isBlank())agent=WebSettings.getDefaultUserAgent(context)
        executor.execute {workerToken=token;diagnostics=JSONObject();try {val result=job();handler.post {if(token==generation)finish(result)}}catch(e:LearningFailure){handler.post {if(token==generation)finish(failureResult(e.reason))}}catch(_:Exception){handler.post {if(token==generation)finish(failureResult("NETWORK"))}} }
    }}
    @PluginMethod fun syncAll(next:PluginCall)=begin(next){val keys=next.getArray("courseKeys");val selected=if(keys==null)emptySet<String>() else (0 until minOf(keys.length(),200)).map { keys.optString(it) }.filter { it.matches(Regex("[0-9]{1,24}/[0-9]{1,24}")) }.toSet();sync(next.getInt("cursor",0) ?: 0,next.getBoolean("force",false) ?: false,selected)}
    @PluginMethod fun getSessionState(next:PluginCall)=begin(next){val key=account();fetchCourses();JSONObject().put("session","valid").put("accountKey",key)}
    @PluginMethod fun login(next:PluginCall){activity.runOnUiThread {
        if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread};call=next;val token=++generation;probing=false
        loadState();val prior=state.optString("verificationUrl");val same=try{account()==state.optString("account")}catch(_:Exception){false};showPage(if(same&&ChaoxingPolicy.allowed(prior))prior else ChaoxingPolicy.LOGIN,true)
        handler.postDelayed({if(token==generation)fail("官方登录尚未完成，请重试","TIMEOUT")},300000)
    }}
    @PluginMethod fun openItem(next:PluginCall){activity.runOnUiThread {
        if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread}
        try {
            loadState()
            val id=next.getString("id").orEmpty()
            if(!id.matches(Regex("[0-9]{1,24}/[0-9]{1,24}/(?:homework|exam)/[0-9]{1,24}"))){next.reject("作业标识无效，请重新读取","ITEM");return@runOnUiThread}
            val same=try{account()==state.optString("account")}catch(_:LearningFailure){false}
            val detail=state.optJSONObject("urls")?.optString(id)
            val url=if(same)ChaoxingPolicy.itemDestination(id,detail,knownCourses+plan) else ChaoxingPolicy.LOGIN
            call=next;++generation
            if(same&&!ChaoxingPolicy.allowed(detail))android.widget.Toast.makeText(context,"此作业没有详情链接，已打开官方课程入口",android.widget.Toast.LENGTH_LONG).show()
            showPage(url,!same)
        }catch(_:Exception){next.reject("官方页面打开失败，请重试","OPEN")}
    }}
    @PluginMethod fun openPortal(next:PluginCall){activity.runOnUiThread {if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread};call=next;++generation;showPage(ChaoxingPolicy.HOME,false)}}
    private fun probeLogin(token:Int) {
        if(token!=generation||call==null||probing)return
        val key=try{account()}catch(_:Exception){android.widget.Toast.makeText(context,"请先在官方页面完成登录",android.widget.Toast.LENGTH_SHORT).show();return}
        probing=true
        executor.execute {workerToken=token;try {
            bindAccount(key)
            val proof=state.optString("verificationRead")
            if(ChaoxingPolicy.safeRead(proof)){val savedForm=state.optJSONObject("verificationForm");val values=savedForm?.keys()?.asSequence()?.associateWith { savedForm.optString(it) };request(proof,values,state.optString("verificationReferer",ChaoxingPolicy.HOME))}
            val courses=fetchCourses();if(account()!=key)throw LearningFailure("ACCOUNT_CHANGED");knownCourses=courses;state.remove("verificationUrl");state.remove("verificationRead");state.remove("verificationForm");state.remove("verificationReferer");saveState()
            handler.post{if(token==generation)finish(JSONObject().put("session","valid").put("accountKey",key).put("courses",publicCourses(courses)).put("resumeCursor",if(planAccount==key)state.optInt("resumeCursor",0) else 0))}
        }catch(e:LearningFailure){handler.post{if(token==generation){if(e.reason=="VERIFY"){probing=false;val target=state.optString("verificationUrl");if(ChaoxingPolicy.allowed(target)&&web?.url!=target)web?.loadUrl(target);android.widget.Toast.makeText(context,"请完成官方验证，再点顶部继续",android.widget.Toast.LENGTH_LONG).show()}else finish(failureResult(e.reason))}}}catch(_:Exception){handler.post{if(token==generation)finish(failureResult("NETWORK"))}}}
    }
    private fun showPage(url:String,auth:Boolean){
        WebView.setWebContentsDebuggingEnabled(false)
        if(agent.isBlank())agent=WebSettings.getDefaultUserAgent(context)
        web=WebView(activity).apply {
            settings.javaScriptEnabled=true;settings.domStorageEnabled=true;settings.allowFileAccess=false;settings.allowContentAccess=false;settings.mixedContentMode=WebSettings.MIXED_CONTENT_NEVER_ALLOW;settings.javaScriptCanOpenWindowsAutomatically=false;settings.setSupportMultipleWindows(false);settings.saveFormData=false
            if(android.os.Build.VERSION.SDK_INT>=26)importantForAutofill=View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            cookies.setAcceptCookie(true);cookies.setAcceptThirdPartyCookies(this,true)
            webChromeClient=object:WebChromeClient(){override fun onPermissionRequest(request:PermissionRequest){request.deny()};override fun onConsoleMessage(message:ConsoleMessage?)=true}
            webViewClient=object:WebViewClient(){
                override fun shouldOverrideUrlLoading(v:WebView,r:WebResourceRequest)=!ChaoxingPolicy.allowed(r.url.toString())
                override fun shouldInterceptRequest(v:WebView,r:WebResourceRequest):WebResourceResponse? {val target=r.url.toString();if(ChaoxingPolicy.allowed(target)){observe(target);return null};return WebResourceResponse("text/plain","UTF-8",ByteArrayInputStream(ByteArray(0)))}
                override fun onReceivedSslError(v:WebView,h:SslErrorHandler,e:android.net.http.SslError){h.cancel();fail("学习通证书验证失败","TLS")}
                override fun onPageFinished(v:WebView,page:String){cookies.flush();if(!auth||probing||ChaoxingPolicy.loginPage(page)||!ChaoxingPolicy.allowed(page)||ChaoxingPolicy.challenge(page,""))return
                    val token=generation
                    v.evaluateJavascript("(function(){const t=document.body?.innerText||'';return /9010|访问过于频繁/.test(t)||/请输入验证码/.test(t)&&[...document.querySelectorAll('input[name=code],input[name=validate],input#verifyCode')].some(e=>e.offsetParent!==null)})()") { value->if(token==generation&&value=="false")probeLogin(token) }
                }

            }
        }
        dialog=Dialog(activity,android.R.style.Theme_Material_Light_NoActionBar).apply {
            val root=LinearLayout(activity).apply{orientation=LinearLayout.VERTICAL;setBackgroundColor(Color.WHITE);fitsSystemWindows=true}
            val bar=LinearLayout(activity);bar.addView(Button(activity).apply{text=if(auth)"取消" else "返回并刷新";setOnClickListener{if(auth)finish(failureResult("CANCELLED"))else finish(JSONObject().put("closed",true))}});bar.addView(TextView(activity).apply{text="学习通官方页面\nchaoxing.com";textSize=14f});if(auth)bar.addView(Button(activity).apply{text="登录/验证后继续";setOnClickListener{probeLogin(generation)}});root.addView(bar);root.addView(web,LinearLayout.LayoutParams(-1,0,1f));setContentView(root);setOnCancelListener{if(auth)finish(failureResult("CANCELLED"))else finish(JSONObject().put("closed",true))};window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE);show();window?.setLayout(-1,-1)
        };val headers=state.optString("verificationReferer").takeIf { auth&&ChaoxingPolicy.allowed(it) }?.let { mapOf("Referer" to it) } ?: emptyMap();web!!.loadUrl(url,headers)
    }
    @PluginMethod fun logout(next:PluginCall){activity.runOnUiThread {if(call!=null)fail("学习通连接已退出","CANCELLED");synchronized(sessionLock){generation++;loadState();val origins=(ChaoxingPolicy.origins+visited.keys).distinct();vault.clear();state=JSONObject();knownCourses=emptyList();plan=emptyList();planAccount=""
        for(origin in origins){val names=cookies.getCookie(origin).orEmpty().split(';').map{it.substringBefore('=').trim()}.filter{it.matches(Regex("[A-Za-z0-9_-]+"))};for(name in names)for(path in listOf("/","/mooc-ans","/mooc2-ans","/pc")){cookies.setCookie(origin,"$name=; Path=$path; Max-Age=0; Secure");cookies.setCookie(origin,"$name=; Domain=.chaoxing.com; Path=$path; Max-Age=0; Secure")};WebStorage.getInstance().deleteOrigin(origin)};cookies.flush();next.resolve(JSObject().put("session","disconnected"))}}}
    private fun finish(value:JSONObject){if(value.has("code")||value.optJSONArray("courseResults")?.let { a->(0 until a.length()).any { a.optJSONObject(it)?.optString("status")!="ok" } }==true||value.optJSONObject("exams")?.optString("status")=="error"||value.optJSONObject("notices")?.optString("status")=="error")value.put("diagnostics",diagnostics);val pending=call ?: return;call=null;generation++;handler.removeCallbacksAndMessages(null);cookies.flush();destroyWeb();pending.resolve(JSObject(value.toString()))}
    private fun fail(message:String,code:String){val pending=call ?: return;call=null;generation++;handler.removeCallbacksAndMessages(null);cookies.flush();destroyWeb();pending.reject(message,code)}
    private fun destroyWeb(){dialog?.dismiss();dialog=null;web?.let{(it.parent as? android.view.ViewGroup)?.removeView(it);it.stopLoading();it.destroy()};web=null}
    override fun handleOnDestroy(){if(call!=null)fail("应用已关闭","CANCELLED");executor.shutdownNow();super.handleOnDestroy()}
}
