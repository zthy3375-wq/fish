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
      String mode=args.getString("mode");
      boolean old=mode.equals("previous");
      until("navigator.onLine===false","device must remain offline");
      if(old){
        for(int i=0;i<5;i++)click("document.querySelector('.mascot-touch')","old fish unavailable");
        click(button("我的"),"profile tab unavailable");
        click("document.querySelector('.collection-entry')","old hall unavailable");
        until("!!document.querySelector('[data-code=puff].unlocked')","old unlock missing");
        click("document.querySelector('[data-code=puff]')","old medal missing");
        click("document.querySelector('.collect-detail .wear')","old pin unavailable");
        until("document.querySelector('dialog[open] .wear')?.textContent.includes('取下')===true","pin failed");
      }else{
        click(button("我的"),"profile tab unavailable");
        until("document.querySelector('.collection-entry .private-shelf')?.textContent.includes('别戳啦！')===true","old pin absent from exhibit");
        until("document.querySelector('.profile-strip').nextElementSibling.classList.contains('collection-entry')","exhibit not near nickname");
        click("document.querySelector('.case-rail button')","medal unavailable");
        until("document.querySelector('dialog.collect-detail[open] h2')?.textContent==='别戳啦！'","incorrect deeplink");
        until("document.querySelector('dialog[open] .wear')?.textContent.includes('取下')===true","old pin lost");
        click("document.querySelector('.detail-close')","detail close missing");
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
