package org.handancampus.app.life

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import android.widget.*
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewFeature
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Native parcel centre. Official pages are data workers, with a separate authentication presentation. */
class ParcelWebActivity : Activity(), ParcelPageWorker.Listener {
    private lateinit var store: ParcelStore
    private lateinit var stage: FrameLayout
    private lateinit var workerLayer: FrameLayout
    private lateinit var content: LinearLayout
    private lateinit var headerTitle: TextView
    private lateinit var headerAction: TextView
    private val workers = mutableMapOf<String, ParcelPageWorker>()
    private val phases = mutableMapOf<String, String>()
    private val handler = Handler(Looper.getMainLooper())
    private val preferences by lazy { getSharedPreferences("parcel_native", MODE_PRIVATE) }
    private var selected = "taobao"
    private var filter = "pending"
    private var platformFilter = "all"
    private var mode = "list"
    private var foreground = false
    private var closed = false
    private var usable = false
    private var clearing = false
    private var dialog: AlertDialog? = null
    private var identityBitmap: Bitmap? = null
    private var originalBrightness = -1f
    private val purple = Color.rgb(112, 77, 170)
    private val ink = Color.rgb(39, 33, 49)
    private val muted = Color.rgb(126, 118, 137)
    private val surface = Color.rgb(248, 246, 251)
    private fun name(p: String) = if (p == "taobao") "淘宝" else "拼多多"
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        selected = intent.getStringExtra("provider")?.takeIf { it in listOf("taobao", "pinduoduo") } ?: "taobao"
        store = ParcelStore(this)
        originalBrightness = window.attributes.screenBrightness
        window.statusBarColor = surface; window.navigationBarColor = surface
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        if (Build.VERSION.SDK_INT >= 30) window.insetsController?.setSystemBarsAppearance(
            WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
            WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setBackgroundColor(surface)
            setOnApplyWindowInsetsListener { v, i ->
                if (Build.VERSION.SDK_INT >= 30) { val e = i.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime()); v.setPadding(e.left,e.top,e.right,e.bottom) }
                else v.setPadding(i.systemWindowInsetLeft,i.systemWindowInsetTop,i.systemWindowInsetRight,i.systemWindowInsetBottom)
                i
            }
        }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(8),0,dp(12),0) }
        header.addView(action("‹", false) { back() }.apply { textSize=32f; contentDescription="返回" }, LinearLayout.LayoutParams(dp(48),dp(52)))
        headerTitle = label("取件中心",19f,true)
        header.addView(headerTitle,LinearLayout.LayoutParams(0,-2,1f))
        headerAction = action("账号",false) { if(mode=="auth") finishAuthentication() else if(mode=="identity") showIdentity(selected) else accounts() }
        header.addView(headerAction,LinearLayout.LayoutParams(dp(64),dp(48)))
        root.addView(header)
        stage = FrameLayout(this)
        workerLayer = FrameLayout(this).apply { importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS }
        content = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setBackgroundColor(surface); isClickable=true }
        stage.addView(workerLayer,FrameLayout.LayoutParams(-1,-1)); stage.addView(content,FrameLayout.LayoutParams(-1,-1))
        root.addView(stage,LinearLayout.LayoutParams(-1,0,1f)); setContentView(root); root.requestApplyInsets()
        usable = ParcelWebProfile.configured && try { WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA) } catch (_:Exception){false}
        if (usable) WebView.setWebContentsDebuggingEnabled(false)
        renderList()
        val pending = preferences.getString("clear_provider",null)
        if(pending != null && usable) clearLogin(pending, false)
    }
    private fun label(value:String,size:Float=14f,bold:Boolean=false) = TextView(this).apply {
        text=value; textSize=size; setTextColor(ink); includeFontPadding=false; setLineSpacing(dp(3).toFloat(),1f)
        if(bold) typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL)
    }
    private fun shape(color:Int, radius:Int=16) = GradientDrawable().apply {setColor(color);cornerRadius=dp(radius).toFloat()}
    private fun action(value:String, filled:Boolean=false, click:()->Unit) = label(value,13f,true).apply {
        gravity=Gravity.CENTER; minHeight=dp(44); setPadding(dp(12),dp(8),dp(12),dp(8)); setTextColor(if(filled)Color.WHITE else purple)
        background=RippleDrawable(ColorStateList.valueOf(0x22704daa),shape(if(filled)purple else Color.TRANSPARENT,12),null)
        isFocusable=true; setOnClickListener { if(!closed && !clearing) click() }
    }
    private fun space(parent:LinearLayout,h:Int) {parent.addView(View(this),LinearLayout.LayoutParams(1,dp(h)))}
    private fun box(parent:LinearLayout):LinearLayout {
        val b=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(16),dp(14),dp(16),dp(14));background=shape(Color.WHITE)}
        parent.addView(b,LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(10)})
        return b
    }
    private fun renderList() {
        if(mode!="list" || closed) return
        headerTitle.text="取件中心"; headerAction.text="账号"; content.visibility=View.VISIBLE
        content.removeAllViews()
        val scroll=ScrollView(this).apply {isFillViewport=true;clipToPadding=false}
        val list=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setPadding(dp(18),dp(12),dp(18),dp(24))}
        scroll.addView(list);content.addView(scroll,LinearLayout.LayoutParams(-1,-1))
        val all=store.ledger.items.values.toList()
        val pending=all.count {it.takenAt==0L && it.state=="pending"}
        val summary=LinearLayout(this).apply {gravity=Gravity.CENTER_VERTICAL}
        summary.addView(label(if(pending>0 || phases.values.any{it=="empty"}) "$pending 件待取" else "包裹待查询",28f,true),LinearLayout.LayoutParams(0,-2,1f))
        summary.addView(action(if(phases.values.any{it=="syncing"})"同步中…" else "刷新") {syncAll()},LinearLayout.LayoutParams(-2,dp(44)))
        list.addView(summary)
        val latest=store.ledger.updated.values.maxOrNull()
        list.addView(label(if(latest==null)"连接账号，集中查看取件码" else "上次更新 ${time(latest)} · 已读取的包裹",12f).apply {setTextColor(muted)})
        if(!store.storageAvailable) list.addView(label("本机缓存暂不可用，本次数据仍可查看",12f).apply {setTextColor(purple)})
        space(list,16)
        val filters=LinearLayout(this)
        listOf("pending" to "待取", "transit" to "运输中", "picked" to "已取").forEach {(id,title)->
            filters.addView(action(title,filter==id){filter=id;renderList()},LinearLayout.LayoutParams(0,dp(42),1f).apply {marginEnd=dp(6)})
        }
        list.addView(filters);space(list,10)
        val chips=LinearLayout(this)
        listOf("all" to "全部", "taobao" to "淘宝", "pinduoduo" to "拼多多").forEach {(id,title)->
            chips.addView(action(title){platformFilter=id;renderList()}.apply {alpha=if(platformFilter==id)1f else .5f},LinearLayout.LayoutParams(0,dp(42),1f))
        };list.addView(chips)
        for(p in listOf("taobao","pinduoduo")) {
            val phase=phases[p]
            val connected=store.ledger.updated.containsKey(p) || preferences.getBoolean("connected_$p",false)
            if(phase in listOf("login","verify","network","unrecognized","renderer") || !connected) {
                val row=box(list)
                val line=LinearLayout(this).apply{gravity=Gravity.CENTER_VERTICAL}
                line.addView(label(name(p),14f,true),LinearLayout.LayoutParams(0,-2,1f))
                val isLogin=phase in listOf("login","verify") || !connected
                line.addView(action(if(isLogin)"连接" else "重试"){if(isLogin)authenticate(p) else sync(p)},LinearLayout.LayoutParams(dp(64),dp(44)))
                row.addView(line)
                row.addView(label(when(phase){
                    "login"->"需要登录，连接后继续同步"
                    "verify"->"需要完成官方验证"
                    "network"->"连接暂不可用，已保留上次数据"
                    "unrecognized"->"暂未读取到包裹，可重新连接后重试"
                    "renderer"->"网页组件已重启，请重试"
                    "syncing"->"正在检查登录与包裹…"
                    else->"首次连接后，在这里直接查看取件码"
                },12f).apply{setTextColor(muted)})
            }
        }
        val filtered=all.filter {p-> (platformFilter=="all" || p.provider==platformFilter) && when(filter){
            "picked"->p.takenAt>0 || p.state=="picked"
            "transit"->p.takenAt==0L && p.state=="transit"
            else->p.takenAt==0L && p.state=="pending"
        }}
        if(filtered.isEmpty()) {
            val providers=if(platformFilter=="all") listOf("taobao","pinduoduo") else listOf(platformFilter)
            val syncing=providers.any{phases[it]=="syncing"}
            val confirmedEmpty=providers.all{phases[it]=="empty"}
            val empty=box(list);space(empty,12)
            val title=if(syncing) "正在查询包裹" else if(filter=="picked") "暂无已取记录" else if(confirmedEmpty && filter=="pending") "暂无待取包裹" else "尚未读取到包裹"
            empty.addView(label(title,18f,true));space(empty,8)
            empty.addView(label(when {
                syncing->"正在同步，请稍候…"
                confirmedEmpty->"官方页面显示暂无待取包裹，身份码仍可正常使用。"
                else->"身份码可单独使用。当前未确认包裹列表，请稍后刷新。"
            },12f).apply{setTextColor(muted)})
            space(empty,12)
        }
        filtered.sortedByDescending {it.syncedAt}.groupBy {it.station.ifBlank{"驿站待核对"}}.forEach {(station,parcels)->
            space(list,8);list.addView(label("$station  ·  ${parcels.size} 件",13f,true).apply{setTextColor(muted);setPadding(dp(2),dp(4),0,dp(10))})
            parcels.forEach {parcel->
                val card=box(list)
                val top=LinearLayout(this).apply{gravity=Gravity.CENTER_VERTICAL}
                top.addView(label(parcel.courier.ifBlank {name(parcel.provider)},12f,true).apply{setTextColor(muted)},LinearLayout.LayoutParams(0,-2,1f))
                top.addView(label(if(parcel.tracking.isNotBlank())"尾号 ${parcel.tracking.takeLast(4)}" else name(parcel.provider),11f).apply{setTextColor(muted)})
                card.addView(top);space(card,8)
                val code=label(parcel.code.ifBlank{if(parcel.state=="picked")"已取件" else "取件码待更新"},if(parcel.code.isBlank())18f else 29f,true).apply{
                    setTextColor(purple);typeface=Typeface.create("monospace",Typeface.BOLD);setPadding(0,dp(6),0,dp(8));minHeight=dp(48)
                    if(parcel.code.isNotBlank()){contentDescription="取件码 ${parcel.code}，点击放大";isFocusable=true;setOnClickListener{enlarge(parcel)}}
                }
                card.addView(code)
                if(parcel.title.isNotBlank())card.addView(label(parcel.title,12f).apply{maxLines=1;ellipsize=android.text.TextUtils.TruncateAt.END;setTextColor(muted)})
                val bottom=LinearLayout(this).apply{gravity=Gravity.CENTER_VERTICAL}
                bottom.addView(label("${name(parcel.provider)} · ${time(parcel.syncedAt)}",11f).apply{setTextColor(muted)},LinearLayout.LayoutParams(0,-2,1f))
                if(parcel.takenAt>0)bottom.addView(action("撤销已取"){store.ledger.mark(parcel.key,false);store.save();renderList()})
                else if(parcel.state!="picked")bottom.addView(action("我已取件"){store.ledger.mark(parcel.key,true);store.save();renderList();toast("已移入已取，可撤销")})
                card.addView(bottom)
            }
        }
        space(list,8)
        val identity=box(list)
        identity.addView(label("出示身份码",15f,true));space(identity,6)
        identity.addView(label("扫码出库 / 亮灯时使用",12f).apply{setTextColor(muted)})
        val identityRow=LinearLayout(this)
        listOf("taobao","pinduoduo").forEach{p->identityRow.addView(action(name(p)){showIdentity(p)},LinearLayout.LayoutParams(0,dp(48),1f))}
        identity.addView(identityRow)
        if(!usable)list.addView(label("应用内同步需要 Android 9 及以上和较新的系统 WebView。可在账号菜单打开官方 App。",12f))
    }
    private fun time(value:Long)=SimpleDateFormat("MM-dd HH:mm",Locale.CHINA).format(Date(value))
    private fun toast(value:String){Toast.makeText(this,value,Toast.LENGTH_SHORT).show()}
    private fun worker(p:String):ParcelPageWorker? {
        if(!usable || clearing || closed)return null
        return workers[p] ?: try {
            ParcelPageWorker(this,p,this).also{workers[p]=it;workerLayer.addView(it.web,FrameLayout.LayoutParams(-1,-1))}
        } catch(_:Exception){phases[p]="renderer";renderList();null}
    }
    private fun sync(p:String) {
        if(!foreground || clearing)return
        val w=worker(p) ?: return
        phases[p]="syncing";w.start();renderList()
    }
    private fun pauseWorkers() {
        workers.values.forEach { it.pause() }
        phases.keys.toList().forEach { p ->
            if(phases[p]=="syncing") phases[p]=if(store.ledger.updated.containsKey(p)) "partial" else "idle"
        }
    }
    private fun syncAll(){if(mode!="list")return;listOf("taobao","pinduoduo").forEach{sync(it)}}
    private fun authenticate(p:String) {
        val w=worker(p) ?: return
        // Explicit reconnection starts a fresh account cache scope before any new response can arrive.
        store.clear(p);preferences.edit().putBoolean("connected_$p",false).apply()
        pauseWorkers();selected=p;mode="auth";phases[p]="syncing"
        headerTitle.text="连接${name(p)}";headerAction.text="完成"
        content.removeAllViews();content.setBackgroundColor(Color.WHITE)
        content.addView(label("请在官方页面登录，成功后自动返回",12f).apply{setPadding(dp(18),dp(10),dp(18),dp(10));setTextColor(muted)})
        if(p=="pinduoduo")content.addView(label("网页登录可能使拼多多 App 需要重新登录",11f).apply{setPadding(dp(18),0,dp(18),dp(10));setTextColor(muted)})
        moveTo(w,content)
        w.start(auth=true)
    }
    private fun moveTo(w:ParcelPageWorker,parent:LinearLayout){(w.web.parent as? android.view.ViewGroup)?.removeView(w.web);parent.addView(w.web,LinearLayout.LayoutParams(-1,0,1f))}
    private fun hideWorkers(){workers.values.forEach{w->(w.web.parent as? android.view.ViewGroup)?.removeView(w.web);workerLayer.addView(w.web,FrameLayout.LayoutParams(-1,-1))}}
    private fun showIdentity(p:String) {
        val w=worker(p) ?: return
        pauseWorkers();selected=p;mode="identity";clearIdentity();hideWorkers()
        headerTitle.text="${name(p)}身份码";headerAction.text="刷新";content.removeAllViews();content.setBackgroundColor(surface)
        val body=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(24),dp(24),dp(24),dp(24))}
        content.addView(body,LinearLayout.LayoutParams(-1,-1))
        body.addView(ProgressBar(this),LinearLayout.LayoutParams(dp(32),dp(32)));space(body,20)
        body.addView(label("正在获取官方身份码",18f,true));space(body,12)
        body.addView(label("获取后可直接在这里出示",13f).apply{setTextColor(muted)})
        w.start(showIdentity=true)
    }
    override fun onBatch(worker:ParcelPageWorker,batch:NativeParcelBatch,scope:String) {
        if(closed || !foreground || clearing || workers[worker.provider]!==worker)return
        store.ledger.bind(worker.provider,scope);store.ledger.merge(batch);store.save()
        preferences.edit().putBoolean("connected_${worker.provider}",true).apply()
        phases[worker.provider]=batch.phase;renderList()
    }
    override fun onVerified(worker:ParcelPageWorker) {
        if(closed || clearing || !foreground)return
        preferences.edit().putBoolean("connected_${worker.provider}",true).apply()
        store.ledger.bind(worker.provider,worker.accountScope());store.save()
        if(phases[worker.provider] !in listOf("partial","empty")) phases[worker.provider]="connected"
        if(mode=="auth" && selected==worker.provider){mode="list";hideWorkers();content.setBackgroundColor(surface);renderList();toast("已连接，正在读取取件信息");listOf("taobao","pinduoduo").filter{it!=worker.provider && preferences.getBoolean("connected_$it",false)}.forEach{sync(it)}}
    }
    override fun onIssue(worker:ParcelPageWorker,issue:String) {
        if(closed || clearing)return
        phases[worker.provider]=issue
        if(issue=="renderer")workers.remove(worker.provider)
        if(mode=="identity" && selected==worker.provider) {
            clearIdentity();content.removeAllViews()
            val body=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(24),dp(24),dp(24),dp(24))}
            content.addView(body,LinearLayout.LayoutParams(-1,-1))
            body.addView(label(if(issue in listOf("login","verify"))"需要连接${name(selected)}" else "身份码暂未获取成功",20f,true));space(body,18)
            body.addView(action(if(issue in listOf("login","verify"))"连接账号" else "重新获取",true){if(issue in listOf("login","verify"))authenticate(selected) else showIdentity(selected)})
            space(body,10);body.addView(action("打开官方 App"){openOfficial(selected)})
        } else if(mode=="auth")toast("可继续完成登录，然后点右上角“完成”")
        renderList()
    }
    override fun onIdentity(worker:ParcelPageWorker,bitmap:Bitmap) {
        if(closed || !foreground || mode!="identity" || selected!=worker.provider){bitmap.recycle();return}
        clearIdentity();identityBitmap=bitmap;content.removeAllViews()
        val body=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(20),dp(24),dp(20),dp(24));setBackgroundColor(Color.WHITE)}
        content.addView(body,LinearLayout.LayoutParams(-1,-1))
        body.addView(label("${name(selected)} · 扫码出库",18f,true));space(body,24)
        val image=ImageView(this).apply{setImageBitmap(bitmap);adjustViewBounds=true;scaleType=ImageView.ScaleType.FIT_CENTER;setBackgroundColor(Color.WHITE);setPadding(dp(12),dp(12),dp(12),dp(12));contentDescription="官方实时身份码"}
        body.addView(image,LinearLayout.LayoutParams(-1,dp(if(bitmap.width>bitmap.height*2)180 else 300)))
        space(body,20);body.addView(label("请向驿站出示 · 仅本次页面显示",12f).apply{setTextColor(muted)})
        body.addView(action("刷新身份码"){showIdentity(selected)})
        window.attributes=window.attributes.apply{screenBrightness=1f}
        // Conservative presentation refresh, not a claim about the platform's actual expiry time.
        handler.postDelayed({if(foreground && mode=="identity")showIdentity(selected)},30_000)
    }
    private fun clearIdentity(){handler.removeCallbacksAndMessages(null);content.removeAllViews();identityBitmap?.recycle();identityBitmap=null;window.attributes=window.attributes.apply{screenBrightness=originalBrightness}}
    private fun enlarge(parcel:NativeParcel) {
        if(!foreground)return
        val body=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;setPadding(dp(22),dp(20),dp(22),dp(16))}
        body.addView(label(parcel.station.ifBlank{"驿站待核对"},14f));space(body,14)
        body.addView(label(parcel.code,36f,true).apply{setTextColor(purple);typeface=Typeface.MONOSPACE;setTextIsSelectable(true);gravity=Gravity.CENTER})
        space(body,10);body.addView(label("${name(parcel.provider)} · ${time(parcel.syncedAt)}",12f).apply{setTextColor(muted)})
        dialog=AlertDialog.Builder(this).setView(body).setPositiveButton("复制取件码"){_,_->(getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("取件码",parcel.code));toast("取件码已复制")}.setNegativeButton("关闭",null).show()
    }
    private fun accounts() {
        dialog=AlertDialog.Builder(this).setTitle("快递账号").setItems(arrayOf("连接淘宝","连接拼多多","退出淘宝并清除缓存","退出拼多多并清除缓存","打开淘宝 App","打开拼多多 App")){_,i->
            when(i){0->authenticate("taobao");1->authenticate("pinduoduo");2->clearLogin("taobao",true);3->clearLogin("pinduoduo",true);4->openOfficial("taobao");5->openOfficial("pinduoduo")}
        }.setNegativeButton("关闭",null).show()
    }
    private fun clearLogin(p:String,notify:Boolean) {
        if(!usable || closed || clearing)return
        if(!preferences.edit().putString("clear_provider",p).commit()){toast("暂时无法清理，请重试");return}
        clearing=true;workers.remove(p)?.destroy();store.clear(p)
        preferences.edit().putBoolean("connected_$p",false).apply();phases[p]="login"
        val sites=if(p=="taobao")listOf("taobao.com","tmall.com","alipay.com","cainiao.com","alibaba.com") else listOf("pinduoduo.net")
        fun next(index:Int){
            if(closed)return
            if(index==sites.size){preferences.edit().remove("clear_provider").commit();clearing=false;renderList();if(notify)toast("已退出${name(p)}");return}
            try{WebStorageCompat.deleteBrowsingDataForSite(WebStorage.getInstance(),sites[index]){next(index+1)}}catch(_:Exception){clearing=false;usable=false;toast("清理尚未完成，请关闭后重试")}
        }
        next(0)
    }
    private fun openOfficial(p:String){try{val t=ParcelShortcutContract.target(p,setOf("provider"));startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(t.uri)).setPackage(t.packageName))}catch(_:Exception){toast("请先安装${name(p)} App")}}
    private fun finishAuthentication() {
        // Completion always exits the login presentation; the subsequent query validates the session.
        val provider=selected
        back()
        if(foreground && mode=="list") sync(provider)
    }
    private fun back(){if(mode=="list"){finish();return};pauseWorkers();clearIdentity();mode="list";hideWorkers();content.setBackgroundColor(surface);renderList()}
    @Deprecated("Legacy Android back dispatch") override fun onBackPressed(){back()}
    override fun onResume(){super.onResume();foreground=true;if(!::store.isInitialized)return;if(mode=="auth")workers[selected]?.continueAuthentication() else if(mode=="identity")showIdentity(selected) else syncAll()}
    override fun onPause(){foreground=false;dialog?.dismiss();dialog=null;pauseWorkers();if(mode=="identity")clearIdentity();if(usable)CookieManager.getInstance().flush();super.onPause()}
    override fun onDestroy(){closed=true;handler.removeCallbacksAndMessages(null);workers.values.toList().forEach{it.destroy()};workers.clear();identityBitmap?.recycle();super.onDestroy()}
}
