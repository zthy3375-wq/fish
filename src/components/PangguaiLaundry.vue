<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref,watch} from 'vue';
import {App} from '@capacitor/app';
import type {PluginListenerHandle} from '@capacitor/core';
import {pangguai,pgBusy,quoteLaundry,startLaundry,pollLaundry,cancelLaundry} from '../composables/pangguai';
import {pgAmount,pangguaiError,laundryPhase,laundryRemaining,type PangguaiDevice,type LaundryQuote} from '../services/pangguai-client';
const props=defineProps<{device?:PangguaiDevice}>();
defineEmits<{close:[]}>();
const selection=ref(''),quote=ref<LaundryQuote>(),method=ref(''),cancelConfirm=ref(false),now=ref(Date.now()),localBusy=ref(false);
const order=computed(()=>pangguai.value.laundry);
const terminal=computed(()=>['completed','closed','refunded'].includes(order.value?.phase??''));
const blocked=computed(()=>localBusy.value||pgBusy.value||pangguai.value.expired);
const existing=computed(()=>!!order.value&&!terminal.value);
const quoteExpired=computed(()=>!!quote.value&&now.value>quote.value.expiresAt);
let active=true,disposed=false,timer:ReturnType<typeof setInterval>|undefined,listener:PluginListenerHandle|undefined,lastPoll=0,failures=0;
watch(()=>props.device,()=>{selection.value='';quote.value=undefined;method.value=''});
watch(()=>pangguai.value.phone,()=>{quote.value=undefined;selection.value='';cancelConfirm.value=false});
function time(value?:number){return value?new Date(value).toLocaleString('zh-CN',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',timeZone:'Asia/Shanghai'}):''}
async function preview(existingOrder=false){if(blocked.value)return;localBusy.value=true;quote.value=undefined;try{const result=await quoteLaundry(existingOrder?undefined:selection.value);if(!disposed&&result){quote.value=result;method.value=result.channels.find(c=>c.available)?.id??''}}finally{localBusy.value=false}}
async function pay(){const q=quote.value;if(!q||blocked.value||quoteExpired.value||!method.value)return;localBusy.value=true;quote.value=undefined;try{await startLaundry(q.id,method.value)}finally{localBusy.value=false;lastPoll=Date.now()}}
async function refresh(){if(blocked.value)return;lastPoll=Date.now();const result=await pollLaundry();failures=result?0:failures+1}
async function cancel(){if(!order.value||blocked.value)return;cancelConfirm.value=false;await cancelLaundry(order.value.id)}
function tick(){now.value=Date.now();if(active&&!disposed&&!blocked.value&&existing.value&&order.value?.orderNo&&failures<3&&Date.now()-lastPoll>=15000)void refresh()}
onMounted(async()=>{timer=setInterval(tick,1000);try{const h=await App.addListener('appStateChange',({isActive})=>{active=isActive;if(isActive){failures=0;tick()}});if(disposed)void h.remove();else listener=h}catch{};tick()});
onUnmounted(()=>{disposed=true;clearInterval(timer);void listener?.remove()});
</script>
<template>
 <section v-if="order" class="wash-progress" aria-label="当前洗衣订单">
  <div class="heading"><span class="eyebrow">{{order.deviceName}} · {{order.program}}</span><button class="text-button" :disabled="blocked" @click="refresh">查询状态</button></div>
  <h3 role="status">{{laundryPhase(order.phase)}}</h3>
  <p v-if="order.phase==='running'">{{laundryRemaining(order.expectedEnd,now)||'设备已确认启动，结束时间尚未返回'}}</p>
  <p v-if="order.phase==='completed'">{{order.finishedAt?'完成于 '+time(order.finishedAt):'平台已确认完成'}}，记得取衣。</p>
  <p v-if="order.phase==='paid'">付款已确认，尚未收到设备启动确认，请查看机身提示。</p>
  <p v-if="order.phase==='checking'">正在查询原订单，请勿重复付款。取消了支付宝付款也请先查询状态。</p>
  <p v-if="order.phase==='creating'">未取得完整下单结果，已阻止重复下单。请查看最近消费和胖乖官方订单核对。</p>
  <p class="subtle">应付 ¥{{pgAmount(order.amount)}}<template v-if="order.updatedAt"> · 查询于 {{time(order.updatedAt)}}</template></p>
  <p v-if="order.error" class="feedback" role="alert">{{pangguaiError(order.error)}}，保留上次已确认的进度。</p>
  <div v-if="['pending','checking'].includes(order.phase)" class="actions">
   <button v-if="order.phase==='pending'&&!order.paySent" class="primary" :disabled="blocked" @click="preview(true)">核对并付款</button>
   <button class="secondary" :disabled="blocked" @click="cancelConfirm=true">取消订单</button>
  </div>
  <div v-if="cancelConfirm" class="feedback"><p>确认取消这笔未完成付款的订单？以平台返回结果为准。</p><div class="actions"><button class="secondary" @click="cancelConfirm=false">保留订单</button><button class="primary" :disabled="blocked" @click="cancel">确认取消</button></div></div>
  <details v-if="order.orderNo"><summary>订单编号</summary><p class="order-number">{{order.orderNo}}</p></details>
 </section>
 <section v-if="device" class="wash-device" aria-label="胖乖设备信息">
  <div class="heading"><h3>{{device.name}}</h3><button class="text-button" :disabled="blocked" @click="$emit('close')">收起</button></div>
  <p class="subtle">{{device.operator||'运营商名称未提供'}} · {{device.category==='00'?'洗衣机':device.category==='04'?'饮水机':'淋浴设备'}}</p>
  <p v-if="device.issue" class="feedback">{{device.issue}}</p>
  <template v-if="device.category==='00'">
   <div role="radiogroup" aria-label="选择洗衣程序">
    <label v-for="sku in device.skus" :key="sku.id" class="program" :class="{selected:selection===sku.id}">
     <input v-model="selection" type="radio" name="wash-program" :value="sku.id" :disabled="!sku.available||blocked||existing" @change="quote=undefined"/>
     <span><strong>{{sku.name||'设备程序'}}</strong><small>{{sku.feature||'程序说明未提供'}}{{!sku.available?' · 暂不可选':''}}</small></span>
     <b>{{sku.price==null?'价格待查询':'¥'+pgAmount(sku.price)}}</b>
    </label>
   </div>
   <p class="subtle">放好衣物并关紧机门，费用以确认页为准。</p>
   <button class="primary full" :disabled="blocked||!selection||existing" @click="preview()">{{localBusy?'正在处理…':existing?'请先处理当前订单':'查看费用'}}</button>
  </template>
  <template v-else>
   <div v-for="sku in device.skus" :key="sku.id" class="program"><span><strong>{{sku.name||'设备出水口'}}</strong><small>{{sku.feature}}</small></span><b>{{sku.price==null?'价格未提供':'标价 ¥'+pgAmount(sku.price)}}</b></div>
   <p class="feedback">本版可识别饮水设备并查询账户。扫码开水、暂停和结算尚未接入，请继续按机身和官方端提示使用。</p>
  </template>
 </section>
 <section v-if="quote" class="wash-confirm" role="group" aria-label="确认洗衣费用">
  <div class="heading"><h3>确认洗衣费用</h3><button class="text-button" :disabled="blocked" @click="quote=undefined">取消</button></div>
  <p>{{quote.deviceName}} · {{quote.program}}</p><strong class="amount">¥{{pgAmount(quote.amount)}}</strong>
  <p class="subtle">胖乖账户 {{pangguai.phone}} · 不使用广告优惠</p>
  <label v-for="channel in quote.channels" :key="channel.id" class="channel"><input v-model="method" type="radio" name="wash-payment" :value="channel.id" :disabled="!channel.available||blocked"/><span>{{channel.name}}<small v-if="!channel.available">{{channel.reason||'当前不可用或需开通'}}</small></span></label>
  <p v-if="!quote.channels.some(c=>c.available)" class="feedback">平台未返回可用的余额或支付宝付款方式，请在官方端核对。</p>
  <p v-if="quoteExpired" class="feedback">报价已过期，请关闭后重新查看费用。</p>
  <button class="primary full" :disabled="blocked||!method||quoteExpired" @click="pay">确认支付 ¥{{pgAmount(quote.amount)}} 并洗衣</button>
  <p class="subtle">确认后将创建或支付当前订单。支付宝需在支付界面确认；付款后单独核对设备是否启动。</p>
 </section>
</template>
<style scoped>
.wash-device,.wash-progress,.wash-confirm{margin-top:16px;padding:16px;border:1px solid var(--color-border,#e6e9ef);border-radius:18px;background:var(--color-surface,#fff)}.wash-progress{background:linear-gradient(120deg,#eef7f3,#f5f7fc)}.heading,.program,.channel,.actions{display:flex;align-items:center;gap:10px}.heading{justify-content:space-between}.heading h3{margin:0;font-size:16px}.eyebrow{font-size:12px;overflow-wrap:anywhere}.wash-progress h3{font-size:21px;margin:10px 0}.wash-progress p,.wash-confirm p{font-size:13px;line-height:1.6}.subtle,small{color:var(--color-muted);font-size:12px;line-height:1.6}.program{padding:14px 0;border-bottom:1px solid var(--color-border,#e6e9ef);cursor:pointer}.program span{flex:1;min-width:0}.program strong{font-size:14px}.program small,.channel small{display:block;margin-top:4px}.program b{font-size:14px;white-space:nowrap}.selected strong,.selected b{color:var(--color-primary)}input[type=radio]{accent-color:var(--color-primary);width:18px;height:18px;flex-shrink:0}.feedback{font-size:12px;line-height:1.7;background:var(--color-tint,#f1f3f9);padding:10px 12px;border-radius:10px}.amount{display:block;font-size:34px;margin:12px 0}.channel{min-height:48px;font-size:14px}.wash-confirm .full{margin-top:14px}.actions{flex-wrap:wrap;margin:12px 0}.wash-progress details{font-size:12px;color:var(--color-muted);margin-top:10px}.order-number{overflow-wrap:anywhere}
</style>
