<script setup lang="ts">
import {onMounted} from 'vue';
import {Droplets,WashingMachine,Map,Package,ChevronRight} from 'lucide-vue-next';
import {initPangguai,pangguai} from '../composables/pangguai';
import {initQuzhi,quzhi} from '../composables/quzhi';
import {quzhiMoney} from '../services/quzhi-client';
import {pgAmount} from '../services/pangguai-client';
defineEmits<{open:[page:string]}>();
onMounted(()=>{void initQuzhi();void initPangguai()});
</script>
<template>
 <div class="life-services">
  <div class="life-wallets"><button class="life-card life-shower" @click="$emit('open','quzhi-wallet')"><Droplets :size="21"/><strong>趣智校园</strong><span>洗澡</span><b>{{quzhi.connected&&quzhi.wallet?.total!=null?'¥'+quzhiMoney(quzhi.wallet.total):'连接账户'}}</b><small>{{quzhi.expired?'登录已失效':quzhi.connected?'上次查询 · 余额与充值':'余额与充值'}}</small></button><button class="life-card life-laundry" @click="$emit('open','pangguai-wallet')"><WashingMachine :size="21"/><strong>胖乖生活</strong><span>洗衣 · 饮水</span><b>{{pangguai.connected&&pangguai.balance!=null?'¥'+pgAmount(pangguai.balance):'连接账户'}}</b><small>{{pangguai.expired?'登录已失效':pangguai.connected?'普通余额 · 上次查询':'钱包 · 扫码 · 消费'}}</small></button></div>
  <div class="life-utilities"><button @click="$emit('open','campus-map')"><Map :size="19"/><span><strong>校园地图</strong><small>找地点 · 收藏 · 导航</small></span><ChevronRight :size="16"/></button><button @click="$emit('open','parcel')"><Package :size="19"/><span><strong>取快递</strong><small>淘宝 · 拼多多出库码</small></span><ChevronRight :size="16"/></button></div>
 </div>
</template>
<style scoped>
.life-services{margin-bottom:12px}.life-wallets{display:grid;grid-template-columns:1fr 1fr;gap:10px}.life-card{position:relative;text-align:left;padding:16px;border:1px solid #e4e9ef;border-radius:18px;min-width:0;color:var(--color-text);min-height:157px}.life-shower{background:linear-gradient(135deg,#eef0ff,#fafaff)}.life-laundry{background:linear-gradient(135deg,#eaf5f1,#f8fcfa)}.life-card>svg{margin-bottom:8px;color:#577b75}.life-shower>svg{color:#7075ad}.life-card strong{display:block;font-size:14px}.life-card>span{position:absolute;right:14px;top:19px;font-size:10px;color:var(--color-muted)}.life-card>b{display:block;margin-top:12px;font-size:23px;font-weight:650;line-height:1.4;overflow-wrap:anywhere}.life-card>small{display:block;margin-top:3px;font-size:10px;color:var(--color-muted)}.life-utilities{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px}.life-utilities button{display:flex;align-items:center;gap:8px;min-height:64px;padding:11px 10px;border:1px solid var(--color-border,#e6e9ef);border-radius:14px;background:var(--color-surface,#fff);color:var(--color-text);text-align:left;min-width:0}.life-utilities span{flex:1;min-width:0}.life-utilities strong{font-size:12px;display:block}.life-utilities small{font-size:9px;color:var(--color-muted);display:block;margin-top:4px}.life-utilities svg{flex-shrink:0}
</style>
