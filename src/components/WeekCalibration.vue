<script setup lang="ts">
import {ref,watch} from 'vue';
import type {Semester} from '../domain/schedule';
import {currentWeek} from '../domain/presentation';
import {firstMondayForWeek} from '../domain/week-calibration';
import {saveWeekCalibration} from '../composables/week-calibration';
const emit=defineEmits<{saved:[]}>();
const props=defineProps<{semester:Semester;now:Date}>();
const week=ref(1),busy=ref(false),message=ref('');
watch(()=>[props.semester.weekStartDate,props.now.toDateString()],()=>{week.value=Math.max(1,Math.min(props.semester.weekCount,currentWeek(props.now,props.semester)))},{immediate:true});
async function save(){try{busy.value=true;message.value='';if(week.value>props.semester.weekCount)throw Error('教学周超过本学期周数');await saveWeekCalibration(props.semester,firstMondayForWeek(props.now,week.value));emit('saved');message.value='已校准，首页和课表同步生效'}catch(e){message.value=(e as Error).message}finally{busy.value=false}}
</script>
<template><details class="week-calibration"><summary>教学周不对？校准本周</summary><form @submit.prevent="save"><p>按学校或老师确认的周次设置。只调整本学期的日期对应关系，不修改课程的单双周和上课周次。</p><label>本周是第 <input v-model.number="week" aria-label="本周教学周" type="number" min="1" :max="semester.weekCount" required/> 周</label><button class="primary" :disabled="busy">保存校准</button><small>第一教学周周一：{{semester.weekStartDate}} · 本机设置</small><p v-if="message" role="status">{{message}}</p></form></details></template>
<style scoped>.week-calibration{font-size:12px;color:var(--color-muted);margin:0 0 8px}.week-calibration summary{min-height:44px;padding:12px 0;cursor:pointer;color:var(--color-primary-strong)}form{border:1px solid var(--color-border);border-radius:16px;padding:14px;background:var(--color-surface);display:flex;align-items:center;gap:12px;flex-wrap:wrap}p{line-height:1.7;margin:0;flex-basis:100%}label{display:flex;align-items:center;gap:8px}input{width:64px;min-height:44px;font:inherit;text-align:center;border:1px solid var(--color-border);border-radius:9px;background:var(--color-surface);color:var(--color-text)}button{min-height:44px}small{display:block;flex-basis:100%}</style>
