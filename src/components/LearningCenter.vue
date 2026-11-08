<script setup lang="ts">
import {computed,onMounted,onUnmounted,reactive,ref} from 'vue';
import {BookOpen,ChevronRight,ChevronDown,Search,ExternalLink,CalendarClock} from 'lucide-vue-next';
import LearningSyncPanel from './LearningSyncPanel.vue';
import LearningConnection from './LearningConnection.vue';
import {learningCache,learningTasks,initLearning,syncLearning,openLearningItem} from '../composables/learning';
import {learningState,type LearningFilter} from '../domain/learning-status';
import {beijingTimestamp,type CampusTask} from '../domain/agenda';
import {resolveLearningItems,groupLearningItems} from '../domain/learning-groups';
import type {LearningItem} from '../services/chaoxing-client';
const emit=defineEmits<{plan:[task:CampusTask]}>();
// Kept at module scope through a separate shared view object, independent of personal task filters.
const view=learningView;
const now=ref(new Date()),error=ref('');const timer=setInterval(()=>now.value=new Date(),30000);onUnmounted(()=>clearInterval(timer));
onMounted(()=>{void initLearning().then(()=>syncLearning()).catch(()=>{})});
const homework=computed(()=>resolveLearningItems(learningCache.value.items,learningCache.value.courses).filter(i=>i.kind==='homework'));
const filters:[LearningFilter,string][]=[['all','全部'],['pending','待提交'],['submitted','已提交 / 完成'],['closed','已截止'],['unknown','状态未知']];
const count=(key:LearningFilter)=>homework.value.filter(i=>key==='all'||learningState(i,now.value).key===key).length;
const list=computed(()=>homework.value.filter(i=>(view.status==='all'||learningState(i,now.value).key===view.status)&&(!view.course||i.courseId+'/'+i.classId===view.course)&&(!view.search||`${i.title} ${i.course}`.toLowerCase().includes(view.search.trim().toLowerCase()))).sort((a,b)=>(a.deadline?beijingTimestamp(a.deadline):Infinity)-(b.deadline?beijingTimestamp(b.deadline):Infinity)||a.title.localeCompare(b.title,'zh-CN')));
const groups=computed(()=>groupLearningItems(list.value,now.value));
function task(item:LearningItem){return learningTasks.value.find(t=>t.externalId===item.id)}
async function open(item:LearningItem){const t=task(item);if(!t)return;try{error.value='';await openLearningItem(t)}catch(e){error.value=(e as Error).message}}
function plan(item:LearningItem){const t=task(item);if(t)emit('plan',t)}
function deadline(item:LearningItem){if(!item.deadline)return '截止时间未知';return '截止 '+item.deadline.replace('T',' ')}
</script>
<script lang="ts">
// Survives navigation without borrowing or overwriting the unified task view.
const learningView=reactive<{tab:'homework'|'courses'|'exams'|'notices';status:LearningFilter;search:string;course:string}>({tab:'homework',status:'all',search:'',course:''});
</script>
<template>
<section class="learning-center" aria-label="学习通中心">
 <LearningConnection/>
 <LearningSyncPanel/>
 <div class="task-mode" role="tablist" aria-label="学习通内容"><button v-for="[id,label] in [['homework','作业'],['courses','课程'],['exams','考试'],['notices','通知']]" :key="id" role="tab" :aria-selected="view.tab===id" @click="view.tab=id as typeof view.tab">{{label}}</button></div>
 <p v-if="error" role="alert" class="task-message danger">{{error}}</p>
 <template v-if="view.tab==='homework'">
  <div class="learning-overview"><strong>已读取 {{homework.length}} 份作业</strong><small>{{learningCache.remaining?`剩余 ${learningCache.remaining} 门课程待扫描`:'按已读取记录统计'}} · {{groups.length}} 门课程</small></div>
  <div class="smart-lists learning-filters" aria-label="作业状态筛选"><button v-for="[key,label] in filters" :key="key" :aria-pressed="view.status===key" @click="view.status=key">{{label}}<small>{{count(key)}}</small></button></div>
  <div class="task-search"><Search :size="16"/><input v-model="view.search" type="search" placeholder="搜索作业或课程" aria-label="搜索学习通作业"/></div>
  <select v-model="view.course" class="learning-course-select" aria-label="学习通课程筛选"><option value="">全部课程</option><option v-for="c in learningCache.courses" :key="c.courseId+'/'+c.classId" :value="c.courseId+'/'+c.classId">{{c.name}}</option></select>
  <p v-if="!list.length" class="task-hint">{{homework.length?'当前筛选下没有作业':'尚未读取到作业。连接后自动扫描；遇到验证时，完成验证后继续。'}}</p>
  <details v-for="group in groups" :key="group.key" class="learning-course-group" open>
   <summary><span class="learning-group-icon"><BookOpen :size="18"/></span><span class="learning-group-copy"><strong>{{group.name}}</strong><small>{{group.items.length}} 份作业<template v-if="group.pending"> · {{group.pending}} 待提交</template><template v-if="group.unknown"> · {{group.unknown}} 状态待核对</template><template v-if="group.closed"> · {{group.closed}} 已截止</template><template v-if="group.submitted"> · {{group.submitted}} 已提交 / 完成</template></small></span><ChevronDown :size="17" class="learning-group-chevron"/></summary>
  <article v-for="item in group.items" :key="item.id" class="learning-work">
   <div class="learning-work-head"><strong>{{item.title}}</strong><span class="learning-state" :class="learningState(item,now).key">{{learningState(item,now).label}}</span></div>
   <small>{{deadline(item)}}</small>
   <small v-if="learningState(item,now).key==='unknown'" class="learning-status-note">平台提交状态尚未识别，可打开原作业核对</small>
   <small v-if="item.statusText&&item.statusText!=='未知'&&item.statusText!=='提交状态未知'">平台：{{item.statusText}}</small>
   <small v-if="item.stale||learningCache.session!=='valid'" class="danger">上次同步记录，当前状态待更新</small>
   <div class="learning-work-actions"><button class="text-button" @click="plan(item)"><CalendarClock :size="14"/>安排到日程</button><button class="text-button" :disabled="!item.hasLink" @click="open(item)">打开原作业 <ExternalLink :size="14"/></button></div>
   <small v-if="!item.hasLink">平台未提供可识别的作业详情链接</small>
  </article>
  </details>
 </template>
 <template v-else-if="view.tab==='courses'"><h3 class="learning-section-title">{{learningCache.courses.length}} 门课程</h3><p v-if="!learningCache.courses.length" class="task-hint">课程尚未读取。</p><button v-for="c in learningCache.courses" :key="c.courseId+'/'+c.classId" class="learning-course-button" @click="view.course=c.courseId+'/'+c.classId;view.status='all';view.tab='homework'"><BookOpen :size="18"/><span><strong>{{c.name}}</strong><small>{{c.teacher||'教师信息未提供'}} · {{homework.filter(i=>i.courseId===c.courseId&&i.classId===c.classId).length}} 份已读取作业</small></span><ChevronRight :size="16"/></button></template>
 <template v-else-if="view.tab==='exams'"><p class="task-hint">{{learningCache.issues.exams?'考试暂未完整更新，保留上次记录':learningCache.examUpdatedAt?'展示上次同步的考试安排':'考试尚未同步。作业扫描完成后再查询。'}}</p><article v-for="item in learningCache.items.filter(i=>i.kind==='exam')" :key="item.id" class="learning-work"><div class="learning-work-head"><strong>{{item.title}}</strong><span class="learning-state" :class="learningState(item,now).key">{{learningState(item,now).label}}</span></div><p>{{item.course}}</p><small>开始 {{item.startAt?.replace('T',' ')||'未知'}} · {{deadline(item)}}</small><button class="text-button" :disabled="!item.hasLink" @click="open(item)">打开原考试</button></article></template>
 <template v-else><p class="task-hint">{{learningCache.issues.notices?'通知暂未完整更新，保留上次记录':learningCache.noticeUpdatedAt?'展示上次同步的通知':'通知尚未同步。作业扫描完成后再查询。'}}</p><details v-for="n in learningCache.notices" :key="n.id" class="learning-work"><summary>{{n.title}}</summary><small>{{n.sender||'发布者未知'}} · {{n.publishedText||'时间未知'}}</small><p>{{n.content}}</p></details></template>
</section>
</template>
