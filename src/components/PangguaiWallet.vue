<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref} from 'vue';
import {App} from '@capacitor/app';
import type {PluginListenerHandle} from '@capacitor/core';
import {ScanLine,RefreshCw,Wallet,ArrowUpRight,ChevronRight} from 'lucide-vue-next';
import {pangguai,pgBusy,pgReady,pgError,initPangguai,connectPangguai,refreshPangguai,disconnectPangguai,scanPangguai,rechargePangguai} from '../composables/pangguai';
import {pgAmount,pangguaiError,pangguaiSupported,type PangguaiDevice,type PangguaiTicket} from '../services/pangguai-client';
import {openPangguaiOfficial} from '../services/pangguai-official';
const supported=pangguaiSupported(),device=ref<PangguaiDevice>(),confirm=ref<PangguaiTicket>(),logout=ref(false),tab=ref<'wallet'|'orders'>('wallet'),notice=ref('');
const valid=computed(()=>pangguai.value.connected&&!pangguai.value.expired),blocked=computed(()=>pgBusy.value||!pgReady.value);
let listener:PluginListenerHandle|undefined,disposed=false,awaitingReturn=false,active=true;
let retry:ReturnType<typeof setTimeout>|undefined;
function updated(value?:number){return value?new Date(value).toLocaleString('zh-CN',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',timeZone:'Asia/Shanghai'}):'尚未更新'}
async function scan(){const result=await scanPangguai();if(!disposed&&result)device.value=result}
async function recharge(){const target=confirm.value;if(!target)return;confirm.value=undefined;awaitingReturn=true;const result=await rechargePangguai(target.id);if(!result?.opened)awaitingReturn=false}
async function resume(){clearTimeout(retry);if(disposed||!active)return;if(awaitingReturn&&pgBusy.value){retry=setTimeout(()=>void resume(),250);return}if(awaitingReturn){awaitingReturn=false;notice.value='已返回，请核对商户余额与支付订单';await refreshPangguai()}else await refreshPangguai(true)}
async function signOut(){logout.value=false;await disconnectPangguai();if(!pangguai.value.connected){device.value=undefined;notice.value='';awaitingReturn=false}}
onMounted(async()=>{await initPangguai();if(disposed)return;await refreshPangguai(true);if(disposed)return;try{const handle=await App.addListener('appStateChange',({isActive})=>{active=isActive;if(isActive)void resume();else clearTimeout(retry)});if(disposed)void handle.remove();else listener=handle}catch{}});
onUnmounted(()=>{disposed=true;clearTimeout(retry);void listener?.remove()});
</script>
<template>
 <div class="pg-wallet">
  <div class="pg-title"><span class="micro-label">洗衣 · 饮水</span><h2>胖乖生活</h2><p class="muted">余额、设备和消费记录，一处查看</p></div>
  <p v-if="!supported" class="pg-status">请在 Android 客户端连接胖乖账户。</p>
  <p v-if="pgError" class="pg-status" role="alert">{{pgError}}</p>
  <section v-if="!pangguai.connected" class="pg-welcome"><Wallet :size="34"/><h3>连接你的胖乖钱包</h3><p>短信登录后，余额直接显示在这里。</p><button class="primary full" :disabled="!supported||blocked" @click="connectPangguai">{{pgBusy?'正在连接…':'连接胖乖生活'}}</button></section>
  <template v-else>
   <div class="pg-identity"><span>{{pangguai.phone}}</span><button class="icon-button" aria-label="刷新胖乖余额与记录" :disabled="blocked||!valid" @click="refreshPangguai()"><RefreshCw :size="18"/></button></div>
   <p v-if="pangguai.expired" class="pg-status">登录已失效，下方保留上次结果。<button class="text-button" :disabled="blocked" @click="connectPangguai">重新连接</button></p>
   <section class="pg-balance"><span>普通账户余额 · 元</span><strong><small>¥</small>{{pgAmount(pangguai.balance)}}</strong><small>查询于 {{updated(pangguai.walletUpdatedAt)}}</small><button class="primary full" :disabled="blocked||!valid" @click="scan"><ScanLine :size="19"/>扫码识别设备</button></section>
   <p v-if="pangguai.issues?.wallet" class="pg-status">余额未更新：{{pangguaiError(pangguai.issues.wallet)}}</p>
   <div class="pg-tabs" role="tablist" aria-label="胖乖钱包内容"><button role="tab" :aria-selected="tab==='wallet'" @click="tab='wallet'">商户钱包</button><button role="tab" :aria-selected="tab==='orders'" @click="tab='orders'">最近消费</button></div>
   <section v-if="tab==='wallet'">
    <p class="pg-hint">小票按商户单独使用，单位为点，不与普通余额相加。</p>
    <p v-if="pangguai.issues?.tickets" class="pg-status">商户钱包未更新：{{pangguaiError(pangguai.issues.tickets)}}</p>
    <p v-if="!pangguai.tickets?.length" class="pg-hint">{{pangguai.ticketsUpdatedAt?'账户暂无商户小票，使用设备后可再次刷新。':'商户钱包尚未取得，点击右上角刷新。'}}</p>
    <article v-for="ticket in pangguai.tickets" :key="ticket.id" class="pg-merchant"><div><h3>{{ticket.name}}</h3><strong>{{pgAmount(ticket.balance)}} <small>点</small></strong><p>本金 {{pgAmount(ticket.principal)}} · 赠送 {{pgAmount(ticket.gift)}}</p></div><button class="secondary" :disabled="blocked||!valid" @click="confirm=ticket">充值<ArrowUpRight :size="15"/></button></article>
    <p v-if="pangguai.ticketsUpdatedAt" class="pg-hint">商户钱包更新于 {{updated(pangguai.ticketsUpdatedAt)}}</p>
   </section>
   <section v-else>
    <p v-if="pangguai.issues?.orders" class="pg-status">消费记录未更新：{{pangguaiError(pangguai.issues.orders)}}</p>
    <p v-if="!pangguai.orders?.length" class="pg-hint">{{pangguai.ordersUpdatedAt?'暂无消费记录':'消费记录尚未取得'}}</p>
    <article v-for="order in pangguai.orders" :key="order.id" class="pg-order"><div><strong>{{order.name||'胖乖消费'}}</strong><small>{{order.time}} · {{order.status}}</small></div><b>¥{{pgAmount(order.amount)}}</b></article>
    <p v-if="pangguai.ordersUpdatedAt" class="pg-hint">最近 20 条 · 金额为现金实付 · {{updated(pangguai.ordersUpdatedAt)}}</p>
   </section>
   <section v-if="device" class="pg-device" aria-label="胖乖设备信息"><div class="pg-heading"><h3>{{device.name}}</h3><button class="text-button" @click="device=undefined">收起</button></div><p>{{device.operator||'运营商名称未提供'}} · {{device.category==='00'?'洗衣设备':device.category==='04'?'饮水设备':'淋浴设备'}}</p><p v-if="device.issue" class="pg-status">{{device.issue}}</p><div v-for="sku in device.skus" :key="sku.id" class="pg-program"><span><strong>{{sku.name||'设备程序'}}</strong><small>{{sku.feature}}</small></span><span>{{sku.price==null?'价格未提供':'标价 ¥'+pgAmount(sku.price)}}<small>{{sku.available?'可选择':'可用性待核对'}}</small></span></div><p class="pg-hint">设备信息已读取。此版本扫码不下单、不扣款；启动设备请在胖乖官方端完成。</p></section>
   <div v-if="confirm" class="pg-confirm" role="group" aria-label="确认胖乖充值账户"><h3>为 {{confirm.name}} 充值</h3><p>当前账户 {{pangguai.phone}}。将打开此商户的支付宝充值页，请核对支付宝手机号和金额后付款。</p><div><button class="secondary" @click="confirm=undefined">取消</button><button class="primary" :disabled="blocked" @click="recharge">前往付款</button></div></div>
   <p v-if="notice" class="pg-status" role="status">{{notice}}</p>
   <details class="pg-management"><summary>账户与帮助</summary><button class="text-button danger" :disabled="blocked" @click="logout=true">退出胖乖账户</button><p class="pg-hint">退出清除本机胖乖会话与缓存，保留教务、趣智和个人待办。</p><button class="text-button" @click="openPangguaiOfficial('wallet')">打开官方页面<ChevronRight :size="14"/></button></details>
   <div v-if="logout" class="pg-confirm"><h3>退出并清除胖乖缓存？</h3><div><button class="secondary" @click="logout=false">取消</button><button class="primary" :disabled="blocked" @click="signOut">确认退出</button></div></div>
  </template>
  <button v-if="!pangguai.connected" class="text-button pg-help" @click="openPangguaiOfficial('login')">登录遇到问题？打开官方验证页面</button>
 </div>
</template>
<style scoped>
.pg-wallet{padding:8px 0 20px}.pg-title h2{margin:7px 0}.pg-title>p{font-size:13px}.pg-status{padding:10px 12px;background:var(--color-tint,#f1f3f9);border-radius:12px;font-size:12px;line-height:1.7}.pg-welcome{text-align:center;padding:30px 4px}.pg-welcome svg{color:var(--color-primary)}.pg-welcome p,.pg-hint{color:var(--color-muted);font-size:12px;line-height:1.6}.pg-identity,.pg-heading{display:flex;align-items:center;justify-content:space-between;gap:12px}.pg-identity{margin:16px 0 8px;font-size:13px}.pg-balance{padding:20px;border-radius:22px;background:linear-gradient(120deg,#e9f6f2,#f5f8fd);border:1px solid #dcebe6}.pg-balance>span,.pg-balance>small{font-size:12px;color:#526d66}.pg-balance>strong{display:block;font-size:42px;line-height:1.7;overflow-wrap:anywhere}.pg-balance strong small{font-size:22px;margin-right:5px}.pg-balance .primary{margin-top:18px}.pg-tabs{display:flex;gap:6px;background:var(--color-bg);padding:4px;border-radius:12px;margin:22px 0 12px}.pg-tabs button{flex:1;min-height:40px;border:0;background:transparent;border-radius:9px;color:var(--color-muted);font-size:13px}.pg-tabs [aria-selected=true]{background:var(--color-surface,#fff);color:var(--color-text);box-shadow:0 2px 6px #0000000a;font-weight:650}.pg-merchant,.pg-order,.pg-program{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:15px 0;border-bottom:1px solid var(--color-border,#e6e9ef)}.pg-merchant>div,.pg-order>div,.pg-program>span:first-child{min-width:0}.pg-merchant h3,.pg-device h3,.pg-confirm h3{font-size:14px;margin:0 0 7px;overflow-wrap:anywhere}.pg-merchant strong{font-size:24px}.pg-merchant strong small{font-size:12px;font-weight:400}.pg-merchant p{font-size:11px;color:var(--color-muted);margin:6px 0 0}.pg-merchant button{flex-shrink:0;display:flex;align-items:center;gap:4px;min-height:40px}.pg-order strong,.pg-program strong{font-size:13px;overflow-wrap:anywhere}.pg-order small,.pg-program small{display:block;font-size:11px;color:var(--color-muted);margin-top:5px}.pg-order b{font-size:14px;white-space:nowrap}.pg-device,.pg-confirm{padding:16px;border:1px solid var(--color-border,#e6e9ef);border-radius:16px;margin:18px 0}.pg-device>p,.pg-confirm p{font-size:12px;color:var(--color-muted);line-height:1.6}.pg-program>span:last-child{text-align:right;font-size:13px;flex-shrink:0}.pg-confirm>div{display:flex;justify-content:flex-end;gap:10px;margin-top:16px}.pg-management{margin-top:24px;font-size:13px}.pg-management summary{padding:10px 0}.pg-help{margin:auto;font-size:12px}
</style>
