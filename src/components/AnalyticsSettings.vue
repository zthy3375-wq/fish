<script setup lang="ts">
import {onMounted,ref} from 'vue';
import {legacy,deleting,deletionError,readLegacyState,deleteLegacyHistory} from '../composables/analytics';
const confirming=ref(false);
onMounted(readLegacyState);
</script>
<template>
 <div v-if="legacy.hasHistory||legacy.deletePending">
  <button v-if="!confirming" class="text-button" :disabled="deleting" @click="confirming=true">{{legacy.deletePending?'重试删除旧版统计':'删除旧版已上报的匿名统计'}}</button>
  <div v-else><p>删除此设备在旧版中上报的使用记录？</p><button class="text-button" @click="confirming=false">取消</button><button class="secondary" :disabled="deleting" @click="confirming=false;deleteLegacyHistory()">确认删除</button></div>
  <p v-if="deletionError" role="alert">{{deletionError}}</p>
 </div>
</template>
