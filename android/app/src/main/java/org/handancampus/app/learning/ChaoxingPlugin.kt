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

private class LearningFailure(val reason:String):Exception(reason)
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
    private var call:PluginCall?=null
    private var web:WebView?=null
    private var dialog:Dialog?=null
    @Volatile private var generation=0
    private var workerToken=0
    private var agent=""
    private var detailBudget=8
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
    private fun loadState(){if(loaded)return;state=try { JSONObject(vault.restore() ?: "{}") }catch(_:Exception){JSONObject()};loaded=true}
    private fun saveState(){checkActive();val raw=state.toString();if(raw.length>1900000)throw LearningFailure("LIMIT");vault.save(raw);cookies.flush()}
    private fun bindAccount(key:String){loadState();if(state.optString("account")!=key){state=JSONObject().put("account",key);knownCourses=emptyList();plan=emptyList()}}
    private fun request(start:String,form:Map<String,String>?=null):LearningPage {
        if(!ChaoxingPolicy.safeRead(start))throw LearningFailure("URL")
        var url=start;var post=form
        for(step in 0..6){
            checkActive()
            if(!ChaoxingPolicy.safeRead(url))throw LearningFailure("URL")
            val connection=URL(url).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects=false;connection.connectTimeout=15000;connection.readTimeout=20000
                connection.setRequestProperty("User-Agent",agent);connection.setRequestProperty("Accept","text/html,application/json;q=0.9,*/*;q=0.8")
                connection.setRequestProperty("Referer",ChaoxingPolicy.HOME)
                cookies.getCookie(url)?.let { connection.setRequestProperty("Cookie",it) }
                if(post!=null){if(url!=ChaoxingPolicy.NOTICES)throw LearningFailure("METHOD");connection.requestMethod="POST";connection.doOutput=true;connection.setRequestProperty("Content-Type","application/x-www-form-urlencoded");connection.outputStream.use { it.write(ChaoxingPolicy.params("",post).substring(1).toByteArray()) }}
                val code=connection.responseCode
                diagnostics.put("host",URI(url).host).put("path",URI(url).path).put("httpStatus",code)
                connection.headerFields.filter { it.key?.equals("Set-Cookie",true)==true }.values.flatten().forEach { cookies.setCookie(url,it) }
                if(code in 300..399){val target=ChaoxingPolicy.absolute(connection.getHeaderField("Location").orEmpty(),url) ?: throw LearningFailure("URL");if(ChaoxingPolicy.loginPage(target))throw LearningFailure("AUTH");if(ChaoxingPolicy.challenge(target,""))throw LearningFailure("VERIFY");url=target;post=null;continue}
                if(code==401)throw LearningFailure("AUTH")
                if(code==403||code==429)throw LearningFailure("HTTP_$code")
                if(code !in 200..299)throw LearningFailure("HTTP_$code")
                val bytes=connection.inputStream.use { input -> val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);while(out.size()<=1500000){val n=input.read(buffer);if(n<0)break;out.write(buffer,0,n)};out.toByteArray() };if(bytes.size>1500000)throw LearningFailure("LIMIT")
                val body=String(bytes,Charsets.UTF_8)
                if(ChaoxingPolicy.challenge(url,body))throw LearningFailure("VERIFY")
                if(Jsoup.parse(body).select("input[type=password]").isNotEmpty())throw LearningFailure("AUTH")
                return LearningPage(url,body)
            } finally { connection.disconnect() }
        }
        throw LearningFailure("REDIRECT")
    }
    private fun fetchCourses():List<LearningCourse> {
        val page=request(ChaoxingPolicy.COURSES)
        val json=try { JSONObject(page.body) }catch(_:Exception){null}
        diagnostics.put("courseKeys",JSONArray(json?.keys()?.asSequence()?.toList()?.take(20) ?: emptyList<String>()))
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
            return courses.values.takeIf { it.size<=200 } ?: throw LearningFailure("LIMIT")
        }
        val base=request(ChaoxingPolicy.HOME)
        val fid=Regex("[\"']?fid[\"']?\\s*[:=]\\s*[\"']?(\\d+)").find(base.body)?.groupValues?.get(1) ?: throw LearningFailure("COURSES_SCHEMA")
        val html=request(ChaoxingPolicy.params("https://mooc2-ans.chaoxing.com/mooc2-ans/visit/courselistdata",mapOf("courseType" to "1","courseFid" to fid,"courseTeacherid" to "0","courseOrderBy" to "0")))
        val list=ChaoxingParser.courses(html.body,html.url)
        if(list.isEmpty()&&!Regex("暂无课程|没有课程").containsMatchIn(Jsoup.parse(html.body).text()))throw LearningFailure("COURSES_SCHEMA")
        return list
    }
    private fun publicCourses(courses:List<LearningCourse>)=JSONArray().apply { courses.forEach { put(JSONObject().put("courseId",it.courseId).put("classId",it.classId).put("name",it.name).put("teacher",it.teacher)) } }
    private fun record(item:LearningRecord):JSONObject {
        val urls=state.optJSONObject("urls") ?: JSONObject().also { state.put("urls",it) };urls.put(item.id,item.url)
        return ChaoxingBridge.record(item)
    }
    private fun courseWork(course:LearningCourse):ParsedWork {
        val page=request(course.url)
        val menu=ChaoxingParser.menu(page.body,page.url)
        val target=menu ?: run {
            val workEnc=ChaoxingParser.hidden(page.body,"workEnc");if(workEnc.isBlank())throw LearningFailure("WORK_ENC")
            val openc=ChaoxingParser.hidden(page.body,"openc");val enc=ChaoxingParser.hidden(page.body,"enc")
            ChaoxingPolicy.params("https://mooc1.chaoxing.com/mooc2/work/list",mapOf("courseId" to course.courseId,"classId" to course.classId,"cpi" to course.cpi,"ut" to "s","openc" to openc,"enc" to workEnc,"stuenc" to enc,"isdisplaytable" to "2"))
        }
        val works=request(target);val parsed=ChaoxingParser.work(works.body,works.url,course)
        if(!parsed.recognized){val dom=Jsoup.parse(works.body);diagnostics.put("workRows",dom.select("li").size).put("workLinks",dom.select("a.inspectTask,li[data]").size).put("workRejected",parsed.rejected);throw LearningFailure("WORK_SCHEMA")}
        return parsed.copy(records=parsed.records.map { item ->
            if(item.deadline==null&&item.status!="submitted"&&detailBudget>0&&URI(item.url).path.endsWith("/work/task"))try { detailBudget--;val detail=request(item.url);ChaoxingParser.enrich(item,detail.body) }catch(e:LearningFailure){if(e.reason in listOf("VERIFY","AUTH"))throw e else item}catch(_:Exception){item} else item
        })
    }
    private fun sync(cursor:Int,force:Boolean):JSONObject {
        checkActive();if(cursor<0||cursor>200||cursor%6!=0)throw LearningFailure("CURSOR");detailBudget=8;loadState();val key=account();bindAccount(key)
        val result=JSONObject().put("session","valid").put("accountKey",key);val items=JSONArray();val outcomes=JSONArray()
        if(cursor==0){
            knownCourses=fetchCourses();if(account()!=key)throw LearningFailure("ACCOUNT_CHANGED")
            result.put("courses",publicCourses(knownCourses)).put("coursesComplete",coursesRejected==0)
            var allComplete=false
            try { val all=request(ChaoxingPolicy.ALL_WORK);val parsed=ChaoxingParser.work(all.body,all.url)
                parsed.records.forEach { raw -> val c=knownCourses.find { it.courseId==raw.courseId&&it.classId==raw.classId };items.put(record(if(c!=null)raw.copy(course=c.name) else raw)) }
                val total=Jsoup.parse(all.body).selectFirst("#totalCount,input[name=totalCount]")?.attr("value")?.toIntOrNull()
                allComplete=parsed.recognized&&parsed.complete&&total!=null&&total==parsed.records.size
                result.put("allWork",if(allComplete)"complete" else if(parsed.recognized)"partial" else "unrecognized")
            }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY"))throw e;result.put("allWork",e.reason)}catch(_:Exception){result.put("allWork","NETWORK")}
            val stamps=state.optJSONObject("stamps") ?: JSONObject().also { state.put("stamps",it) }
            plan=if(allComplete)emptyList() else knownCourses.filter { force||System.currentTimeMillis()-stamps.optLong(it.key,0)>600000 }
            planAccount=key
            try { val page=request(ChaoxingPolicy.EXAMS);val parsed=ChaoxingParser.exams(page.body,page.url);if(!parsed.recognized)throw LearningFailure("EXAMS_SCHEMA");result.put("exams",JSONObject().put("status",if(parsed.complete)"ok" else "partial").put("items",JSONArray().apply{parsed.records.forEach { put(record(it)) }})) }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY"))throw e;result.put("exams",JSONObject().put("status","error").put("code",e.reason))}catch(_:Exception){result.put("exams",JSONObject().put("status","error").put("code","NETWORK"))}
            try { val page=request(ChaoxingPolicy.NOTICES,mapOf("type" to "0","notice_type" to "0","lastValue" to "","sort" to "0","folderUUID" to "","kw" to ""));val j=JSONObject(page.body);if(!j.optBoolean("status"))throw LearningFailure("NOTICES_SCHEMA");val list=j.optJSONObject("notices")?.optJSONArray("list") ?: throw LearningFailure("NOTICES_SCHEMA");val data=JSONArray()
                for(i in 0 until minOf(list.length(),100)){val n=list.optJSONObject(i) ?: continue;val id=n.optString("id").ifBlank { n.optString("noticeId") };val title=n.optString("title");if(id.isBlank()||title.isBlank())continue;data.put(JSONObject().put("id",id.take(100)).put("title",title.take(200)).put("content",Jsoup.parse(n.optString("content")).text().take(6000)).put("sender",n.optString("sendName").take(100)).put("publishedText",n.optString("sendTime").ifBlank { n.optString("insertTime") }.take(100)))}
                result.put("notices",JSONObject().put("status","ok").put("data",data))
            }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY"))throw e;result.put("notices",JSONObject().put("status","error").put("code",e.reason))}catch(_:Exception){result.put("notices",JSONObject().put("status","error").put("code","NETWORK"))}
        }else if(planAccount!=key)throw LearningFailure("PLAN_EXPIRED")
        for(course in plan.drop(cursor).take(6)){
            try {val parsed=courseWork(course);parsed.records.forEach { items.put(record(it)) };val ok=parsed.complete
                outcomes.put(JSONObject().put("key",course.key).put("status",if(ok)"ok" else "partial").put("count",parsed.records.size).put("complete",ok));if(ok)state.getJSONObject("stamps").put(course.key,System.currentTimeMillis())
            }catch(e:LearningFailure){if(e.reason in listOf("AUTH","VERIFY"))throw e;outcomes.put(JSONObject().put("key",course.key).put("status","error").put("code",e.reason))}catch(_:Exception){outcomes.put(JSONObject().put("key",course.key).put("status","error").put("code","NETWORK"))}
            Thread.sleep(250)
        }
        if(account()!=key)throw LearningFailure("ACCOUNT_CHANGED")
        saveState();val next=cursor+6
        return result.put("items",items).put("courseResults",outcomes).put("nextCursor",if(next<plan.size)next else JSONObject.NULL).put("remainingCount",maxOf(0,plan.size-next))
    }
    private fun begin(next:PluginCall,job:()->JSONObject){activity.runOnUiThread {
        if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread};call=next;val token=++generation
        if(agent.isBlank())agent=WebSettings.getDefaultUserAgent(context)
        executor.execute {workerToken=token;diagnostics=JSONObject();try {val result=job();handler.post {if(token==generation)finish(result)}}catch(e:LearningFailure){handler.post {if(token==generation)finish(JSONObject().put("session",if(e.reason in listOf("AUTH","ACCOUNT_CHANGED"))"expired" else "unknown").put("code",e.reason))}}catch(_:Exception){handler.post {if(token==generation)finish(JSONObject().put("session","unknown").put("code","NETWORK"))}} }
    }}
    @PluginMethod fun syncAll(next:PluginCall)=begin(next){sync(next.getInt("cursor",0) ?: 0,next.getBoolean("force",false) ?: false)}
    @PluginMethod fun getSessionState(next:PluginCall)=begin(next){val key=account();fetchCourses();JSONObject().put("session","valid").put("accountKey",key)}
    @PluginMethod fun login(next:PluginCall){activity.runOnUiThread {
        if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread};call=next;val token=++generation;probing=false
        showPage(ChaoxingPolicy.LOGIN,true)
        handler.postDelayed({if(token==generation)fail("官方登录尚未完成，请重试","TIMEOUT")},300000)
    }}
    @PluginMethod fun openItem(next:PluginCall){activity.runOnUiThread {
        if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread}
        try {loadState();if(account()!=state.optString("account"))throw LearningFailure("AUTH");val id=next.getString("id") ?: throw LearningFailure("ITEM");val url=state.optJSONObject("urls")?.optString(id).orEmpty();if(!ChaoxingPolicy.allowed(url))throw LearningFailure("LINK_EXPIRED");call=next;++generation;showPage(url,false)}catch(e:LearningFailure){next.reject("请先刷新学习通或重新登录",e.reason)}
    }}
    @PluginMethod fun openPortal(next:PluginCall){activity.runOnUiThread {if(call!=null){next.reject("学习通操作正在进行","BUSY");return@runOnUiThread};call=next;++generation;showPage(ChaoxingPolicy.HOME,false)}}
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
                override fun shouldInterceptRequest(v:WebView,r:WebResourceRequest):WebResourceResponse?=if(ChaoxingPolicy.allowed(r.url.toString()))null else WebResourceResponse("text/plain","UTF-8",ByteArrayInputStream(ByteArray(0)))
                override fun onReceivedSslError(v:WebView,h:SslErrorHandler,e:android.net.http.SslError){h.cancel();fail("学习通证书验证失败","TLS")}
                override fun onPageFinished(v:WebView,page:String){cookies.flush();if(!auth||probing||ChaoxingPolicy.loginPage(page)||!ChaoxingPolicy.allowed(page))return
                    try {account()}catch(_:Exception){return};probing=true;val token=generation
                    executor.execute {workerToken=token;try {val courses=fetchCourses();val key=account();bindAccount(key);knownCourses=courses;saveState();handler.post{if(token==generation)finish(JSONObject().put("session","valid").put("accountKey",key).put("courses",publicCourses(courses)))}}catch(_:Exception){handler.post{if(token==generation)probing=false}}}
                }
            }
        }
        dialog=Dialog(activity,android.R.style.Theme_Material_Light_NoActionBar).apply {
            val root=LinearLayout(activity).apply{orientation=LinearLayout.VERTICAL;setBackgroundColor(Color.WHITE);fitsSystemWindows=true}
            val bar=LinearLayout(activity);bar.addView(Button(activity).apply{text=if(auth)"取消" else "返回并刷新";setOnClickListener{if(auth)fail("已取消学习通登录","CANCELLED")else finish(JSONObject().put("closed",true))}});bar.addView(TextView(activity).apply{text="学习通官方页面\nchaoxing.com";textSize=14f});root.addView(bar);root.addView(web,LinearLayout.LayoutParams(-1,0,1f));setContentView(root);setOnCancelListener{if(auth)fail("已取消学习通登录","CANCELLED")else finish(JSONObject().put("closed",true))};window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE);show();window?.setLayout(-1,-1)
        };web!!.loadUrl(url)
    }
    @PluginMethod fun logout(next:PluginCall){activity.runOnUiThread {if(call!=null)fail("学习通连接已退出","CANCELLED");vault.clear();state=JSONObject();knownCourses=emptyList();plan=emptyList();planAccount=""
        for(origin in ChaoxingPolicy.origins){val names=cookies.getCookie(origin).orEmpty().split(';').map{it.substringBefore('=').trim()}.filter{it.matches(Regex("[A-Za-z0-9_-]+"))};for(name in names)for(path in listOf("/","/mooc-ans","/mooc2-ans","/pc")){cookies.setCookie(origin,"$name=; Path=$path; Max-Age=0; Secure");cookies.setCookie(origin,"$name=; Domain=.chaoxing.com; Path=$path; Max-Age=0; Secure")};WebStorage.getInstance().deleteOrigin(origin)};cookies.flush();next.resolve(JSObject().put("session","disconnected"))}}
    private fun finish(value:JSONObject){if(value.has("code"))value.put("diagnostics",diagnostics);val pending=call ?: return;call=null;generation++;handler.removeCallbacksAndMessages(null);cookies.flush();destroyWeb();pending.resolve(JSObject(value.toString()))}
    private fun fail(message:String,code:String){val pending=call ?: return;call=null;generation++;handler.removeCallbacksAndMessages(null);cookies.flush();destroyWeb();pending.reject(message,code)}
    private fun destroyWeb(){dialog?.dismiss();dialog=null;web?.let{(it.parent as? android.view.ViewGroup)?.removeView(it);it.stopLoading();it.destroy()};web=null}
    override fun handleOnDestroy(){if(call!=null)fail("应用已关闭","CANCELLED");executor.shutdownNow();super.handleOnDestroy()}
}
