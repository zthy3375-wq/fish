<script setup lang="ts">
import {nextTick,ref} from 'vue';
import {badges,honorDate,type Badge} from '../../domain/communityHonors';
const detail=ref<Badge|null>(null),dialog=ref<HTMLDialogElement>();
async function show(badge:Badge){
  detail.value=badge;await nextTick();
  if(dialog.value&&!dialog.value.open)dialog.value.showModal();
}
defineExpose({show});
</script>
<template><Teleport to="body"><dialog v-if="detail" ref="dialog" class="hyt-badge-detail" :aria-label="badges[detail.code].name" @click.self="dialog?.close()" @close="!dialog?.open&&(detail=null)">
 <component :is="badges[detail.code].icon" :size="32" aria-hidden="true"/><h3>{{badges[detail.code].name}}</h3><p>{{badges[detail.code].description}}</p><p>{{badges[detail.code].method}}</p><small>获得日期 · {{honorDate(detail.at)}}</small><form method="dialog"><button>完成</button></form>
</dialog></Teleport></template>
