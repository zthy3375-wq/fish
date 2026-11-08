<script setup lang="ts">
import {onMounted} from 'vue';
import {Droplets, ChevronRight} from 'lucide-vue-next';
import {initQuzhi,quzhi} from '../composables/quzhi';
import {quzhiMoney} from '../services/quzhi-client';
defineEmits<{open:[]}>();
onMounted(initQuzhi);
</script>
<template>
  <button class="service-row quzhi-entry" @click="$emit('open')">
    <Droplets class="row-icon"/><span class="row-copy"><strong>趣智校园</strong><small>{{quzhi.expired?'登录已失效 · 重新连接':quzhi.connected?'余额与消费 · 充值':'连接账户，查看洗澡余额与充值'}}</small></span>
    <span v-if="quzhi.connected && quzhi.wallet?.total != null" class="quzhi-entry-balance">¥{{quzhiMoney(quzhi.wallet.total)}}<small>上次查询</small></span><ChevronRight :size="18"/>
  </button>
</template>
<style scoped>
.quzhi-entry{width:100%;text-align:left}.quzhi-entry-balance{margin-left:auto;white-space:nowrap;font-size:17px;font-weight:650}.quzhi-entry-balance small{display:block;text-align:right;font-size:10px;font-weight:400;color:var(--color-muted)}
</style>
