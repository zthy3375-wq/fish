<script setup lang="ts">
import {onMounted,computed} from 'vue';
import {Droplets,WashingMachine,Map,Package,ChevronRight} from 'lucide-vue-next';
import {initPangguai,pangguai} from '../composables/pangguai';
import {initQuzhi,quzhi} from '../composables/quzhi';
import {quzhiMoney} from '../services/quzhi-client';
import {drinkingWaterTicket,drinkingWaterAmount} from '../domain/drinking-water-wallet';
defineEmits<{open:[page:string]}>();
const water=computed(()=>drinkingWaterAmount(drinkingWaterTicket(pangguai.value.tickets??[])?.balance));
const ongoing=computed(()=>{const w=pangguai.value.water;return !!w&&!['settled','ended_zero','closed_unknown','archived_unverified'].includes(w.phase)});
onMounted(()=>{void initQuzhi();void initPangguai()});
</script>
<template>
 <div class="life-services">
  <div class="life-wallets">
   <button class="life-card life-shower" @click="$emit('open','quzhi-wallet')">
    <span class="life-service-icon"><Droplets :size="22"/></span>
    <span class="life-service-copy"><strong>趣智校园</strong><small>{{quzhi.expired?'登录已失效 · 请重新连接':'洗澡 · 余额与充值'}}</small></span>
    <span class="life-wallet-value"><b :class="{'is-disconnected':!quzhi.connected}">{{quzhi.connected&&quzhi.wallet?.total!=null?'¥'+quzhiMoney(quzhi.wallet.total):quzhi.connected?'待查询':'连接账户'}}</b><span class="life-balance-label">{{quzhi.connected?'洗澡余额 · 上次查询':'去连接'}}</span></span>
    <ChevronRight class="life-row-arrow" :size="16"/>
   </button>
   <button class="life-card life-laundry" @click="$emit('open','pangguai-wallet')">
    <span class="life-service-icon"><WashingMachine :size="22"/></span>
    <span class="life-service-copy"><strong>胖乖生活</strong><small>{{pangguai.expired?'登录已失效 · 请重新连接':ongoing?'查看当前接水记录':'饮水 · 洗衣 · 扫码'}}</small></span>
    <span class="life-wallet-value"><b :class="{'is-disconnected':!pangguai.connected}">{{pangguai.connected?(water!==null?'¥'+water:'暂未获取'):'连接账户'}}</b><span class="life-balance-label">{{pangguai.connected?'饮水余额 · 上次查询':'去连接'}}</span></span>
    <ChevronRight class="life-row-arrow" :size="16"/>
   </button>
  </div>
  <div class="life-utilities">
   <button class="life-parcel" @click="$emit('open','parcel')"><Package :size="20"/><span><strong>取快递</strong><small>淘宝 · 拼多多出库码</small></span><ChevronRight :size="14"/></button>
   <button class="life-map" @click="$emit('open','campus-map')"><Map :size="20"/><span><strong>校园平面图</strong><small>东区 · 西区</small></span><ChevronRight :size="14"/></button>
  </div>
 </div>
</template>
<style scoped>
.life-services{background:var(--color-surface);border:1px solid var(--color-border);border-radius:16px;overflow:hidden}
.life-wallets{display:grid}
.life-card{display:flex;align-items:center;gap:12px;min-width:0;min-height:72px;border-radius:0;padding:12px 14px;text-align:left;color:var(--color-text);background:transparent}
.life-card+ .life-card{border-top:1px solid var(--color-divider)}
.life-service-icon{display:grid;place-items:center;flex:0 0 40px;height:40px;border-radius:12px;background:var(--color-tint);color:var(--color-primary)}
.life-laundry .life-service-icon{background:var(--course-green-bg);color:var(--course-green)}
.life-service-copy{flex:1;min-width:0}.life-service-copy strong{display:block;font-size:15px;font-weight:650;line-height:1.5}.life-service-copy small{display:block;color:var(--color-muted);font-size:11px;line-height:1.6;margin-top:2px;overflow-wrap:anywhere}
.life-wallet-value{flex:0 1 auto;text-align:right;min-width:0}.life-wallet-value b{display:block;font-size:19px;line-height:1.3;font-weight:650;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}.life-wallet-value .is-disconnected{font-size:13px;color:var(--color-primary)}
.life-balance-label{display:block;color:var(--color-muted);font-size:10px;line-height:1.6;margin-top:3px}.life-row-arrow{color:var(--color-muted);flex-shrink:0}
.life-utilities{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);border-top:1px solid var(--color-divider)}
.life-utilities button{display:flex;align-items:center;gap:9px;min-width:0;min-height:64px;border-radius:0;padding:10px 14px;text-align:left;color:var(--color-text)}
.life-utilities button+button{border-left:1px solid var(--color-divider)}
.life-utilities button>span{flex:1;min-width:0}.life-utilities svg{flex-shrink:0;color:var(--color-primary)}.life-utilities svg:last-child{color:var(--color-muted)}
.life-utilities strong{display:block;font-size:13px;font-weight:600;line-height:1.5}.life-utilities small{display:block;margin-top:2px;font-size:10px;line-height:1.6;color:var(--color-muted)}
.life-card:active,.life-utilities button:active{background:var(--color-highlight);transform:none}.life-card:focus-visible,.life-utilities button:focus-visible{outline-offset:-3px}
@media(max-width:374px){.life-card{padding-inline:12px;gap:9px}.life-service-icon{flex-basis:36px;height:36px}.life-wallet-value b{font-size:18px}.life-utilities button{padding-inline:12px;gap:7px}.life-utilities button>svg:first-child{width:18px}.life-balance-label{font-size:10px}}
@media(min-width:540px){.life-card{gap:16px;padding-inline:18px}.life-service-copy small{font-size:12px}.life-utilities button{padding-inline:18px}}
</style>
