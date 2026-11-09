<script setup lang="ts">
import {computed,ref} from 'vue';
import {allTasks,tasksReady,tasksBusy,changeTasks,cancelLearningSchedule} from '../composables/tasks';
import {saveLearningPlan} from '../composables/learning';
import {taskSummary,replanTask} from '../domain/tasks';
import {beijingDay,shiftDay,beijingTimestamp,type CampusTask} from '../domain/agenda';
import {learningTaskState} from '../domain/learning-status';
import {taskStore} from '../services/task-store';
import DailyTaskRow from './DailyTaskRow.vue';
const props=defineProps<{now:Date}>();
defineEmits<{open:[task:CampusTask];navigate:[section:string];create:[]}>();
const message=ref(''),undoTask=ref<CampusTask|null>(null);
const today=computed(()=>taskSummary(allTasks.value,props.now).today);
const urgent=computed(()=>allTasks.value.filter(t=>!t.completed&&t.deadline&&t.deadline.slice(0,10)<=shiftDay(beijingDay(props.now),7)&&!today.value.some(x=>x.id===t.id)&&(t.source!=='chaoxing'||learningTaskState(t,props.now).key==='pending')).sort((a,b)=>beijingTimestamp(a.deadline!)-beijingTimestamp(b.deadline!)));
async function complete(t:CampusTask){try{await changeTasks(()=>taskStore.complete(t.id,!t.completed));undoTask.value=t;message.value=t.completed?'已恢复任务':'已完成'}catch(e){message.value=(e as Error).message}}
async function undo(){const current=allTasks.value.find(t=>t.id===undoTask.value?.id);if(current)await complete(current);undoTask.value=null}
async function cancelPlan(task:CampusTask){try{await cancelLearningSchedule(task);message.value='已取消安排，原作业保留在学习通'}catch(e){message.value=(e as Error).message}}
async function replan(t:CampusTask,offset:number){try{const day=shiftDay(beijingDay(props.now),offset);if(t.source==='chaoxing')await saveLearningPlan(replanTask({...t},day,props.now));else await changeTasks(()=>taskStore.change(s=>{const target=s.tasks.find(x=>x.id===t.id);if(target)replanTask(target,day,props.now)}));message.value=offset?'已安排明天':'已加入今天'}catch(e){message.value=(e as Error).message}}
</script>
<template>
<section class="today-tasks"><div class="section-heading"><h2>今天计划 <small>{{today.length}}</small></h2><button class="text-button" @click="$emit('navigate','agenda')">全部待办</button></div><p v-if="message" class="task-message" role="status">{{message}} <button v-if="undoTask" class="text-button" @click="undo">撤销</button></p>
<DailyTaskRow class="today-planned-row" v-for="t in today.slice(0,4)" :key="t.id" :task="t" :now="now" :busy="tasksBusy" @open="$emit('open',$event)" @complete="complete" @replan="replan" @cancel-plan="cancelPlan"/>
<button v-if="tasksReady&&!today.length" class="today-empty" @click="$emit('create')">今天还没有计划 <span>＋ 记一件事</span></button><button v-if="today.length>4" class="text-button" @click="$emit('navigate','agenda')">查看其余 {{today.length-4}} 项</button>
<template v-if="urgent.length"><div class="section-heading"><h2>留意截止 <small>{{urgent.length}}</small></h2><button class="text-button" @click="$emit('navigate','learning')">学习通</button></div><p class="task-hint">未来 7 天内截止及逾期的个人任务，尚未加入今天计划。</p><DailyTaskRow v-for="t in urgent.slice(0,3)" :key="t.id" :task="t" :now="now" :busy="tasksBusy" @open="$emit('open',$event)" @complete="complete" @replan="replan" @cancel-plan="cancelPlan"/><button v-if="urgent.length>3" class="text-button" @click="$emit('navigate','due')">查看全部 {{urgent.length}} 项</button></template>
</section>
</template>
