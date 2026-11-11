<script setup lang="ts">
import {onMounted,onBeforeUnmount,ref} from 'vue';
import {Bike,ScanLine,Copy,ArrowUpRight} from 'lucide-vue-next';
import {scanBike,actOnBike,clearBike,bikeSupported,bikeName,bikeStatusMessage,bikeErrorMessage,bikeShortcut,lastBikeChoice,chooseBike,loadRecentBike,saveRecentBike,forgetRecentBike,officialAppName,type ScannedBike,type BikeMode,type BikeProvider,type BikeStatus} from '../services/bike-scan';
const supported=bikeSupported(),bike=ref<ScannedBike>(),busy=ref(false),message=ref(''),selected=ref(lastBikeChoice()),recent=ref(loadRecentBike()),more=ref(false);
let disposed=false;
function refreshRecent(){recent.value=loadRecentBike()}
function select(provider:BikeProvider){selected.value=provider;chooseBike(provider);bike.value=undefined;more.value=false}
function record(provider:BikeProvider,status:BikeStatus,number?:string){const r=saveRecentBike(provider,status,number);if(r)recent.value=r}
async function scan(){
 if(!supported||busy.value)return;busy.value=true;bike.value=undefined;message.value='';
 try{const result=await scanBike();if(!disposed){bike.value=result;selected.value=result.provider;chooseBike(result.provider)}}
 catch(e){if(!disposed)message.value=bikeErrorMessage(e)}finally{if(!disposed)busy.value=false}
}
async function start(provider:BikeProvider){
 if(busy.value)return;
 select(provider);busy.value=true;await clearBike();if(disposed)return;busy.value=false;
 if(provider==='hello'){await scan();return}
 await shortcut(provider,'scanner');
}
async function shortcut(provider:BikeProvider,mode:'scanner'|'home',target:'app'|'alipay'='app'){
 if(!supported||busy.value)return;busy.value=true;message.value='';
 try{const status=await bikeShortcut(provider,mode,target);if(!disposed){message.value=bikeStatusMessage(status);if(mode==='scanner')record(provider,status)}}
 catch(e){if(!disposed)message.value=bikeErrorMessage(e)}finally{if(!disposed)busy.value=false}
}
async function act(mode:BikeMode|'copy'){
 if(busy.value||!bike.value)return;busy.value=true;message.value='';const current=bike.value;
 try{const status=await actOnBike(current,mode);if(!disposed){message.value=bikeStatusMessage(status);record(current.provider,status,current.number)}}
 catch(e){if(!disposed)message.value=bikeErrorMessage(e)}finally{if(!disposed)busy.value=false}
}
async function returnOfficial(){refreshRecent();if(recent.value)await shortcut(recent.value.provider,'home',recent.value.target);else message.value='最近入口已过期，请手动打开官方应用查看当前骑行。'}
function forget(){if(busy.value)return;forgetRecentBike();recent.value=undefined;bike.value=undefined;void clearBike();message.value='已清除本机入口记录，官方订单不受影响；请在官方端确认还车。'}
onMounted(()=>{window.addEventListener('focus',refreshRecent);document.addEventListener('visibilitychange',refreshRecent)});
onBeforeUnmount(()=>{disposed=true;bike.value=undefined;void clearBike();window.removeEventListener('focus',refreshRecent);document.removeEventListener('visibilitychange',refreshRecent)});
</script>
<template>
 <section class="bike-scan" aria-label="快捷用车" :aria-busy="busy">
  <header><Bike :size="24"/><div><h2>快捷用车</h2><p>登录、开锁与还车在官方端完成</p></div></header>
  <template v-if="supported">
   <div class="bike-choices">
    <button :class="{selected:selected==='hello'}" :aria-pressed="selected==='hello'" :disabled="busy" @click="start('hello')"><strong>哈啰扫码用车</strong><small>扫码后前往支付宝</small></button>
    <button :class="{selected:selected==='meituan'}" :aria-pressed="selected==='meituan'" :disabled="busy" @click="start('meituan')"><strong>美团官方扫码</strong><small>尝试打开美团扫一扫</small></button>
   </div>
   <div v-if="recent" class="bike-recent"><div><strong>最近打开的入口 · {{officialAppName(recent)}}</strong><small>{{recent.number?`车号 ${recent.number}`:'从官方入口扫码'}}</small></div><button class="primary full" :disabled="busy" @click="returnOfficial">返回官方用车 <ArrowUpRight :size="16"/></button><p>可能进入首页，骑行与还车结果请在官方端查看。</p><button class="text-action" :disabled="busy" @click="forget">清除入口记录</button></div>
   <div v-if="bike" class="bike-result"><span>已识别 {{bikeName(bike)}}</span><strong>{{bike.number}}</strong><small>请与车身编号核对</small></div>
   <button v-if="bike" class="primary full" :disabled="busy" @click="act('use')"><ArrowUpRight :size="18"/>前往用车</button>
   <p v-if="bike" class="bike-note">{{bike.provider==='hello'?'将尝试把车码带入支付宝哈啰，请在官方页面核对车辆和费用。':'美团车码网页可能进入下载页，可改用上方官方扫码。'}}</p>
   <button v-if="bike" class="bike-rescan" :disabled="busy" @click="scan"><ScanLine :size="18"/>重新扫码</button>
   <button class="text-action" :disabled="busy" :aria-expanded="more" @click="more=!more">{{more?'收起其他方式':'其他打开方式'}}</button>
   <div v-if="more" class="bike-fallbacks">
    <button v-if="!bike" :disabled="busy" @click="scan"><ScanLine :size="14"/>本机识别车码</button>
    <button :disabled="busy" @click="shortcut(selected,'home')">打开{{selected==='hello'?'哈啰':'美团'}} App 首页</button>
    <template v-if="bike"><button :disabled="busy" @click="act('copy')"><Copy :size="14"/>复制车辆编号</button><button :disabled="busy" @click="act('web')">系统打开车码网页</button></template>
    <button v-if="selected==='hello'" :disabled="busy" @click="shortcut('hello','scanner')">尝试哈啰 App 扫码</button>
   </div>
   <p class="bike-note">未跳转或入口不支持时，可手动打开官方 App 扫码。官方账号与登录状态由对应 App 或小程序管理。</p>
   <p v-if="busy||message" role="status" aria-live="polite" class="bike-message">{{busy?'正在处理…':message}}</p>
  </template>
  <p v-else class="bike-intro">请在 Android 客户端中使用快捷用车。</p>
 </section>
</template>
<style scoped>
.bike-scan{padding:22px 18px 18px}.bike-scan header{display:flex;align-items:center;gap:12px;color:var(--color-primary);margin:0 32px 16px 0}.bike-scan h2{font-size:21px;color:var(--color-text);margin:0}.bike-scan header p{font-size:11px;color:var(--color-muted);margin:5px 0 0}.bike-choices{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px}.bike-choices button{padding:12px 10px;text-align:left;border:1px solid var(--color-border);border-radius:14px;background:var(--color-surface);min-width:0}.bike-choices button.selected{background:var(--color-highlight);border-color:var(--color-primary)}.bike-choices strong{display:block;font-size:14px;color:var(--color-text)}.bike-choices small{display:block;font-size:10px;line-height:1.7;color:var(--color-muted);margin-top:5px}.bike-recent{padding:12px;border:1px solid var(--color-border);border-radius:14px;margin-bottom:12px}.bike-recent strong{font-size:12px}.bike-recent small{display:block;font-size:11px;color:var(--color-muted);margin:6px 0 10px}.bike-recent p{font-size:10px;line-height:1.7;color:var(--color-muted);margin:7px 0 0}.bike-result{display:grid;gap:7px;padding:14px;margin-bottom:12px;background:var(--color-highlight);border:1px solid var(--color-border);border-radius:16px}.bike-result span{font-size:13px;color:var(--color-primary)}.bike-result strong{font-size:27px;letter-spacing:1px;font-variant-numeric:tabular-nums;color:var(--color-text)}.bike-result small{font-size:11px;color:var(--color-muted)}.bike-intro,.bike-note{font-size:11px;line-height:1.8;color:var(--color-muted);margin:10px 0}.bike-rescan{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:44px;margin-top:10px;border:1px solid var(--color-border);border-radius:12px;color:var(--color-primary);background:var(--color-surface)}.text-action{min-height:44px;font-size:12px;color:var(--color-primary)}.bike-fallbacks{display:flex;flex-wrap:wrap;gap:0 14px}.bike-fallbacks button{display:flex;align-items:center;gap:5px;font-size:12px;min-height:44px;color:var(--color-primary)}.bike-message{font-size:12px;line-height:1.7;color:var(--color-text);overflow-wrap:anywhere}.bike-scan button:disabled{opacity:.5}.bike-scan button:focus-visible{outline:2px solid var(--color-primary);outline-offset:3px}
</style>
