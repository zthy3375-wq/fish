<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref,watch} from 'vue';
import {KeyRound} from 'lucide-vue-next';
import {quzhi,quzhiBusy,quzhiReady,loadQuzhiBathCode} from '../composables/quzhi';
import type {QuzhiBathCode} from '../services/quzhi-client';
const props=withDefaults(defineProps<{active?:boolean}>(),{active:true});
const code=ref<QuzhiBathCode>(),pending=ref(false),error=ref('');
const valid=computed(()=>quzhiReady.value&&quzhi.value.connected&&!quzhi.value.expired);
let generation=0,disposed=false;
function conceal(){generation++;code.value=undefined;error.value='';pending.value=false}
function hidden(){if(document.visibilityState!=='visible')conceal()}
watch([()=>props.active,()=>quzhi.value.connected,()=>quzhi.value.expired,()=>quzhi.value.phone],conceal);
async function reveal(){
 if(pending.value||quzhiBusy.value||!valid.value||!props.active)return;
 conceal();const request=++generation;pending.value=true;
 try{
  const result=await loadQuzhiBathCode();
  if(disposed||request!==generation||!props.active||document.visibilityState!=='visible'||!valid.value)return;
  if(result.phone!==quzhi.value.phone||typeof result.enabled!=='boolean'||!Number.isFinite(result.queriedAt)||
   (result.code!==null&&!/^[0-9]{8}$/.test(result.code))||(result.enabled&&!result.code))throw Error('洗澡码信息不完整，请重新查询');
  code.value=result;
 }catch(e){if(!disposed&&request===generation)error.value=(e as Error).message}
 finally{if(request===generation)pending.value=false}
}
const timestamp=computed(()=>code.value?new Date(code.value.queriedAt).toLocaleTimeString('zh-CN',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit'}):'');
onMounted(()=>document.addEventListener('visibilitychange',hidden));
onUnmounted(()=>{disposed=true;conceal();document.removeEventListener('visibilitychange',hidden)});
defineExpose({conceal});
</script>
<template>
 <section class="quzhi-bath-code" aria-label="趣智洗澡码">
  <div class="bath-heading"><span><KeyRound :size="18"/><strong>洗澡码</strong></span><button v-if="code" class="text-button" @click="conceal">收起</button></div>
  <template v-if="code">
   <div v-if="code.enabled&&code.code" class="bath-digits" aria-label="当前洗澡码">{{code.code}}</div>
   <p v-if="code.enabled" class="bath-state">已开启 · 在支持使用码的设备上输入</p>
   <p v-else class="bath-state">洗澡码尚未开启，请在趣智校园开启后刷新。</p>
   <small>查询于 {{timestamp}}</small>
  </template>
  <p v-else class="bath-state">查看当前账户的设备使用码</p>
  <p v-if="error" class="bath-error" role="alert">{{error}}</p>
  <button class="secondary full" :disabled="pending||quzhiBusy||!valid" @click="reveal">{{pending?'正在查询…':code?'刷新洗澡码':'查看洗澡码'}}</button>
 </section>
</template>
<style scoped>
.quzhi-bath-code{margin-top:14px;padding:16px;border:1px solid var(--color-border);border-radius:18px;background:var(--color-surface)}.bath-heading,.bath-heading>span{display:flex;align-items:center;gap:8px}.bath-heading{justify-content:space-between}.bath-heading svg{color:var(--color-primary)}.bath-heading strong{font-size:14px}.bath-heading button{font-size:12px;min-height:32px}.bath-digits{margin:16px 0 8px;text-align:center;font-size:32px;font-weight:650;letter-spacing:4px;font-variant-numeric:tabular-nums;color:var(--color-text);line-height:1.4}.quzhi-bath-code .bath-state{font-size:12px;line-height:1.6;margin:10px 0;color:var(--color-muted)}.quzhi-bath-code small{font-size:11px;color:var(--color-muted)}.quzhi-bath-code .full{margin-top:10px;min-height:42px}.bath-error{font-size:12px;color:var(--color-danger);line-height:1.6}
</style>
