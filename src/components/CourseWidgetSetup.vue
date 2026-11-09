<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref} from 'vue';
import {widgetSupported,courseWidgetStatus,pinCourseWidget,openWidgetHome,hasNewCourseWidget} from '../services/course-widget';
const count=ref<number|null>(null),supported=ref(true),busy=ref(false);
const stage=ref<'idle'|'pending'|'unavailable'|'unsupported'|'added'>('idle');
const message=ref(''),baseline=ref<number[]|null>(null);
let disposed=false,version=0,timer:ReturnType<typeof setInterval>|undefined,deadline=0;
function stop(){if(timer)clearInterval(timer);timer=undefined}
const statusMessage=computed(()=>{
 if(message.value)return message.value;
 if(stage.value==='added')return '已检测到新添加的桌面课表。';
 if(stage.value==='pending')return '添加请求已发送，尚未确认添加成功。如果没有弹窗，请按下方步骤手动添加。';
 if(stage.value==='unsupported')return '当前桌面不支持从应用内添加，请从桌面小组件列表手动添加。';
 if(stage.value==='unavailable')return '暂时无法确认添加结果，请检查桌面或按下方步骤手动添加。';
 return count.value!==null&&count.value>0?'桌面上已有 '+count.value+' 个课表小组件，可查看或继续添加。':'可以请求系统添加，也可以从桌面小组件列表添加。';
});
async function check(){
 const token=version;
 if(!widgetSupported()){supported.value=false;stage.value='unsupported';return;}
 try{
  const result=await courseWidgetStatus();
  if(disposed||token!==version)return;
  if(!Array.isArray(result.ids)||!result.ids.every(id=>Number.isInteger(id)&&id>0))throw Error();
  supported.value=result.supported;count.value=result.ids.length;
  if(baseline.value!==null&&hasNewCourseWidget(baseline.value,result.ids)){stage.value='added';stop();}
  else if(!result.supported&&stage.value==='idle')stage.value='unsupported';
 }catch{if(!disposed&&token===version&&stage.value!=='pending')stage.value='unavailable';}
}
async function add(){
 if(busy.value||stage.value==='pending'||!widgetSupported())return;
 busy.value=true;message.value='';stop();const token=++version;
 try{
  const result=await pinCourseWidget();
  if(disposed||token!==version)return;
  baseline.value=Array.isArray(result.baselineIds)?result.baselineIds:null;
  stage.value=result.requested?'pending':'unsupported';
  if(result.requested){
   deadline=Date.now()+20000;
   timer=setInterval(()=>{if(Date.now()>=deadline){stop();if(stage.value==='pending')stage.value='unavailable';return;}if(!document.hidden)void check();},2000);
   void check();
  }else supported.value=false;
 }catch{if(!disposed&&token===version)stage.value='unavailable';}
 finally{if(!disposed&&token===version)busy.value=false;}
}
async function home(){
 message.value='';
 try{await openWidgetHome();}
 catch{if(!disposed)message.value='请使用手机主页手势返回桌面，然后按下方步骤添加。';}
}
function foreground(){if(!document.hidden)void check()}
onMounted(()=>{void check();document.addEventListener('visibilitychange',foreground)});
onUnmounted(()=>{disposed=true;version++;stop();document.removeEventListener('visibilitychange',foreground)});
</script>
<template>
 <section class="widget-setup" aria-label="桌面课表添加">
  <h2>桌面课表</h2>
  <p class="widget-intro">今天、明天的课程，一眼查看。默认采用紧凑的 4×2 尺寸。</p>
  <p class="widget-status" role="status">{{statusMessage}}</p>
  <button class="primary" :disabled="busy||stage==='pending'||!supported||!widgetSupported()" @click="add">{{busy?'正在发送…':stage==='pending'?'等待添加结果…':'请求系统添加'}}</button>
  <section class="widget-manual" aria-labelledby="widget-manual-title">
   <h3 id="widget-manual-title">没有弹窗？从桌面手动添加</h3>
   <ol><li>长按桌面空白处，进入“小组件”或“添加小部件”。</li><li>在应用列表中找到“邯院通”。</li><li>选择“邯院通 · 近日课程”，拖到桌面并调整大小。</li></ol>
   <p>如果先看到推荐内容，请继续查找“全部小组件”或应用小组件列表。</p>
   <div class="widget-manual-actions"><button class="secondary" :disabled="!widgetSupported()" @click="home">前往桌面</button><button class="text-button" @click="check">检查添加结果</button></div>
  </section>
  <p class="widget-note">已添加的旧组件如果仍占着大格子，请长按缩小，或删除后重新添加。课表更新请在应用内刷新。</p>
 </section>
</template>
<style scoped>
.widget-setup{padding:8px 2px 4px}.widget-setup h2{font-size:21px;margin-bottom:7px}.widget-intro,.widget-note{font-size:12px;color:var(--color-muted);line-height:1.7}.widget-status{font-size:13px;line-height:1.8;background:var(--color-tint);padding:12px;border-radius:14px;margin:16px 0 12px}.widget-setup>.primary{width:100%;min-height:44px}.widget-manual{border-top:1px solid var(--color-divider);margin-top:20px;padding-top:16px}.widget-manual h3{font-size:14px;margin:0 0 10px}.widget-manual ol{padding-left:21px;margin:0;display:grid;gap:9px;font-size:13px;line-height:1.7}.widget-manual>p{font-size:11px;line-height:1.7;color:var(--color-muted);margin-top:12px}.widget-manual-actions{display:flex;gap:12px;align-items:center;margin:14px 0}.widget-manual-actions button{min-height:44px}.widget-note{margin-top:12px}
</style>
