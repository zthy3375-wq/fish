<script setup lang="ts">
import DailyTaskRow from './DailyTaskRow.vue';
import {learningCache,initLearning,syncLearning,saveLearningPlan} from '../composables/learning';
import {computed,onMounted,onUnmounted,ref} from 'vue';
import {Plus,ChevronLeft,ChevronRight,Check,Search,ArrowUp} from 'lucide-vue-next';
import {academicCache,schoolTerm,schoolCourses} from '../composables/handan-academic';
import {schedule} from '../composables/schedule';
import {agendaView,taskView,tasksReady,tasksBusy,taskError,allTasks,initTasks,reloadTasks,changeTasks,cancelLearningSchedule} from '../composables/tasks';
import {beijingDay,validDay,shiftDay,buildAgenda,type CampusTask,type AgendaEvent,type CourseSeries} from '../domain/agenda';
import {selectTasks,taskSummary,createTask,replanTask,type SmartList} from '../domain/tasks';
import {flatten,uid} from '../domain/schedule';
import {taskStore} from '../services/task-store';
import type {Course} from '../domain/academic';
const emit=defineEmits<{course:[course:Course];navigate:[section:string];edit:[task?:CampusTask,day?:string]}>();
const now=ref(new Date()),message=ref(''),error=ref(''),filters=ref(false);
const smartLists:[SmartList,string][]=[['today','今天'],['planned','接下来'],['inbox','未安排']];
const priorities=['无优先级','低优先级','中优先级','高优先级'];
const selectedDay=computed(()=>validDay(agendaView.date)?agendaView.date:beijingDay(now.value));
const series=computed<CourseSeries[]>(()=>{const all:CourseSeries[]=[];const school=schoolTerm.value?.data;if(school)all.push({semester:school.semester,courses:schoolCourses.value,source:'school'});for(const semester of schedule.value.semesters){if(semester.id.startsWith('school-page-'))continue;const table=schedule.value.timeTables.find(t=>t.id===semester.timeTableId);all.push({semester,courses:flatten(schedule.value.courses,semester.id,table),source:'personal'})}return all});
const courses=computed(()=>[...new Set([...series.value.flatMap(s=>s.courses.map(c=>c.name)),...learningCache.value.courses.map(c=>c.name)].filter(Boolean))].sort((a,b)=>a.localeCompare(b,'zh-CN')));
const courseOptions=computed(()=>[...new Set([...courses.value,...allTasks.value.map(t=>t.course).filter(Boolean)])]);
const tasks=computed(()=>selectTasks(allTasks.value,taskView,now.value));
const summary=computed(()=>taskSummary(allTasks.value,now.value));
const groups=computed(()=>{
 const result=new Map<string,{key:string;name:string;tasks:CampusTask[]}>();
 for(const task of tasks.value){
  const learning=task.source==='chaoxing';
  const identity=learning?task.externalId?.split('/').slice(0,2).join('/'):'';
  const key=learning?'cx:'+identity:taskView.group?'personal:'+task.course:'personal';
  const name=learning?task.course:taskView.group?(task.course||'其他个人任务'):'';
  const group=result.get(key)||{key,name,tasks:[]};group.tasks.push(task);result.set(key,group);
 }
 return [...result.values()];
});
const agenda=computed(()=>buildAgenda(series.value,academicCache.value.exams.data||[],allTasks.value,selectedDay.value,agendaView.range,now.value));
const timelineEvents=computed(()=>agenda.value.events.filter(e=>!e.completed&&(agendaView.filter==='all'||e.kind===agendaView.filter)&&(!taskView.source||taskView.source==='all'||(taskView.source==='chaoxing'?e.taskId?.startsWith('cx:'):e.kind==='task'&&!e.taskId?.startsWith('cx:')))));
const days=computed(()=>Array.from({length:agendaView.range},(_,i)=>{const date=shiftDay(selectedDay.value,i);return {date,events:timelineEvents.value.filter(e=>e.date===date)}}));
const nextEvent=computed(()=>timelineEvents.value.find(e=>e.startAt!==null&&e.startAt>=+now.value));
const count=(view:SmartList)=>selectTasks(allTasks.value,{...taskView,view,search:'',course:'',priority:-1},now.value).length;
function report(e:unknown){error.value=e instanceof Error?e.message:'操作未完成，请重试'}
async function quickAdd(){if(!taskView.quick.trim()||tasksBusy.value)return;error.value='';try{const task=createTask(taskView.quick.trim(),uid(),now.value);if(taskView.view==='today')task.plannedDay=beijingDay(now.value);if(taskView.course)task.course=taskView.course;await changeTasks(()=>taskStore.upsert(task));taskView.quick='';if(taskView.view!=='today')taskView.view='inbox';message.value='任务已添加';}catch(e){report(e)}}
function edit(task?:CampusTask){emit('edit',task,!task?(taskView.mode==='timeline'?selectedDay.value:taskView.view==='today'?beijingDay(now.value):undefined):undefined)}
async function complete(task:CampusTask){if(task.source==='chaoxing')return;try{await changeTasks(()=>taskStore.complete(task.id,!task.completed));message.value=task.completed?'已恢复任务':'已完成，可在「已完成」中撤销'}catch(e){report(e)}}
async function cancelPlan(task:CampusTask){try{await cancelLearningSchedule(task);message.value='已取消安排，原作业保留在学习通'}catch(e){report(e)}}
async function replan(task:CampusTask,offset:number){try{if(task.source==='chaoxing'){await saveLearningPlan(replanTask({...task},shiftDay(beijingDay(now.value),offset),now.value));message.value='计划已调整，最终截止时间保持原样';return;}await changeTasks(()=>taskStore.change(s=>{const t=s.tasks.find(t=>t.id===task.id);if(!t)throw Error('任务已不存在');replanTask(t,shiftDay(beijingDay(now.value),offset),now.value)}));message.value='计划已调整，最终截止时间保持原样'}catch(e){report(e)}}
function selectEvent(e:AgendaEvent){if(e.taskId){const task=allTasks.value.find(t=>t.id===e.taskId);if(task){edit(task)}}else if(e.course)emit('course',e.course);else emit('navigate','exams')}
function moveDay(n:number){agendaView.date=shiftDay(selectedDay.value,n)}
function today(){agendaView.date=beijingDay(now.value)}
function week(){const day=new Date(selectedDay.value+'T12:00:00Z').getUTCDay()||7;agendaView.date=shiftDay(selectedDay.value,1-day);agendaView.range=7}
function dayLabel(day:string){return `${day===beijingDay(now.value)?'今天 · ':''}${day.slice(5).replace('-','月')}日 ${new Intl.DateTimeFormat('zh-CN',{weekday:'short',timeZone:'Asia/Shanghai'}).format(new Date(day+'T12:00:00+08:00'))}`}
function nowIndex(events:AgendaEvent[]){const i=events.findIndex(e=>e.startAt!==null&&e.startAt>+now.value);return i<0?events.length:i}
function eventState(e:AgendaEvent){if(e.startAt===null)return e.source==='个人计划'?'当天安排':'时间待核对';if(e.kind==='task'&&e.source.includes('截止'))return e.startAt<+now.value?'已逾期':'截止';return (e.endAt??e.startAt)<+now.value?'已结束':e.startAt<=+now.value?'进行中':'未开始'}
const undoTask=ref<CampusTask|null>(null);
async function toggleTask(task:CampusTask){await complete(task);if(!taskError.value&&!error.value)undoTask.value=task}
async function undo(){const t=undoTask.value;if(!t)return;const live=allTasks.value.find(x=>x.id===t.id);if(live)await complete(live);undoTask.value=null}
const timer=setInterval(()=>now.value=new Date(),30000);
onMounted(()=>{void initTasks().catch(()=>{});void initLearning().then(()=>syncLearning()).catch(()=>{})});onUnmounted(()=>{clearInterval(timer)});
</script>
<template>
<section class="campus-agenda task-center" aria-label="统一日程">
 <div class="daily-task-toolbar"><div class="task-mode" role="tablist" aria-label="待办与日程"><button role="tab" :aria-selected="taskView.mode==='list'" @click="taskView.mode='list'">任务清单</button><button role="tab" :aria-selected="taskView.mode==='timeline'" @click="taskView.mode='timeline'">日程</button></div><button class="icon-button" aria-label="添加待办" :disabled="!tasksReady" @click="edit()"><Plus :size="21"/></button></div>
 <p v-if="taskError||error" role="alert" class="task-message danger">{{error||taskError}} <button v-if="!tasksReady" @click="reloadTasks">重新读取</button></p><p v-if="message" role="status" class="task-message">{{message}} <button v-if="undoTask" class="text-button" @click="undo">撤销</button></p>
 <template v-if="taskView.mode==='list'">
  <div class="smart-lists" aria-label="智能清单"><button v-for="[id,label] in smartLists" :key="id" :aria-pressed="taskView.view===id" @click="taskView.view=id">{{label}}<small>{{count(id)}}</small></button></div>
  <div class="task-search"><Search :size="16"/><input v-model="taskView.search" type="search" aria-label="搜索任务" placeholder="搜索任务、课程或备注"/><button class="text-button" :aria-expanded="filters" @click="filters=!filters">筛选</button></div>
  <div v-if="filters" class="task-filters"><select v-model="taskView.source" aria-label="任务来源"><option value="all">全部来源</option><option value="personal">个人任务</option><option value="chaoxing">学习通</option></select><select v-model="taskView.view" aria-label="任务范围"><option value="today">今天</option><option value="planned">接下来</option><option value="inbox">未安排</option><option value="due">即将截止</option><option value="completed">已完成</option></select><select v-model="taskView.course" aria-label="按课程筛选"><option value="">所有课程</option><option v-for="course in courseOptions" :key="course">{{course}}</option></select><select v-model="taskView.sort" aria-label="任务排序"><option value="smart">智能排序</option><option value="deadline">截止时间</option><option value="priority">重要程度</option><option value="title">标题</option></select><select v-model.number="taskView.priority" aria-label="优先级筛选"><option :value="-1">全部优先级</option><option v-for="(p,i) in priorities" :key="i" :value="i">{{p}}</option></select><label><input v-model="taskView.group" type="checkbox"/>个人任务也按课程分组</label></div>
  <div v-if="taskView.search||taskView.course||['due','completed'].includes(taskView.view)" class="task-list-heading"><h3>{{taskView.view==='completed'?'已完成':taskView.view==='due'?'即将截止':smartLists.find(([id])=>id===taskView.view)?.[1]}}</h3><span>{{tasks.length}} 项</span></div>
  <section v-for="group in groups" :key="group.key" class="task-group"><h4 v-if="group.name">{{group.name}} <small>{{group.tasks.length}} 项</small></h4>
   <DailyTaskRow v-for="task in group.tasks" :key="task.id" :task="task" :now="now" :busy="tasksBusy" @open="edit" @complete="toggleTask" @replan="replan" @cancel-plan="cancelPlan"/>
  </section>
  <div v-if="!tasks.length" class="task-empty"><Check :size="26"/><strong>{{taskView.search||taskView.course?'没有匹配任务':taskView.view==='inbox'?'先记下来，再安排':'这里暂时没有任务'}}</strong><p>在下方输入标题即可添加。学习通作业可在「学习」中安排到今天。</p></div>
 </template>
 <template v-else>
  <div class="timeline-controls"><button class="icon-button" aria-label="前一天日程" @click="moveDay(-1)"><ChevronLeft :size="18"/></button><input v-model="agendaView.date" type="date" aria-label="日程日期"/><button class="icon-button" aria-label="后一天日程" @click="moveDay(1)"><ChevronRight :size="18"/></button><button class="text-button" @click="today">今天</button></div>
  <div class="timeline-options"><button :aria-pressed="agendaView.range===1" @click="agendaView.range=1">当天</button><button :aria-pressed="agendaView.range===7" @click="agendaView.range=7">未来7天</button><button @click="week">周视图</button><select v-model="agendaView.filter" aria-label="日程类型"><option value="all">全部安排</option><option value="course">课程</option><option value="exam">考试</option><option value="task">个人任务</option></select></div>
  <p v-if="!validDay(agendaView.date)" class="task-message">日期无效，暂显示今天。</p>
  <p v-if="summary.overdue.length" class="task-message danger"><button @click="taskView.mode='list';taskView.view='today'">{{summary.overdue.length}} 项任务逾期 · 重新规划</button></p>
  <p v-if="!schoolTerm?.data" class="task-hint">学校课表尚未同步，当前显示个人安排和已有考试缓存。</p><p v-if="academicCache.session==='expired'||schoolTerm?.error||academicCache.exams.error" class="task-hint">学校连接待更新，课程和考试显示上次缓存。</p>
  <p v-if="agenda.unknownExams" class="task-hint">{{agenda.unknownExams}} 条考试日期待核对，请查看考试安排原文。</p>
  <p v-if="nextEvent" class="task-next">即将开始 · {{nextEvent.title}} · {{nextEvent.time}}</p>
  <div v-for="day in days" :key="day.date" class="timeline-day"><h3>{{dayLabel(day.date)}}<small>{{day.events.length}} 项</small></h3>
   <template v-for="(e,index) in day.events" :key="e.id"><div v-if="day.date===beijingDay(now)&&index===nowIndex(day.events)" class="timeline-now">现在 {{new Intl.DateTimeFormat('zh-CN',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit'}).format(now)}}</div><article class="agenda-event timeline-event" :class="[e.kind,{deadline:e.source.includes('截止'),current:e.startAt!==null&&e.startAt<=+now&&(e.endAt??0)>+now}]">
    <span class="timeline-dot"/><button class="timeline-copy" @click="selectEvent(e)"><small>{{e.time}} · {{eventState(e)}}</small><strong>{{e.title}}</strong><span>{{e.location||e.source}} · {{e.source}}{{e.kind==='task'?'':' · 只读'}}</span></button>
   </article></template><div v-if="day.date===beijingDay(now)&&nowIndex(day.events)===day.events.length" class="timeline-now">现在 {{new Intl.DateTimeFormat('zh-CN',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit'}).format(now)}}</div><p v-if="!day.events.length" class="task-hint">暂无已知安排</p></div>
  <p class="task-hint">任务执行时间和最终截止分别展示。学校课程日期依赖本机学期配置；个人任务不会修改学校安排。</p>
 </template>
 <form v-if="taskView.mode==='list'" class="task-quick" aria-label="快速添加任务" @submit.prevent="quickAdd"><Plus :size="18"/><input v-model="taskView.quick" aria-label="快速任务标题" maxlength="100" placeholder="添加任务，回车保存" :disabled="!tasksReady"/><button class="primary" aria-label="快速保存任务" :disabled="!tasksReady||tasksBusy||!taskView.quick.trim()"><ArrowUp :size="18"/></button></form>
</section>
</template>
