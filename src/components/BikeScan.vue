<script setup lang="ts">
import {onMounted,onBeforeUnmount,ref} from 'vue';
import {Bike,ScanLine,Copy,ArrowUpRight} from 'lucide-vue-next';
import {scanBike,actOnBike,clearBike,bikeSupported,bikeName,bikeStatusMessage,bikeErrorMessage,type ScannedBike,type BikeMode} from '../services/bike-scan';
const supported=bikeSupported(),bike=ref<ScannedBike>(),busy=ref(false),message=ref('');
let disposed=false;
async function scan(){
 if(!supported||busy.value)return;busy.value=true;bike.value=undefined;message.value='';
 try{const result=await scanBike();if(!disposed)bike.value=result}
 catch(e){if(!disposed)message.value=bikeErrorMessage(e)}finally{if(!disposed)busy.value=false}
}
async function act(mode:BikeMode|'copy'){
 if(busy.value||!bike.value)return;busy.value=true;message.value='';
 try{const status=await actOnBike(bike.value,mode);if(!disposed)message.value=bikeStatusMessage(status)}
 catch(e){if(!disposed)message.value=bikeErrorMessage(e)}finally{if(!disposed)busy.value=false}
}
onMounted(()=>{void scan()});
onBeforeUnmount(()=>{disposed=true;bike.value=undefined;void clearBike()});
</script>
<template>
 <section class="bike-scan" aria-label="扫码骑车" :aria-busy="busy">
  <header><Bike :size="24"/><div><h2>扫码骑车</h2><p>哈啰 · 美团单车</p></div></header>
  <template v-if="supported">
   <div v-if="bike" class="bike-result"><span>已识别 {{bikeName(bike)}}</span><strong>{{bike.number}}</strong><small>请与车身编号核对</small></div>
   <p v-else class="bike-intro">对准车身二维码，自动识别品牌和车辆编号。扫码页支持手电筒和相册识别。</p>
   <button v-if="bike" class="primary full" :disabled="busy" @click="act('use')"><ArrowUpRight :size="18"/>前往用车</button>
   <button class="bike-rescan" :disabled="busy" @click="scan"><ScanLine :size="18"/>{{bike?'重新扫码':'扫描车身二维码'}}</button>
   <div v-if="bike" class="bike-fallbacks"><button :disabled="busy" @click="act('scanner')">尝试打开官方扫码</button><button :disabled="busy" @click="act('copy')"><Copy :size="14"/>复制车辆编号</button><button :disabled="busy" @click="act('web')">系统打开车码网页</button></div>
   <p v-if="bike" class="bike-note">{{bike.provider==='hello'?'优先打开支付宝中的哈啰入口，登录、开锁和结算在官方端完成。':'车码链接可能进入美团下载页；若未带入车辆，请打开官方扫码或输入车号。'}}进入官方端后请核对车号及收费规则，开锁和还车结果以官方端为准。</p>
   <p v-if="busy||message" role="status" aria-live="polite" class="bike-message">{{busy?'正在处理…':message}}</p>
  </template>
  <p v-else class="bike-intro">请在 Android 客户端中使用扫码骑车。</p>
 </section>
</template>
<style scoped>
.bike-scan{padding:22px 18px 18px}.bike-scan header{display:flex;align-items:center;gap:12px;color:var(--color-primary);margin:0 32px 18px 0}.bike-scan h2{font-size:21px;color:var(--color-text);margin:0}.bike-scan header p{font-size:12px;color:var(--color-muted);margin:5px 0 0}.bike-result{display:grid;gap:9px;padding:18px;margin-bottom:16px;background:var(--color-highlight);border:1px solid var(--color-border);border-radius:18px}.bike-result span{font-size:13px;color:var(--color-primary)}.bike-result strong{font-size:29px;letter-spacing:1px;font-variant-numeric:tabular-nums;color:var(--color-text)}.bike-result small{font-size:11px;color:var(--color-muted)}.bike-intro,.bike-note{font-size:12px;line-height:1.8;color:var(--color-muted);margin:12px 0}.bike-rescan{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:46px;margin-top:10px;border:1px solid var(--color-border);border-radius:12px;color:var(--color-primary);background:var(--color-surface)}.bike-fallbacks{display:flex;flex-wrap:wrap;gap:0 14px;margin-top:12px}.bike-fallbacks button{display:flex;align-items:center;gap:5px;font-size:12px;min-height:44px;color:var(--color-primary)}.bike-message{font-size:12px;line-height:1.7;color:var(--color-text);overflow-wrap:anywhere}.bike-scan button:disabled{opacity:.5}.bike-scan button:focus-visible{outline:2px solid var(--color-primary);outline-offset:3px}
</style>
