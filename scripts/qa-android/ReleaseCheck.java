package org.handancampus.releasecheck;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;
import org.json.JSONObject;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class ReleaseCheck extends Instrumentation {
  private Bundle args;
  private Activity activity;
  @Override public void onCreate(Bundle options) { super.onCreate(options); args=options; start(); }
  private WebView web(View view) {
    if(view instanceof WebView) return (WebView)view;
    if(view instanceof ViewGroup) {
      ViewGroup group=(ViewGroup)view;
      for(int i=0;i<group.getChildCount();i++){WebView found=web(group.getChildAt(i));if(found!=null)return found;}
    }
    return null;
  }
  private boolean js(String expression) throws Exception {
    CountDownLatch latch=new CountDownLatch(1);
    AtomicReference<String> value=new AtomicReference<>();
    runOnMainSync(()->{
      WebView page=web(activity.getWindow().getDecorView());
      if(page==null){latch.countDown();return;}
      page.evaluateJavascript(expression, result->{value.set(result);latch.countDown();});
    });
    if(!latch.await(5,TimeUnit.SECONDS))throw new Exception("WebView evaluation timed out");
    return "true".equals(value.get());
  }
  private void until(String condition,String message) throws Exception {
    long until=SystemClock.elapsedRealtime()+40000;
    while(SystemClock.elapsedRealtime()<until){if(js(condition))return;SystemClock.sleep(150);}
    throw new Exception(message);
  }
  private void click(String finder,String message) throws Exception {
    until("(()=>{const button=("+finder+");if(!button||button.disabled)return false;button.click();return true})()",message);
  }
  private static String button(String text) {
    return "Array.from(document.querySelectorAll('button')).find(b=>b.textContent.trim()==="+JSONObject.quote(text)+")";
  }
  @Override public void onStart() {
    Bundle result=new Bundle();
    try{
      Intent launch=getTargetContext().getPackageManager().getLaunchIntentForPackage("org.handancampus.app");
      launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      activity=startActivitySync(launch);
      until("document.querySelectorAll('.life-wallets .life-card').length===2","wallets unavailable");
      until("(()=>{const [a,b]=document.querySelectorAll('.life-wallets .life-card');const x=a.getBoundingClientRect(),y=b.getBoundingClientRect();return x.width>0&&x.right<=y.left+1&&Math.abs(x.top-y.top)<2&&a.textContent.includes('趣智校园')&&b.textContent.includes('胖乖生活')})()","wallets not side by side");
      long since=SystemClock.elapsedRealtime();
      boolean offline="offline".equals(args.getString("mode"));
      if(!offline)click(button("社区"),"community tab unavailable");
      if("signup".equals(args.getString("mode"))) {
        click(button("注册账号"),"registration entry unavailable");
        until("document.querySelectorAll('.th-auth input').length===2&&!!document.querySelector('input[autocomplete=new-password]')","two-field form unavailable");
        String login=JSONObject.quote(args.getString("login")),pass=JSONObject.quote(args.getString("pass"));
        until("(()=>{const fields=document.querySelectorAll('.th-auth input');const values=["+login+","+pass+"];fields.forEach((e,i)=>{e.value=values[i];e.dispatchEvent(new Event('input',{bubbles:true}));});return fields[0].value===values[0]&&fields[1].value===values[1]&&fields[0].form.checkValidity()})()","input validation failed");
        click(button("创建账号"),"create account disabled");
      }
      if(!offline)until("!!document.querySelector('.th-nav .th-self')&&!document.querySelector('.th-auth')","authenticated feed unavailable");
      if(!"signup".equals(args.getString("mode"))) {
        click(button("我的"),"profile tab unavailable");
        if(offline)until("navigator.onLine===false","network still available in offline test");
        click("document.querySelector('.collection-entry')","global cabinet entry missing");
        until("document.querySelectorAll('.cabinet-grid button').length===25 && !!document.querySelector('[data-code=welcome].unlocked') && !!document.querySelector('[data-code=arrival].unlocked')","local or server-verified achievement missing");
        until("document.querySelector('.collection-account h3')?.textContent.length>0","account summary missing");
        click("document.querySelector('[data-code=welcome]')","local medal missing");
        if("upgrade".equals(args.getString("mode")))click("document.querySelector('.collect-detail .wear')","private showcase action missing");
        until("document.querySelector('.wear')?.textContent.includes('取下')===true","local shelf not persisted");
        click("document.querySelector('.detail-close')","detail close unavailable");
        click("document.querySelector('[data-code=arrival]')","account medal missing");
        until("document.querySelector('dialog.collect-detail[open] h2')?.textContent==='破壳而出'","second medal detail lost");
        if("upgrade".equals(args.getString("mode")))click("document.querySelector('dialog[open] .wear')","server showcase action missing");
        until(offline?"document.querySelector('.wear')?.textContent.includes('已展示')===true && document.querySelector('.wear').disabled":"document.querySelector('.wear')?.textContent.includes('取下')===true","public showcase not persisted");
        click("document.querySelector('.detail-close')","account detail close unavailable");
        click(button("隐藏"),"hidden filter missing");
        until("document.querySelectorAll('.cabinet-grid button').length===1 && document.querySelector('.cabinet-grid')?.textContent.includes('未知奇遇')===true","hidden clue leaked");

      }
      result.putString("qa","PASS "+args.getString("mode"));
      result.putString("elapsed",Long.toString(SystemClock.elapsedRealtime()-since));
      finish(Activity.RESULT_OK,result);
    }catch(Throwable error){
      try {
        result.putString("detail", "open="+js("!!document.querySelector('dialog.collect-detail[open]')")+" arrival="+js("!!document.querySelector('[data-code=arrival].unlocked')")+" selectedArrival="+js("document.querySelector('.collect-detail h2')?.textContent==='破壳而出'")+" wear="+js("!!document.querySelector('.collect-detail .wear')")+" disabled="+js("document.querySelector('.collect-detail .wear')?.disabled===true")+" online="+js("navigator.onLine===true"));
      } catch(Exception ignored){}
      result.putString("qa","FAIL "+error.getClass().getSimpleName()+" "+error.getMessage());
      finish(Activity.RESULT_CANCELED,result);
    }
  }
}
