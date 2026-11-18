<script setup lang="ts">
import {onMounted,computed} from 'vue';
import {Droplets,WashingMachine,Map,Package,ChevronRight,ArrowUpRight} from 'lucide-vue-next';
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
   <button class="life-card life-shower" @click="$emit('open','quzhi-wallet')"><span class="life-brand"><Droplets :size="18"/><strong>趣智校园</strong><ArrowUpRight :size="14"/></span><span class="life-balance-label">洗澡余额</span><b>{{quzhi.connected&&quzhi.wallet?.total!=null?'¥'+quzhiMoney(quzhi.wallet.total):quzhi.connected?'待查询':'连接账户'}}</b><small>{{quzhi.expired?'登录已失效 · 请重新连接':quzhi.connected?'上次查询 · 充值与记录':'洗澡 · 余额与充值'}}</small></button>
   <button class="life-card life-laundry" @click="$emit('open','pangguai-wallet')"><span class="life-brand"><WashingMachine :size="18"/><strong>胖乖生活</strong><ArrowUpRight :size="14"/></span><span class="life-balance-label">饮水余额</span><b>{{pangguai.connected?(water!==null?'¥'+water:'暂未获取'):'连接账户'}}</b><small>{{pangguai.expired?'登录已失效 · 请重新连接':ongoing?'查看当前接水记录':pangguai.connected?'上次查询 · 饮水与洗衣':'饮水 · 洗衣 · 扫码'}}</small></button>
  </div>
  <div class="life-utilities">
   <button class="life-parcel" @click="$emit('open','parcel')"><Package :size="20"/><span><strong>取快递</strong><small>淘宝 · 拼多多出库码</small></span><ChevronRight :size="14"/></button>
   <button class="life-map" @click="$emit('open','campus-map')"><Map :size="20"/><span><strong>校园平面图</strong><small>东区 · 西区</small></span><ChevronRight :size="14"/></button>
  </div>
 </div>
</template>
<style scoped>
.life-wallets{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
.life-card{display:flex;flex-direction:column;align-items:stretch;min-width:0;min-height:122px;padding:14px;text-align:left;border:1px solid var(--color-border);border-radius:18px;color:var(--color-text)}
.life-shower{background:linear-gradient(130deg,var(--color-tint),var(--color-surface))}
.life-laundry{background:linear-gradient(130deg,var(--course-green-bg),var(--color-surface))}
.life-brand{display:flex;align-items:center;gap:7px;color:var(--color-primary)}.life-laundry .life-brand{color:var(--course-green)}
.life-brand strong{flex:1;font-size:15px}.life-balance-label,.life-card small{font-size:11px;line-height:1.45;color:var(--color-muted)}
.life-balance-label{margin-top:10px}.life-card>b{font-size:22px;line-height:1.3;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}.life-card small{margin-top:auto;padding-top:4px}
.life-utilities{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);margin-top:8px;border:1px solid var(--color-divider);border-radius:14px;background:var(--color-surface)}
.life-utilities button{display:flex;align-items:center;gap:9px;min-width:0;min-height:64px;border-radius:0;padding:10px 14px;text-align:left;color:var(--color-text)}
.life-utilities button+button{border-left:1px solid var(--color-divider)}
.life-utilities button>span{flex:1;min-width:0}.life-utilities svg{flex-shrink:0;color:var(--color-primary)}.life-utilities svg:last-child{color:var(--color-muted)}
.life-utilities strong{display:block;font-size:13px;font-weight:600;line-height:1.5}.life-utilities small{display:block;margin-top:2px;font-size:10px;line-height:1.6;color:var(--color-muted)}
.life-card:active,.life-utilities button:active{background:var(--color-highlight);transform:none}.life-card:focus-visible,.life-utilities button:focus-visible{outline-offset:-3px}
@media(max-width:374px){.life-card{padding:11px}.life-brand{gap:5px}.life-utilities button{padding-inline:10px}}
</style>
