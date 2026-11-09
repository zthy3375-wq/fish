<script setup lang="ts">
import {Check,BookOpen,MoreHorizontal} from 'lucide-vue-next';
import type {CampusTask} from '../domain/agenda';
import {beijingDay,shiftDay} from '../domain/agenda';
import {plannedDay} from '../domain/tasks';
import {learningTaskState} from '../domain/learning-status';
const props=defineProps<{task:CampusTask;now:Date;busy?:boolean}>();
defineEmits<{open:[task:CampusTask];complete:[task:CampusTask];replan:[task:CampusTask,offset:number];cancelPlan:[task:CampusTask]}>();
function dateLabel(value:string){const d=value.slice(0,10);return (d===beijingDay(props.now)?'今天':d===shiftDay(beijingDay(props.now),1)?'明天':d.slice(5).replace('-','月')+'日')+(value.includes('T')?' '+value.slice(11):'')}
</script>
<template>
<article class="task-row daily-task-row" :class="{done:task.completed}">
<button v-if="task.source!=='chaoxing'" class="task-check" :aria-label="(task.completed?'恢复待办 ':'完成待办 ')+task.title" :disabled="busy" @click="$emit('complete',task)"><Check v-if="task.completed" :size="15"/></button><span v-else class="task-source-icon" aria-label="学习通作业"><BookOpen :size="18"/></span>
<button class="task-copy" @click="$emit('open',task)"><strong>{{task.title}}</strong><span v-if="task.course">{{task.course}}</span><span v-if="task.source==='chaoxing'" class="learning-task-badge">{{learningTaskState(task,now).label}}{{task.prepared&&!task.completed?' · 已做完待提交':''}}{{task.platformStale?' · 待更新':''}}</span><span v-if="plannedDay(task)">计划 {{dateLabel(task.plannedAt||task.plannedDay!)}}</span><span v-if="task.deadline" class="deadline-label">截止 {{dateLabel(task.deadline)}}</span><span v-if="task.steps?.length" class="task-progress">{{task.steps.filter(s=>s.completed).length}}/{{task.steps.length}} 步骤<small v-if="task.repeat"> · 重复任务</small></span></button>
<details class="row-menu"><summary :aria-label="'任务操作 '+task.title"><MoreHorizontal :size="18"/></summary><div><button @click="$emit('open',task)">查看详情</button><button :disabled="busy" @click="$emit('replan',task,0);($event.currentTarget as HTMLElement).closest('details')!.open=false">今天做</button><button :disabled="busy" @click="$emit('replan',task,1);($event.currentTarget as HTMLElement).closest('details')!.open=false">明天做</button><button v-if="task.source==='chaoxing'&&plannedDay(task)" class="danger" :disabled="busy" @click="$emit('cancelPlan',task);($event.currentTarget as HTMLElement).closest('details')!.open=false">取消安排</button></div></details>
</article>
</template>
