<script setup lang="ts">
import {onMounted,computed} from 'vue';
import {Droplets,WashingMachine,Map,Package,ChevronRight,ArrowUpRight} from 'lucide-vue-next';
import {initPangguai,pangguai} from '../composables/pangguai';
import {initQuzhi,quzhi} from '../composables/quzhi';
import {quzhiMoney} from '../services/quzhi-client';
import {drinkingWaterTicket,drinkingWaterAmount} from '../domain/drinking-water-wallet';
defineEmits<{open:[page:string]}>();
const water=computed(()=>drinkingWaterAmount(drinkingWaterTicket(pangguai.value.tickets??[])?.balance));
onMounted(()=>{void initQuzhi();void initPangguai()});
</script>
<template>
 <div class="life-services">
  <div class="life-wallets">
   <button class="life-card life-shower" @click="$emit('open','quzhi-wallet')"><span class="life-brand"><Droplets :size="18"/><strong>趣智校园</strong><ArrowUpRight :size="14"/></span><span class="life-balance-label">洗澡余额</span><b>{{quzhi.connected&&quzhi.wallet?.total!=null?'¥'+quzhiMoney(quzhi.wallet.total):quzhi.connected?'待查询':'连接账户'}}</b><small>{{quzhi.expired?'登录已失效 · 请重新连接':quzhi.connected?'上次查询 · 充值与记录':'洗澡 · 余额与充值'}}</small></button>
   <button class="life-card life-laundry" @click="$emit('open','pangguai-wallet')"><span class="life-brand"><WashingMachine :size="18"/><strong>胖乖生活</strong><ArrowUpRight :size="14"/></span><span class="life-balance-label">饮水余额</span><b>{{pangguai.connected?(water!==null?'¥'+water:'暂未获取'):'连接账户'}}</b><small>{{pangguai.expired?'登录已失效 · 请重新连接':pangguai.connected?'上次查询 · 饮水与洗衣':'饮水 · 洗衣 · 扫码'}}</small></button>
  </div>
  <div class="life-utilities"><button class="life-parcel" @click="$emit('open','parcel')"><span class="parcel-icon"><Package :size="23"/></span><span><strong>取快递</strong><small>淘宝 · 拼多多出库码</small></span><ChevronRight :size="16"/></button><button class="life-map" @click="$emit('open','campus-map')"><Map :size="20"/><span><strong>校园地图</strong><small>找地点</small></span><ChevronRight :size="15"/></button></div>
 </div>
</template>
<style scoped>
.life-services{margin:0}.life-wallets{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.life-card{position:relative;text-align:left;padding:14px!important;border:1px solid #dfd5f1;border-radius:20px;min-width:0;color:var(--color-text);min-height:135px!important}.life-shower{background:linear-gradient(125deg,#eee5ff,#f8f4ff)}.life-laundry{background:linear-gradient(125deg,#e4f2eb,#f5faf7);border-color:#d9e8df}.life-card .life-brand{position:static;display:flex;gap:7px;align-items:center;color:#58399b;font-size:13px}.life-laundry .life-brand{color:#39634f}.life-brand strong{font-size:14px;flex:1;line-height:1.5}.life-brand svg:last-child{opacity:.7}.life-card .life-balance-label{position:static;display:block;margin-top:12px;font-size:10px;color:#726480}.life-laundry .life-balance-label{color:#5a7063}.life-card>b{display:block;margin-top:2px!important;font-size:25px!important;font-weight:700;line-height:1.4;font-variant-numeric:tabular-nums;overflow-wrap:anywhere;letter-spacing:-.5px}.life-card>small{display:block!important;font-size:9px;color:var(--color-muted);line-height:1.5;margin-top:4px}.life-utilities{display:grid;grid-template-columns:minmax(0,1.6fr) minmax(0,1fr);gap:10px;margin-top:10px}.life-utilities button{display:flex;align-items:center;gap:10px;min-height:65px;padding:11px 12px;border:1px solid var(--color-border);border-radius:18px;background:var(--color-surface);color:var(--color-text);text-align:left;min-width:0}.life-utilities .life-parcel{background:#fff5e9;border-color:#efe2ce}.life-utilities button>span:not(.parcel-icon){flex:1;min-width:0}.parcel-icon{width:33px;height:36px;display:grid;place-items:center;color:#91623b}.life-utilities strong{font-size:14px;display:block}.life-utilities small{font-size:9px;color:var(--color-muted);display:block;margin-top:3px;line-height:1.5}.life-map>svg:first-child{color:var(--color-primary)}.life-utilities svg{flex-shrink:0}
:global([data-theme=dark]) .life-card{background:var(--color-highlight);border-color:var(--color-border)}:global([data-theme=dark]) .life-card .life-brand{color:var(--color-primary)}:global([data-theme=dark]) .life-card .life-balance-label{color:var(--color-muted)}:global([data-theme=dark]) .life-utilities .life-parcel{background:#393024;border-color:#564737}
@media(max-width:374px){.life-card{padding:12px!important}.life-brand strong{font-size:13px}.life-brand{gap:5px!important}.life-utilities button{gap:6px;padding:9px}.life-utilities strong{font-size:13px}.life-utilities small{font-size:9px}.parcel-icon{width:28px}.life-card>b{font-size:23px!important}}
</style>
