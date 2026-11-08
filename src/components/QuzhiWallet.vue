<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref} from 'vue';
import {App} from '@capacitor/app';
import type {PluginListenerHandle} from '@capacitor/core';
import {Droplets,RefreshCw,ArrowUpRight,WalletCards} from 'lucide-vue-next';
import {quzhi,quzhiBusy,quzhiReady,quzhiError,initQuzhi,refreshQuzhi,connectQuzhi,disconnectQuzhi,rechargeQuzhi} from '../composables/quzhi';
import {quzhiSupported,quzhiMonth,quzhiMoney,quzhiIssue} from '../services/quzhi-client';

const month=ref(quzhiMonth()), confirmation=ref<'recharge'|'logout'|''>(''), returned=ref(false);
let listener:PluginListenerHandle|undefined, disposed=false, awaitingReturn=false;
let resumeTimer:ReturnType<typeof setTimeout>|undefined;
const supported=quzhiSupported();
const valid=computed(()=>quzhi.value.connected&&!quzhi.value.expired);
const billsMatch=computed(()=>month.value===quzhi.value.billsMonth);
const blocked=computed(()=>quzhiBusy.value||!quzhiReady.value);
function timestamp(value?:number){return value?new Date(value).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}):'尚未查询'}
async function recharge(){
  confirmation.value='';returned.value=false;awaitingReturn=true;
  if(!await rechargeQuzhi())awaitingReturn=false;
}
async function resume(){
  if(disposed||!awaitingReturn)return;
  if(quzhiBusy.value){clearTimeout(resumeTimer);resumeTimer=setTimeout(()=>void resume(),200);return}
  awaitingReturn=false;returned.value=true;
  await refreshQuzhi(month.value);
}
async function logout(){confirmation.value='';returned.value=false;awaitingReturn=false;await disconnectQuzhi()}
onMounted(async()=>{
  await initQuzhi();
  if(disposed)return;
  if(supported){
    try{const handle=await App.addListener('appStateChange',({isActive})=>{if(isActive)void resume()});if(disposed)void handle.remove();else listener=handle}catch{/* Manual refresh remains available. */}
    if(!disposed)await refreshQuzhi(month.value);
  }
});
onUnmounted(()=>{disposed=true;clearTimeout(resumeTimer);void listener?.remove()});
</script>
<template>
<div class="quzhi-wallet">
  <span class="micro-label"><Droplets :size="17"/>校园生活</span>
  <h2>趣智校园</h2><p class="muted">洗澡余额、消费账单与充值</p>
  <p v-if="!supported" class="quzhi-notice">请安装 Android 客户端后连接趣智校园。</p>
  <p v-if="quzhiError" class="quzhi-notice" role="alert">{{quzhiError}}</p>
  <template v-if="!quzhi.connected">
    <section class="quzhi-empty"><WalletCards :size="32"/><h3>把洗澡钱包放在这里</h3><p>连接已有趣智账户，直接查余额和账单。充值可直达支付宝中的趣智充值页。</p><button class="primary full" :disabled="!supported||blocked" @click="connectQuzhi(month)">{{quzhiBusy?'正在连接…':'连接趣智校园'}}</button></section>
    <p class="quzhi-note">手机号、密码或验证码在原生登录窗口填写。会话加密留在本机，不保存密码，不加载趣智 App 的广告页面。</p>
  </template>
  <template v-else>
    <div class="quzhi-identity"><span><strong>{{quzhi.school||'学校信息尚未取得'}}</strong><small>{{quzhi.phone}}</small></span><button class="icon-button" aria-label="刷新趣智余额与账单" :disabled="blocked||!valid" @click="refreshQuzhi(month)"><RefreshCw :size="18" :class="{'quzhi-spin':quzhiBusy}"/></button></div>
    <div v-if="quzhi.expired" class="quzhi-notice">登录已失效，下方为上次查询结果。<button class="text-button" :disabled="blocked" @click="connectQuzhi(month)">重新连接</button></div>
    <section class="quzhi-balance" aria-label="趣智钱包余额">
      <span>账户总余额</span><strong class="quzhi-amount"><small>¥</small>{{quzhiMoney(quzhi.wallet?.total)}}</strong>
      <div class="quzhi-breakdown"><span>充值余额 <b>¥{{quzhiMoney(quzhi.wallet?.cash)}}</b></span><span>赠送余额 <b>¥{{quzhiMoney(quzhi.wallet?.gift)}}</b></span></div>
      <small class="quzhi-updated">{{quzhiBusy?'正在更新…':'查询于 '+timestamp(quzhi.walletUpdatedAt)}}</small>
      <button class="primary full" :disabled="blocked||!valid" @click="confirmation='recharge'"><ArrowUpRight :size="17"/>充值 · 支付宝</button>
    </section>
    <p v-if="quzhi.issues?.wallet" class="quzhi-notice" role="status">余额未更新：{{quzhiIssue(quzhi.issues.wallet)}}</p>
    <p v-if="returned" class="quzhi-notice" role="status">已从充值页面返回，请核对下方余额；实际到账以平台余额和支付订单为准。</p>
    <div v-if="confirmation==='recharge'" class="quzhi-confirm" role="group" aria-label="确认充值账户">
      <strong>前往支付宝的趣智充值页</strong><p>当前连接：{{quzhi.phone}} · {{quzhi.school||'学校待核对'}}。支付宝可能登录了另一个账户，请在付款前核对学校与手机号。</p>
      <div><button class="secondary" @click="confirmation=''">取消</button><button class="primary" :disabled="blocked" @click="recharge">打开充值页</button></div>
    </div>
    <section class="quzhi-bills" aria-label="趣智消费账单">
      <div class="quzhi-bills-heading"><h3>消费账单</h3><label>月份<input v-model="month" type="month" min="2020-01" :max="quzhiMonth()" :disabled="blocked||!valid" @change="refreshQuzhi(month)"/></label></div>
      <p v-if="quzhi.issues?.bills" class="quzhi-notice" role="status">账单未更新：{{quzhiIssue(quzhi.issues.bills)}}</p>
      <p v-if="quzhi.billsMonth&&!billsMatch" class="quzhi-note">{{month}} 尚未取得，下方保留 {{quzhi.billsMonth}} 的账单。</p>
      <p v-if="!quzhi.billsUpdatedAt" class="quzhi-note">{{quzhiBusy?'正在查询消费记录…':'尚未取得消费记录，点击右上角刷新。'}}</p>
      <p v-else-if="!quzhi.bills?.length" class="quzhi-note">{{quzhi.billsMonth}} 暂无消费记录。</p>
      <ul v-else><li v-for="(bill,index) in quzhi.bills" :key="bill.id+'-'+index"><div><strong>{{bill.description}}</strong><small>{{bill.date||'时间未提供'}}</small></div><b>¥{{quzhiMoney(bill.amount)}}</b></li></ul>
      <p v-if="quzhi.billsTruncated" class="quzhi-note">本页仅展示平台返回的前 200 条，未显示完整月份。</p>
      <p v-if="quzhi.billsUpdatedAt" class="quzhi-note">账单查询于 {{timestamp(quzhi.billsUpdatedAt)}} · 当前展示消费记录</p>
    </section>
    <details class="quzhi-account"><summary>账户管理</summary><p class="quzhi-note">退出会清除此账户在本机保存的余额、账单和会话，保留教务与个人待办。</p><button class="text-button danger" :disabled="blocked" @click="confirmation='logout'">退出趣智账户</button></details>
    <div v-if="confirmation==='logout'" class="quzhi-confirm" role="group" aria-label="退出趣智账户"><strong>退出并清除趣智缓存？</strong><div><button class="secondary" @click="confirmation=''">取消</button><button class="primary" :disabled="blocked" @click="logout">确认退出</button></div></div>
  </template>
</div>
</template>
<style scoped>
.quzhi-wallet{padding-top:8px}.quzhi-wallet h2{margin:8px 0}.quzhi-wallet h3{font-size:16px;margin:0}.quzhi-note,.quzhi-notice{font-size:12px;line-height:1.65;color:var(--color-muted);overflow-wrap:anywhere}.quzhi-notice{padding:10px 12px;background:var(--color-tint,#f4f3f9);border-radius:12px}.quzhi-empty{text-align:center;padding:24px 8px}.quzhi-empty>svg{color:var(--color-primary,#6753b5);margin-bottom:12px}.quzhi-empty p{font-size:14px;line-height:1.7;color:var(--color-muted)}.quzhi-identity{display:flex;align-items:center;justify-content:space-between;margin:20px 0 12px;gap:12px}.quzhi-identity strong{font-size:14px}.quzhi-identity small{display:block;color:var(--color-muted);font-size:12px;margin-top:4px}.quzhi-balance{background:linear-gradient(125deg,var(--color-tint,#f3f0fc),var(--color-surface,#fff));border:1px solid var(--color-line,#e6e2ed);border-radius:20px;padding:18px}.quzhi-balance>span{font-size:13px;color:var(--color-muted)}.quzhi-amount{display:block;font-size:40px;font-weight:700;letter-spacing:-1px;line-height:1.5;overflow-wrap:anywhere}.quzhi-amount small{font-size:21px;margin-right:6px}.quzhi-breakdown{display:flex;flex-wrap:wrap;gap:8px 18px;font-size:12px;color:var(--color-muted)}.quzhi-breakdown b{font-weight:500}.quzhi-updated{display:block;margin:10px 0 16px;color:var(--color-muted);font-size:11px}.quzhi-bills{margin-top:24px}.quzhi-bills-heading{display:flex;align-items:center;justify-content:space-between;gap:8px}.quzhi-bills-heading label{display:flex;align-items:center;gap:4px;font-size:11px;color:var(--color-muted)}.quzhi-bills-heading input{font:inherit;font-size:12px;max-width:138px;padding:7px;border:1px solid var(--color-line,#e6e2ed);border-radius:8px;background:var(--color-surface,#fff);color:inherit}.quzhi-bills ul{list-style:none;padding:0;margin:12px 0}.quzhi-bills li{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:13px 0;border-bottom:1px solid var(--color-line,#e6e2ed)}.quzhi-bills li div{min-width:0}.quzhi-bills li strong{font-size:13px;font-weight:500;overflow-wrap:anywhere}.quzhi-bills li small{display:block;font-size:11px;color:var(--color-muted);margin-top:4px}.quzhi-bills li>b{font-size:14px;white-space:nowrap}.quzhi-confirm{border:1px solid var(--color-line,#e6e2ed);padding:14px;border-radius:14px;margin-top:14px}.quzhi-confirm strong{font-size:14px}.quzhi-confirm p{font-size:12px;line-height:1.7;color:var(--color-muted)}.quzhi-confirm>div{display:flex;gap:10px;justify-content:flex-end;margin-top:12px}.quzhi-account{margin-top:20px;font-size:13px}.quzhi-account summary{padding:10px 0;cursor:pointer}.quzhi-spin{animation:quzhi-spin 1s linear infinite}@keyframes quzhi-spin{to{transform:rotate(360deg)}}@media(prefers-reduced-motion:reduce){.quzhi-spin{animation:none}}
</style>
