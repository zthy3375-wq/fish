<script lang="ts">
import {reactive} from 'vue';
const learningView=reactive<{tab:'homework'|'courses'|'exams'|'notices';status:LearningFilter;search:string;course:string}>({tab:'homework',status:'pending',search:'',course:''});
</script>
<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref} from 'vue';
import {BookOpen,ChevronRight,ChevronDown,Search,Settings2,RefreshCw,ArrowRight,Pause} from 'lucide-vue-next';
import LearningSyncPanel from './LearningSyncPanel.vue';
import LearningConnection from './LearningConnection.vue';
import {learningCache,learningTasks,learningBusy,initLearning,syncLearning,saveLearningPlan,pauseLearning,learningError} from '../composables/learning';
import {learningState,type LearningFilter} from '../domain/learning-status';
import {beijingDay,beijingTimestamp,type CampusTask} from '../domain/agenda';
import {plannedDay,replanTask} from '../domain/tasks';
import {resolveLearningItems,groupLearningItems} from '../domain/learning-groups';
import type {LearningItem} from '../services/chaoxing-client';
const emit=defineEmits<{plan:[task:CampusTask]}>();
const view=learningView,now=ref(new Date()),message=ref(''),saving=ref(false),management=ref<HTMLDetailsElement>();
const failedCount=computed(()=>Object.values(learningCache.value.courseSync).filter(r=>r.status==='error'||r.status==='partial').length);
function showCourses(){view.tab='courses'}
function refresh(){if(!learningCache.value.selectedCourses.length){showCourses();return}void syncLearning({force:true})}
const timer=setInterval(()=>now.value=new Date(),30000);onUnmounted(()=>clearInterval(timer));
onMounted(()=>{void initLearning().then(()=>syncLearning()).catch(()=>{})});
const homework=computed(()=>resolveLearningItems(learningCache.value.items,learningCache.value.courses).filter(i=>i.kind==='homework'));
const filters:[LearningFilter,string][]=[['pending','待提交'],['unknown','待核对'],['submitted','已提交'],['closed','已截止'],['all','全部']];
const list=computed(()=>homework.value.filter(i=>(view.status==='all'||learningState(i,now.value).key===view.status)&&(!view.course||i.courseId+'/'+i.classId===view.course)&&(!view.search||`${i.title} ${i.course}`.toLowerCase().includes(view.search.trim().toLowerCase()))).sort((a,b)=>(a.deadline?beijingTimestamp(a.deadline):Infinity)-(b.deadline?beijingTimestamp(b.deadline):Infinity)||a.title.localeCompare(b.title,'zh-CN')));
const groups=computed(()=>groupLearningItems(list.value,now.value));
const count=(key:LearningFilter)=>homework.value.filter(i=>(key==='all'||learningState(i,now.value).key===key)&&(!view.course||i.courseId+'/'+i.classId===view.course)).length;
const courseName=computed(()=>learningCache.value.courses.find(c=>c.courseId+'/'+c.classId===view.course)?.name);
const needsAction=computed(()=>!learningCache.value.connected||learningCache.value.session==='expired'||learningCache.value.issues.connection==='VERIFY');
const status=computed(()=>learningBusy.value?`正在更新 ${learningCache.value.completedCount}/${learningCache.value.plannedCount||'…'} 门课程`:!learningCache.value.connected?'连接后查看课程作业':learningCache.value.session==='expired'?'登录已过期，点击重新连接':learningCache.value.issues.connection==='VERIFY'?'需要完成验证码，已有作业保留':learningCache.value.remaining?`还有 ${learningCache.value.remaining} 门课程待更新`:Object.keys(learningCache.value.issues).length?'部分内容未更新，已读记录保留':learningCache.value.updatedAt?'上次更新 '+new Date(learningCache.value.updatedAt).toLocaleTimeString('zh-CN',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit'}):'选择关注课程开始同步');
function task(item:LearningItem){return learningTasks.value.find(t=>t.externalId===item.id)}
function isToday(item:LearningItem){const t=task(item);return !!t&&plannedDay(t)===beijingDay(now.value)}
function open(item:LearningItem){const t=task(item);if(t)emit('plan',t)}
async function today(item:LearningItem){const t=task(item);if(!t||saving.value)return;try{saving.value=true;await saveLearningPlan(replanTask({...t},beijingDay(now.value)));message.value='已加入今天，截止时间不变'}catch(e){message.value=(e as Error).message}finally{saving.value=false}}
function deadline(item:LearningItem){if(!item.deadline)return '截止时间待核对';const d=item.deadline.slice(0,10);return (d===beijingDay(now.value)?'今天':d.slice(5).replace('-','月')+'日')+' '+item.deadline.slice(11)+' 截止'}
function chooseCourse(key:string){view.course=key;view.status='all';view.tab='homework'}
</script>
<template>
<section class="learning-center daily-learning" aria-label="学习通中心">
<div class="lc-topbar"><span>{{learningCache.connected?'学习通已连接':'课程与作业，一处查看'}}</span><button class="icon-button" aria-label="同步管理" @click="management!.open=!management!.open"><Settings2 :size="19"/></button></div>
<details ref="management" class="learning-management" :open="!learningCache.connected"><summary>账号设置</summary><LearningConnection/></details>
<template v-if="learningCache.connected">
 <div class="lc-navigation">
  <div class="lc-primary-tabs" role="tablist" aria-label="学习任务"><button role="tab" :aria-selected="view.tab==='homework'" @click="view.tab='homework'">作业</button><button role="tab" :aria-selected="view.tab==='exams'" @click="view.tab='exams'">考试</button></div>
  <div class="lc-tools"><button :aria-pressed="view.tab==='courses'" @click="showCourses"><BookOpen :size="16"/>课程管理</button><button :aria-pressed="view.tab==='notices'" @click="view.tab='notices'">通知<ChevronRight :size="15"/></button></div>
 </div>
 <div v-if="view.tab==='homework'" class="lc-overview"><div><h2>{{count('pending')?`${count('pending')} 份作业待提交`:'看看今天的学习任务'}}</h2><p>{{status}}</p></div><button class="lc-refresh" :disabled="learningBusy" aria-label="更新关注课程" @click="refresh"><RefreshCw :size="18"/>{{learningBusy?'更新中':'更新'}}</button></div>
 <div v-if="learningBusy||learningCache.remaining" class="lc-progress" role="status"><span>{{learningBusy?'正在读取':'更新已暂停'}} · 已处理 {{learningCache.completedCount}} / {{learningCache.plannedCount}} 门</span><button v-if="learningBusy" class="text-button" @click="pauseLearning"><Pause :size="14"/>暂停</button><button v-else class="text-button" @click="syncLearning({force:true})">继续更新</button><progress :max="Math.max(1,learningCache.plannedCount)" :value="learningCache.completedCount"/></div>
 <button v-if="needsAction" class="lc-attention" @click="management!.open=true">{{status}}<ArrowRight :size="16"/></button>
 <button v-else-if="!learningCache.selectedCourses.length&&view.tab!=='courses'" class="lc-attention" @click="showCourses"><span>选择常用课程，之后一键更新作业</span><ArrowRight :size="16"/></button>
 <button v-else-if="failedCount&&view.tab!=='courses'" class="lc-attention" @click="showCourses"><span>{{failedCount}} 门课程未读完整，已读作业可继续查看</span><ArrowRight :size="16"/></button>
 <p v-if="learningError" class="task-message" role="status">{{learningError}}</p>

</template>
<p v-if="message" role="status" class="task-message">{{message}}</p>
<template v-if="view.tab==='homework'">
<div v-if="view.course" class="course-context"><strong>{{courseName||'所选课程'}}</strong><button class="text-button" @click="view.course='';view.status='pending'">全部课程</button></div>
<div v-if="learningCache.connected" class="smart-lists learning-filters" aria-label="作业状态筛选"><button v-for="[key,label] in filters" :key="key" :aria-pressed="view.status===key" @click="view.status=key">{{label}}<small>{{count(key)}}</small></button></div>
<div v-if="learningCache.connected" class="task-search"><Search :size="16"/><input v-model="view.search" type="search" placeholder="搜索作业或课程" aria-label="搜索学习通作业"/></div>
<p v-if="learningCache.connected" class="task-hint">{{list.length}} 份已读取作业<template v-if="view.status==='unknown'"> · 提交状态需要核对</template><template v-else-if="view.status==='closed'"> · 截止与提交是不同状态</template></p>
<details v-for="group in groups" :key="group.key" class="learning-course-group" open><summary><BookOpen :size="17"/><span class="learning-group-copy"><strong>{{group.name}}</strong><small>{{group.items.length}} 份作业</small></span><ChevronDown :size="16"/></summary>
<article v-for="item in group.items" :key="item.id" class="learning-work compact-work"><button class="work-open" @click="open(item)"><strong>{{item.title}}</strong><small>{{deadline(item)}}</small><span class="learning-state" :class="learningState(item,now).key">{{learningState(item,now).label}}</span><small v-if="item.stale" class="danger">上次记录 · 待更新</small></button><button v-if="learningState(item,now).key==='pending'" class="text-button plan-today" :disabled="saving||isToday(item)" @click="today(item)">{{isToday(item)?'已安排今天':'今天做'}}</button></article></details>
<div v-if="!list.length" class="task-empty"><BookOpen :size="25"/><strong>{{view.search?'没有匹配作业':!learningCache.connected?'先连接学习通':!homework.length?'尚未读取到作业':'当前分类没有作业'}}</strong><p>{{!learningCache.connected?'登录后选择需要关注的课程。':'可切换分类，或在课程管理中更新作业。'}}</p><button v-if="learningCache.connected" class="text-button" @click="showCourses">查看课程</button></div>
</template>
<template v-else-if="view.tab==='courses'"><LearningSyncPanel @view="chooseCourse"/></template>
<template v-else-if="view.tab==='exams'"><p class="task-hint">{{learningCache.issues.exams?'考试尚未完整更新，保留上次记录':learningCache.examUpdatedAt?'学习通考试 · 上次同步记录':'考试尚未同步'}}</p><article v-for="item in learningCache.items.filter(i=>i.kind==='exam')" :key="item.id" class="learning-work"><button class="work-open" @click="open(item)"><strong>{{item.title}}</strong><small>{{item.course}} · {{deadline(item)}}</small><span class="learning-state" :class="learningState(item,now).key">{{learningState(item,now).label}}</span></button></article><p v-if="!learningCache.items.some(i=>i.kind==='exam')" class="task-empty">暂无已读取考试</p></template>
<template v-else><p class="task-hint">{{learningCache.issues.notices?'通知尚未完整更新，保留上次记录':learningCache.noticeUpdatedAt?'上次同步的通知':'通知尚未同步'}}</p><details v-for="n in learningCache.notices" :key="n.id" class="learning-work"><summary>{{n.title}}</summary><small>{{n.sender}} · {{n.publishedText}}</small><p>{{n.content}}</p></details><p v-if="!learningCache.notices.length" class="task-empty">暂无已读取通知</p></template>
</section>
</template>

<style src="../learning-center.css"></style>
