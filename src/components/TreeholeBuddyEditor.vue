<script setup lang="ts">
import type {TreeholeBuddyDraft} from '../services/treehole';
import {buddyLocalTime,buddyISOTime} from '../domain/treeholeBuddies';
const props=defineProps<{modelValue:TreeholeBuddyDraft;disabled?:boolean}>();
const emit=defineEmits<{'update:modelValue':[value:TreeholeBuddyDraft];remove:[]}>();
function update(part:Partial<TreeholeBuddyDraft>){emit('update:modelValue',{...props.modelValue,...part});}
</script>
<template><section class="th-buddy-editor" aria-label="编辑搭子招募"><header><strong>一起去做点什么</strong><button type="button" :disabled="disabled" @click="$emit('remove')">移除报名</button></header><label>活动时间 · 北京时间<input type="datetime-local" aria-label="搭子活动时间" :value="buddyLocalTime(modelValue.startsAt)" :disabled="disabled" required @input="update({startsAt:buddyISOTime(($event.target as HTMLInputElement).value)})"/></label><label>集合地点<input :value="modelValue.location" aria-label="搭子集合地点" placeholder="例如：东操场入口" maxlength="60" required :disabled="disabled" @input="update({location:($event.target as HTMLInputElement).value})"/></label><label>还招几位搭子<select :value="modelValue.capacity" aria-label="招募人数" :disabled="disabled" @change="update({capacity:Number(($event.target as HTMLSelectElement).value)})"><option v-for="n in 20" :key="n" :value="n">{{n}} 位</option></select></label><small>人数不含你。请选择未来 90 天内的时间，活动开始后停止报名。发布后时间、地点和人数固定；你可以随时结束招募。</small></section></template>
<style scoped>
.th-buddy-editor{padding:14px;background:var(--color-bg);border-radius:12px;margin:12px 0;display:flex;flex-direction:column;gap:12px}header{display:flex;justify-content:space-between;gap:8px;align-items:center}strong{font-size:14px}label{display:flex;flex-direction:column;gap:7px;font-size:13px;min-width:0}input,select{width:100%;min-width:0;max-width:100%;box-sizing:border-box;min-height:44px;background:white;padding:10px;border-radius:8px;font-size:14px}button{min-height:44px;font-size:12px;color:var(--color-primary)}small{color:var(--color-muted);font-size:11px;line-height:1.65}
</style>
