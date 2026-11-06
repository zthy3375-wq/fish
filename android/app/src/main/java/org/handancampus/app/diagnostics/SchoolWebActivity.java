package org.handancampus.app.diagnostics;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.content.Intent;
import android.graphics.Color;
import android.net.http.SslError;
import android.webkit.*;
import android.view.*;
import android.widget.*;
import org.handancampus.app.BuildConfig;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;

/** Standalone, non-exported, private-process browser. NO Capacitor bridge or JavascriptInterface. */
public class SchoolWebActivity extends Activity {
    private static boolean dataDirectorySet=false;
    private WebView web;
    private TextView status;
    private Button detect, preview;
    private String lastReport;
    private boolean closing=false, busy=false;
    private int generation=0;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private String reader;
    private boolean automatic;
    private int autoAttempts=0;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        automatic=getIntent().getBooleanExtra("automatic",false);
        if(Build.VERSION.SDK_INT<28 || !DiagnosticPolicy.enabled(BuildConfig.DEBUG,BuildConfig.ACADEMIC_DIAGNOSTICS)) {finish();return;}
        // Separate from the Capacitor WebView's data directory and local student storage.
        if(!dataDirectorySet){WebView.setDataDirectorySuffix("school-diagnostic-session");dataDirectorySet=true;}
        try (java.io.InputStream input = getAssets().open("academic-diagnostic-reader.js")) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream(); byte[] buffer = new byte[4096]; int count;
            while ((count=input.read(buffer))!=-1) out.write(buffer,0,count);
            reader = out.toString("UTF-8");
        }
        catch(Exception e){finish();return;}
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_SECURE,WindowManager.LayoutParams.FLAG_SECURE);
        getWindow().setStatusBarColor(Color.rgb(247,248,251));
        getWindow().setNavigationBarColor(Color.rgb(247,248,251));
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(Color.rgb(247,248,251));
        root.setFitsSystemWindows(true);
        LinearLayout toolbar=new LinearLayout(this);toolbar.setGravity(Gravity.CENTER_VERTICAL);
        Button close=new Button(this);close.setText("关闭");close.setOnClickListener(v->cancel());toolbar.addView(close);
        TextView host=new TextView(this);host.setText("邯郸学院官方网页\njwgl.hdc.edu.cn · 实验读取");host.setTextColor(Color.rgb(44,59,77));host.setTextSize(13);toolbar.addView(host,new LinearLayout.LayoutParams(0,-2,1));
        Button retry=new Button(this);retry.setText("重试");retry.setOnClickListener(v->{if(web!=null&&DiagnosticPolicy.allowedSchoolUrl(web.getUrl()))web.reload();});toolbar.addView(retry);root.addView(toolbar);
        status=new TextView(this);status.setText("请自行登录并进入本人课表。fish 不读取登录表单。未知认证跳转将阻止；系统浏览器登录不与此窗口共享。");status.setTextSize(12);status.setPadding(18,10,18,10);root.addView(status);
        web=new WebView(this);root.addView(web,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout actions=new LinearLayout(this);
        detect=new Button(this);detect.setText("检测课表结构");detect.setOnClickListener(v->read(false));actions.addView(detect,new LinearLayout.LayoutParams(0,-2,1));
        preview=new Button(this);preview.setText("读取课程供本机预览");preview.setEnabled(false);preview.setOnClickListener(v->new AlertDialog.Builder(this).setTitle("仅在本机预览本人课程")
            .setMessage("将从已识别的课表容器读取课程、教师、教室、星期、节次和周次，交给 fish 本机预览。不会上传；只有你另行确认后才保存。请确认你有权在学校允许范围内处理这些数据。")
            .setNegativeButton("取消",null).setPositiveButton("读取",(d,w)->read(true)).show());actions.addView(preview,new LinearLayout.LayoutParams(0,-2,1));root.addView(actions);
        setContentView(root);
        WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);settings.setSupportMultipleWindows(false);settings.setSaveFormData(false);
        if(Build.VERSION.SDK_INT>=26) {settings.setSafeBrowsingEnabled(true);web.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);}
        WebView.setWebContentsDebuggingEnabled(false);
        web.setDownloadListener((a,b,c,d,e)->status.setText("本工具不代下载学校文件，请通过学校官方浏览器入口自行操作。"));
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest request){request.deny();}
            @Override public boolean onShowFileChooser(WebView view,ValueCallback<android.net.Uri[]> callback,FileChooserParams p){return false;}
            @Override public boolean onCreateWindow(WebView v,boolean dialog,boolean user,android.os.Message msg){return false;}
        });
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                if(DiagnosticPolicy.allowedSchoolUrl(request.getUrl().toString()))return false;
                status.setText("已阻止未经验证的站外跳转。请在系统浏览器完成，或仅分享不含参数的认证域名供核实。");return true;
            }
            @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){
                if(DiagnosticPolicy.allowedSchoolUrl(request.getUrl().toString()))return null;
                return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));
            }
            @Override public void onPageStarted(WebView view,String url,android.graphics.Bitmap icon){
                generation++;autoAttempts=0;lastReport=null;preview.setEnabled(false);detect.setEnabled(false);busy=false;
                final int token=generation;
                handler.postDelayed(()->{if(!closing&&token==generation){status.setText("页面加载较久。可等待、重试或关闭；未判断登录成功或失败。");detect.setEnabled(true);}},30000);
            }
            @Override public void onPageFinished(WebView view,String url){
                detect.setEnabled(DiagnosticPolicy.readableCourseCandidate(url));
                if(automatic)handler.postDelayed(()->autoRead(),700);
                status.setText(DiagnosticPolicy.readableCourseCandidate(url)?"网页已加载。请手动查询本人课表，再点击检测。":"学校登录页面：请自行输入信息并完成验证。此处不执行页面读取。");
            }
            @Override public void onReceivedSslError(WebView v,SslErrorHandler h,SslError e){h.cancel();status.setText("HTTPS 证书验证失败，已停止加载；不会忽略证书错误。");detect.setEnabled(false);}
            @Override public void onReceivedError(WebView v,WebResourceRequest r,WebResourceError e){if(r.isForMainFrame()){generation++;status.setText("页面网络错误，请检查连接后重试；没有采集数据。");detect.setEnabled(false);}}
            @Override public void onReceivedHttpError(WebView v,WebResourceRequest r,WebResourceResponse e){if(r.isForMainFrame()){status.setText("学校页面返回错误，请稍后重试或关闭。未记录响应内容。");detect.setEnabled(false);}}
        });
        CookieManager cookies=CookieManager.getInstance();cookies.setAcceptCookie(true);cookies.setAcceptThirdPartyCookies(web,false);
        cookies.removeAllCookies(done->{if(!closing){WebStorage.getInstance().deleteAllData();web.clearCache(true);web.loadUrl(DiagnosticPolicy.OFFICIAL_LOGIN);}});
    }
    private void autoRead(){
        if(closing||!automatic||web==null||autoAttempts++>=90)return;
        if(!busy&&DiagnosticPolicy.readableCourseCandidate(web.getUrl())){
            read(true);
            // Follow only a unique, existing same-origin course-menu link; never invent an endpoint or execute onclick.
            if(autoAttempts==3)web.evaluateJavascript("(function(){const urls=new Set();for(const a of document.querySelectorAll('a[href]')){const label=a.textContent.trim();if(!['学生课表查询','个人课表','我的课表'].includes(label))continue;try{const u=new URL(a.getAttribute('href'),location.href);if(u.origin===location.origin&&u.pathname.startsWith('/kbcx/'))urls.add(u.href)}catch{}}if(urls.size===1)location.assign(Array.from(urls)[0]);})()",null);
        }
        handler.postDelayed(()->autoRead(),2000);
    }
    private void read(boolean collect){
        if(closing||busy||web==null||!DiagnosticPolicy.readableCourseCandidate(web.getUrl()))return;
        busy=true;final int token=++generation;detect.setEnabled(false);preview.setEnabled(false);
        handler.postDelayed(()->{if(token==generation&&!closing&&busy){generation++;busy=false;detect.setEnabled(true);status.setText("结构检查超时，未生成结果，请重试或关闭。");}},8000);
        web.evaluateJavascript("("+reader+")("+(collect?"true":"false")+")", raw->{
            if(closing||token!=generation)return;
            busy=false;detect.setEnabled(true);
            try{
                if(raw==null||raw.length()>700000)throw new Exception();
                Object decoded=new org.json.JSONTokener(raw).nextValue();if(!(decoded instanceof String))throw new Exception();
                String data=(String)decoded;if(data.length()>300000)throw new Exception();
                JSONObject payload=new JSONObject(data),observation=payload.getJSONObject("observation");
                String container=observation.getString("container");
                if(!java.util.Arrays.asList("unrecognized","kbList","zf-grid","zf-list").contains(container))throw new Exception();
                lastReport=observation.toString();
                if(collect){
                    if("unrecognized".equals(container)||observation.optInt("invalidCount")>0||observation.optBoolean("specialArrangements")||observation.optBoolean("frameLimit")){
                        if(!"unrecognized".equals(container))status.setText("存在未识别、特殊或异常安排，已停止读取。可返回脱敏结构报告，不能静默丢课。");return;
                    }
                    if(payload.getJSONArray("kbList").length()==0)return;
                    Intent result=new Intent();result.putExtra("observation",lastReport);result.putExtra("automatic",automatic);result.putExtra("courses",payload.getJSONArray("kbList").toString());complete(result);return;
                }
                int count=observation.optInt("recordCount");
                preview.setEnabled(!"unrecognized".equals(container)&&count>0&&observation.optInt("invalidCount")==0&&!observation.optBoolean("specialArrangements")&&!observation.optBoolean("frameLimit"));
                new AlertDialog.Builder(this).setTitle("课表结构检查")
                    .setMessage("结构："+container+"\n可识别安排数："+count+"\n异常数："+observation.optInt("invalidCount")+"\n报告不含真实课程内容。真实系统兼容性仍需本人核对。")
                    .setNegativeButton("继续查看网页",null).setPositiveButton("返回脱敏报告",(d,w)->{Intent result=new Intent();result.putExtra("observation",lastReport);complete(result);}).show();
            }catch(Exception e){status.setText("返回数据无法安全过滤，已停止输出。请使用本地人工检查或自行脱敏的截图。");}
        });
    }
    private void complete(Intent result){setResult(RESULT_OK,result);cleanup(()->finish());}
    private void cancel(){setResult(RESULT_CANCELED);cleanup(()->finish());}
    private void cleanup(Runnable done){
        if(closing)return;closing=true;generation++;handler.removeCallbacksAndMessages(null);
        if(web!=null){web.stopLoading();web.clearHistory();web.clearFormData();web.clearCache(true);}
        WebStorage.getInstance().deleteAllData();
        CookieManager.getInstance().removeAllCookies(success->{CookieManager.getInstance().flush();done.run();});
        handler.postDelayed(done,1500);
    }
    @Override public void onBackPressed(){if(web!=null&&web.canGoBack()){web.goBack();}else cancel();}
    @Override protected void onStop(){super.onStop();if(!isChangingConfigurations()&&!closing)cancel();}
    @Override protected void onDestroy(){generation++;handler.removeCallbacksAndMessages(null);if(web!=null){web.stopLoading();web.destroy();web=null;}CookieManager.getInstance().removeAllCookies(null);CookieManager.getInstance().flush();WebStorage.getInstance().deleteAllData();super.onDestroy();}
}
