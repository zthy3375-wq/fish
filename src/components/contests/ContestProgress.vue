<script setup lang="ts">
import {computed} from 'vue';
import {contestStage,type Contest} from '../../services/contests';
const props=defineProps<{contest:Contest;now:number}>();
const step=computed(()=>{const p=contestStage(props.contest,props.now);return ['draft','upcoming'].includes(p)?-1:['submitting','waiting'].includes(p)?0:p==='voting'?1:2;});
</script>
<template><ol v-if="contest.state!=='cancelled'" class="ct-progress" aria-label="赛事阶段"><li v-for="(label,i) in ['投稿','投票','公布']" :key="label" :class="{current:i===step,done:i<step}" :aria-current="i===step?'step':undefined"><i aria-hidden="true"/><span>{{label}}</span></li></ol></template>
<style scoped>.ct-progress{display:flex;list-style:none;padding:0;margin:17px 0 12px;gap:10px}.ct-progress li{display:flex;align-items:center;gap:6px;flex:1;font-size:11px;color:var(--color-muted)}.ct-progress li::after{content:'';height:1px;background:var(--color-divider);flex:1}.ct-progress li:last-child{flex:none}.ct-progress li:last-child::after{display:none}.ct-progress i{width:6px;height:6px;border:1px solid var(--color-border);border-radius:50%}.ct-progress .current{color:var(--color-primary);font-weight:600}.ct-progress .current i,.ct-progress .done i{background:var(--color-primary);border-color:var(--color-primary)}</style>
