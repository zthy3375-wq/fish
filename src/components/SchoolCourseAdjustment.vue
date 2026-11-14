<script setup lang="ts">
import {computed, ref, watch, onBeforeUnmount} from 'vue';
import {ArrowLeft} from 'lucide-vue-next';
import type {Course} from '../domain/academic';
import {periodTimes, type TimeTable} from '../domain/schedule';
import {normalizeCourseTime, type CourseTimeChange} from '../domain/school-course-adjustments';
const props=defineProps<{source:Course;current:Course;table:TimeTable;week:number;saving:boolean;saveError:string}>();
const emit=defineEmits<{save:[weeks:number[],change:CourseTimeChange,allow:boolean];cancel:[]}>();
const draft=ref<CourseTimeChange>({day:props.current.day,room:props.current.room,start:props.current.start,end:props.current.end,
  startPeriod:props.current.startPeriod??null,endPeriod:props.current.endPeriod??null,timeMode:props.current.startPeriod?'period':'custom'});
const week=ref(props.source.weeks.includes(props.week)?props.week:(props.source.weeks.find(w=>w>=props.week)??props.source.weeks[0]));
const range=ref('one'),custom=ref<number[]>([week.value]),confirmed=ref(false),error=ref(''),exitConfirm=ref(false);
const weeks=computed(()=>range.value==='one'?[week.value]:range.value==='future'?props.source.weeks.filter(w=>w>=week.value):range.value==='all'?props.source.weeks:custom.value);
const snapshot=()=>JSON.stringify([draft.value,week.value,range.value,custom.value]);
const initial=snapshot();
const dirty=computed(()=>snapshot()!==initial);
function beforeUnload(e:BeforeUnloadEvent){if(dirty.value){e.preventDefault();e.returnValue=''}}
window.addEventListener('beforeunload',beforeUnload);onBeforeUnmount(()=>window.removeEventListener('beforeunload',beforeUnload));
watch([draft,week,range,custom],()=>{confirmed.value=false;error.value=''}, {deep:true});
function syncTime(){if(draft.value.timeMode==='period'){draft.value.startPeriod??=1;draft.value.endPeriod=Math.max(draft.value.startPeriod,draft.value.endPeriod??draft.value.startPeriod);try{Object.assign(draft.value,periodTimes(props.table,draft.value.startPeriod,draft.value.endPeriod))}catch(e){error.value=(e as Error).message}}}
function toggle(w:number){custom.value=custom.value.includes(w)?custom.value.filter(x=>x!==w):[...custom.value,w].sort((a,b)=>a-b)}
function requestCancel(){if(props.saving)return;if(exitConfirm.value){exitConfirm.value=false;return}if(dirty.value)exitConfirm.value=true;else emit('cancel')}
defineExpose({requestCancel,hasChanges:()=>dirty.value});
function save(){try{if(!weeks.value.length)throw Error('请至少选择一个上课周');emit('save',weeks.value,normalizeCourseTime(draft.value,props.table),confirmed.value)}catch(e){error.value=(e as Error).message}}
</script>
<template>
  <form class="course-editor-page school-adjustment" @submit.prevent="save">
    <header class="editor-header"><button type="button" class="icon-button" aria-label="取消调课" @click="requestCancel"><ArrowLeft :size="21"/></button><div><h2>调整时间/地点</h2><small>{{source.name}}</small></div><button class="primary" :disabled="saving">{{saving?'保存中':'保存'}}</button></header>
    <div class="editor-scroll"><fieldset class="editor-fields" :disabled="saving">
      <p class="muted">只调整你的课表，重新同步后保留。可随时恢复学校安排。退出或重新连接学校账号会清除本机调课记录。</p>
      <section class="editor-basic">
        <h3>生效周次</h3>
        <label class="form-label">调整范围<select v-model="range" aria-label="调整范围"><option value="one">仅某一周</option><option value="future">从某周起</option><option value="all">全部上课周</option><option value="custom">自选周次</option></select></label>
        <label v-if="range==='one'||range==='future'" class="form-label">{{range==='one'?'生效周':'起始周'}}<select v-model.number="week" :aria-label="range==='one'?'生效周':'起始周'"><option v-for="w in source.weeks" :key="w" :value="w">第 {{w}} 周</option></select></label>
        <div v-if="range==='custom'" class="adjustment-weeks" aria-label="自选教学周"><button v-for="w in source.weeks" :key="w" type="button" :aria-pressed="custom.includes(w)" :class="{chosen:custom.includes(w)}" @click="toggle(w)">{{w}}</button></div>
        <p class="muted">第 {{weeks.join('、')||'—'}} 周 · 共 {{weeks.length}} 次</p>
      </section>
      <section class="editor-basic"><h3>新的上课安排</h3>
        <label class="form-label">星期<select v-model.number="draft.day" aria-label="星期"><option v-for="(d,i) in ['一','二','三','四','五','六','日']" :key="i" :value="i+1">星期{{d}}</option></select></label>
        <label class="form-label">时间方式<select v-model="draft.timeMode" aria-label="时间方式" @change="syncTime"><option value="period">按节次</option><option value="custom">自定义时间</option></select></label>
        <div v-if="draft.timeMode==='period'" class="form-grid"><label class="form-label">开始节次<select v-model.number="draft.startPeriod" aria-label="开始节次" @change="syncTime"><option v-for="s in table.slots" :key="s.number" :value="s.number">第 {{s.number}} 节 · {{s.start}}</option></select></label><label class="form-label">结束节次<select v-model.number="draft.endPeriod" aria-label="结束节次" @change="syncTime"><option v-for="s in table.slots.filter(s=>s.number>=(draft.startPeriod??1))" :key="s.number" :value="s.number">第 {{s.number}} 节 · {{s.end}}</option></select></label></div>
        <div v-else class="form-grid"><label class="form-label">开始时间<input v-model="draft.start" type="time" required/></label><label class="form-label">结束时间<input v-model="draft.end" type="time" required/></label></div>
        <label class="form-label">上课教室<input v-model="draft.room" maxlength="150" placeholder="例如：实验楼 305"/></label>
      </section>
      <p class="muted">学校原安排：周{{['一','二','三','四','五','六','日'][source.day-1]}} {{source.start}}–{{source.end}} · {{source.room||'地点未提供'}}</p>
      <p v-if="error||saveError" role="alert" class="error-text">{{error||saveError}}</p>
      <label v-if="saveError.includes('重叠')" class="adjustment-confirm"><input v-model="confirmed" type="checkbox"/>已核对时间冲突，仍然保存</label>
      <div v-if="exitConfirm" class="confirmation"><p>放弃尚未保存的调课？</p><button type="button" class="secondary full" @click="emit('cancel')">放弃修改</button><button type="button" class="text-button" @click="exitConfirm=false">继续编辑</button></div>
    </fieldset></div>
  </form>
</template>
<style scoped>
.school-adjustment h3{margin:4px 0 10px}.adjustment-weeks{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:6px}.adjustment-weeks button{min-height:38px;border:1px solid var(--border);border-radius:9px;background:var(--surface);color:var(--text)}.adjustment-weeks .chosen{background:#6150a3;color:white}.adjustment-confirm{display:flex;align-items:center;gap:8px;font-size:14px}.adjustment-confirm input{width:20px;height:20px}.error-text{color:#b22f43}.editor-header small{display:block;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
</style>
