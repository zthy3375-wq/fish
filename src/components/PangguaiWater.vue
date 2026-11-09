<script setup lang="ts">
import {computed,nextTick,onMounted,onUnmounted,ref,watch} from 'vue';
import {App} from '@capacitor/app';
import type {PluginListenerHandle} from '@capacitor/core';
import {pangguai,pgBusy,prepareWater,startWater,pollWater,endWater,confirmPhysicalWaterEnd,openWaterPaymentSetup} from '../composables/pangguai';
import {pgAmount,pangguaiError,waterPhase,type PangguaiDevice,type WaterQuote} from '../services/pangguai-client';
const props=defineProps<{device?:PangguaiDevice}>();defineEmits<{close:[]}>();
const selection=ref(''),quote=ref<WaterQuote>(),localBusy=ref(false),starting=ref(false),clock=ref(Date.now()),panel=ref<HTMLElement>(),confirmPanel=ref<HTMLElement>(),devicePanel=ref<HTMLElement>();
const session=computed(()=>pangguai.value.water),terminal=computed(()=>['settled','ended_zero','closed_unknown'].includes(session.value?.phase??''));
const activeSession=computed(()=>!!session.value&&!terminal.value),blocked=computed(()=>localBusy.value||pgBusy.value||pangguai.value.expired),expired=computed(()=>!!quote.value&&clock.value>quote.value.expiresAt);
let disposed=false,active=true,awaitingSetup=false,setupAway=false,lastPoll=0,failures=0,timer:ReturnType<typeof setInterval>|undefined,listener:PluginListenerHandle|undefined;
watch(()=>session.value?.id,()=>{failures=0;lastPoll=0});
watch(()=>props.device,async d=>{selection.value=d?.skus.length===1&&d.skus[0]?.available?d.skus[0].id:'';quote.value=undefined;if(d){await nextTick();devicePanel.value?.scrollIntoView?.({block:'nearest'})}},{immediate:true});
function updated(value:number){return new Date(value).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',second:'2-digit',timeZone:'Asia/Shanghai'})}
const elapsed=computed(()=>{if(!session.value?.startedAt)return '';const sec=Math.max(0,Math.floor(((session.value.endedAt??clock.value)-session.value.startedAt)/1000));return `${Math.floor(sec/60)}分${String(sec%60).padStart(2,'0')}秒`});
async function preview(){if(blocked.value||!selection.value)return;localBusy.value=true;quote.value=undefined;try{const result=await prepareWater(selection.value);if(!disposed&&result){quote.value=result;await nextTick();confirmPanel.value?.scrollIntoView?.({block:'nearest',behavior:'smooth'})}}finally{localBusy.value=false}}
async function begin(){const q=quote.value;if(!q||blocked.value||expired.value||!q.canStart)return;localBusy.value=true;starting.value=true;quote.value=undefined;try{await startWater(q.id);await nextTick();panel.value?.scrollIntoView?.({block:'nearest',behavior:'smooth'})}finally{localBusy.value=false;starting.value=false;lastPoll=Date.now()}}
async function refresh(){if(blocked.value)return;lastPoll=Date.now();const result=await pollWater();failures=result?0:failures+1}
async function finish(){const s=session.value;if(!s||blocked.value)return;localBusy.value=true;try{await endWater(s.id)}finally{localBusy.value=false;lastPoll=Date.now()}}
async function physical(){if(session.value&&!blocked.value)await confirmPhysicalWaterEnd(session.value.id)}
async function setup(){if(blocked.value)return;awaitingSetup=true;setupAway=false;const result=await openWaterPaymentSetup();if(!result?.opened)awaitingSetup=false}
function tick(){clock.value=Date.now();if(disposed||!active||blocked.value)return;if(awaitingSetup&&setupAway){awaitingSetup=false;void preview();return}if(activeSession.value&&session.value?.orderNo&&failures<3&&Date.now()-lastPoll>=3000)void refresh()}
onMounted(async()=>{timer=setInterval(tick,1000);try{const h=await App.addListener('appStateChange',({isActive})=>{active=isActive;if(!isActive&&awaitingSetup)setupAway=true;if(isActive){failures=0;tick()}});if(disposed)void h.remove();else listener=h}catch{};tick()});
onUnmounted(()=>{disposed=true;clearInterval(timer);void listener?.remove()});
</script>
<template>
 <div class="water-flow">
 <section v-if="session&&!terminal" ref="panel" class="water-progress" aria-label="当前接水记录">
  <div class="heading"><span>{{session.deviceName}} · {{session.outlet}}</span><button class="text-button" :disabled="blocked" @click="refresh">查询状态</button></div>
  <h3 aria-live="polite">{{session.error==='WATER_OWNERSHIP'?'接水状态待核对':waterPhase(session.phase)}}</h3>
  <p v-if="elapsed&&session.error!=='WATER_OWNERSHIP'" class="elapsed">{{elapsed}} <small>本地参考计时</small></p>
  <p v-if="session.phase==='starting'">正在核对本次用水，请查看机身提示。尚未确认启动时不要重复扫码开水。</p>
  <template v-if="['using','ending'].includes(session.phase)&&session.error!=='WATER_OWNERSHIP'">
   <p>先将杯子放好。未出水时请看机身提示；暂停请按机身「暂停」。</p>
   <button v-if="session.remoteEnd&&!session.endSent&&session.error!=='WATER_OWNERSHIP'" class="primary full" :disabled="blocked" @click="finish">结束接水并结算</button>
   <p v-else class="instruction">{{session.endSent?'已请求结束，尚待设备确认；仍在出水请按机身「结算」。':'接完后请按机身「结算」，这里会继续核对结束和账单。'}}</p>
  </template>
  <p v-if="session.phase==='settling'||session.phase==='ended'">本次用水会话已结束，正在处理后付账单。不会再次开水或重复发送扣费请求。</p>
  <p v-if="session.endBasis==='session_closed'" class="instruction">平台已不再返回本次用水会话。如机身仍在出水，请立即按机身「结算」。</p>
  <p v-if="session.phase==='settled'" class="amount">本次实付 ¥{{pgAmount(session.amount)}}</p>
  <p v-if="session.phase==='ended_zero'">设备回报本次用量为零，未追加后付请求。费用仍以平台消费记录为准。</p>
  <p v-if="session.error" class="feedback" role="alert">{{pangguaiError(session.error)}}</p>
  <button v-if="session.error==='WATER_OWNERSHIP'" class="secondary full" :disabled="blocked" @click="refresh">核对旧记录并恢复扫码</button>
  <button v-if="activeSession&&!session.orderNo" class="secondary full" :disabled="blocked" @click="physical">已按机身结算，核对设备</button>
  <p class="muted">{{session.paymentName}} · 查询于 {{updated(session.updatedAt)}}</p>
  <details v-if="session.orderNo"><summary>本次订单</summary><p>{{session.orderNo}}</p></details>
 </section>
 <section v-if="device&&!quote&&(!activeSession||device.id!==session?.deviceId)" ref="devicePanel" class="water-device" aria-label="选择接水口">
  <div class="heading"><h3>{{device.name}}</h3><button class="text-button" @click="$emit('close')">收起</button></div>
  <p class="muted">{{device.operator||'饮水设备'}} · 请核对热水／常温水出水口</p>
  <p v-if="device.issue" class="feedback">{{device.issue}}</p>
  <label v-for="sku in device.skus" :key="sku.id" class="outlet"><input v-model="selection" type="radio" name="water-outlet" :value="sku.id" :disabled="blocked||activeSession||!sku.available"/><span><strong>{{sku.name||'接水选项'}}</strong><small>{{sku.feature||'计费说明以机身标识为准'}}{{!sku.available?' · 暂不可用':''}}</small></span></label>
  <button class="primary full" :disabled="blocked||activeSession||!selection" @click="preview">{{starting?'正在启动…':localBusy?'正在查询…':activeSession?'请先处理当前接水记录':'接水'}}</button>
 </section>
 <section v-if="quote" ref="confirmPanel" class="water-confirm" role="group" aria-label="确认接水与扣费方式">
  <div class="heading"><h3>确认接水</h3><button class="text-button" :disabled="blocked" @click="quote=undefined">取消</button></div>
  <p><strong>{{quote.deviceName}} · {{quote.outlet}}</strong></p><p>{{quote.feature||'按设备实际用量计费，具体计费规则请核对机身标识。'}}</p>
  <p v-if="quote.price!=null" class="muted">平台标价 {{pgAmount(quote.price)}}，不是本次总价；计费单位以设备说明为准。</p>
  <p>扣费方式：{{quote.paymentName}}</p><p class="muted">胖乖账户 {{pangguai.phone}}。确认后启动本次用水，结束后按实际使用结算；本次不使用广告优惠。</p>
  <p class="instruction">{{quote.remoteEnd?'支持在此结束接水；也可使用机身结算按钮。':'接完请按机身「结算」，应用会继续查询结束状态和账单。'}}</p>
  <p v-if="!quote.canStart" class="feedback">{{quote.reason}}</p>
  <div v-if="!quote.canStart" class="actions"><button class="secondary" :disabled="blocked" @click="setup">到支付宝胖乖处理</button><button class="secondary" :disabled="blocked" @click="preview">重新检查</button></div>
  <p v-if="expired" class="feedback">确认信息已过期，请取消后重新查询。</p>
  <button class="primary full" :disabled="blocked||expired||!quote.canStart" @click="begin">确认开始接水</button>
 </section>
 <details v-if="session&&terminal" :key="session.id" class="water-history" aria-label="上次接水记录">
  <summary><span><strong>{{waterPhase(session.phase)}}</strong><small>{{session.deviceName}} · {{session.outlet}}</small></span><b v-if="session.phase==='settled'">¥{{pgAmount(session.amount)}}</b><span class="history-toggle">详情</span></summary>
  <div class="history-body">
   <p v-if="elapsed">{{elapsed}} · 本地参考计时</p>
   <p v-if="session.phase==='ended_zero'">设备回报本次用量为零，费用仍以平台消费记录为准。</p>
   <p v-if="session.phase==='closed_unknown'">{{session.endBasis==='order_replaced'?'设备已切换订单，旧记录已移出接水状态，可重新扫码。费用以最近消费或官方账单为准。':'设备已空闲，可重新扫码。本次账单请在最近消费或官方端核对。'}}</p>
   <p v-if="session.error" role="alert">{{pangguaiError(session.error)}}</p>
   <p>{{session.paymentName}} · 查询于 {{updated(session.updatedAt)}}</p>
   <p v-if="session.orderNo">订单 {{session.orderNo}}</p>
   <button class="text-button" :disabled="blocked" @click="refresh">查询状态</button>
  </div>
 </details>
 </div>
</template>
<style scoped>
.water-progress,.water-device,.water-confirm{margin-top:16px;padding:16px;border:1px solid var(--color-border,#e6e9ef);border-radius:18px;background:var(--color-surface,#fff)}.water-progress{background:linear-gradient(120deg,#edf7fc,#f4f7fb)}.heading,.outlet,.actions{display:flex;align-items:center;gap:10px}.heading{justify-content:space-between;font-size:12px}.heading h3{font-size:16px;margin:0}.water-progress h3{font-size:21px;margin:12px 0}.water-progress p,.water-confirm p{font-size:13px;line-height:1.7}.water-progress .elapsed{font-size:25px;font-weight:600}.elapsed small{font-size:11px;font-weight:400}.muted,small{font-size:12px!important;color:var(--color-muted);line-height:1.6}.outlet{padding:15px 0;border-bottom:1px solid var(--color-border);font-size:14px}.outlet input{width:18px;height:18px;accent-color:var(--color-primary);flex-shrink:0}.outlet small{display:block;margin-top:5px}.full{margin-top:14px}.instruction,.feedback{padding:10px 12px;border-radius:10px;background:var(--color-tint,#edf2f8)}.feedback{font-size:12px}.actions{flex-wrap:wrap}.water-progress .amount{font-size:25px;font-weight:650}.water-progress details{font-size:12px;color:var(--color-muted);margin-top:10px}.water-progress details p{overflow-wrap:anywhere}
.water-device,.water-confirm{scroll-margin-block:12px}.water-history{margin-top:12px;border:1px solid var(--color-border,#e6e9ef);border-radius:14px;background:var(--color-surface,#fff)}.water-history summary{display:flex;align-items:center;gap:10px;padding:12px;cursor:pointer;list-style:none}.water-history summary::-webkit-details-marker{display:none}.water-history summary>span:first-child{flex:1;min-width:0}.water-history strong{display:block;font-size:13px;font-weight:600}.water-history small{display:block;margin-top:3px;overflow-wrap:anywhere}.water-history b{font-size:17px;white-space:nowrap}.history-toggle{font-size:12px;color:var(--color-primary);flex-shrink:0}.history-toggle::after{content:'⌄';margin-left:4px}.water-history[open] .history-toggle::after{content:'⌃'}.history-body{padding:0 12px 12px;border-top:1px solid var(--color-border)}.history-body p{font-size:12px;overflow-wrap:anywhere}
</style>
