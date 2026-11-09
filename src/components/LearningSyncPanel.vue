<script setup lang="ts">
import {ref,computed} from 'vue';
import {BookOpen,Search,ChevronRight,RefreshCw,Check,Plus} from 'lucide-vue-next';
import {learningCourseStatus} from '../domain/learning-sync-status';
import {learningCache,learningBusy,selectLearningCourses,syncLearning} from '../composables/learning';
const emit=defineEmits<{view:[key:string]}>();
const search=ref(''),scope=ref<'all'|'followed'|'failed'>('all'),error=ref(''),saving=ref(false);
const key=(c:{courseId:string;classId:string})=>c.courseId+'/'+c.classId;
const followed=(k:string)=>learningCache.value.selectedCourses.includes(k);
const failed=(k:string)=>['error','partial'].includes(learningCache.value.courseSync[k]?.status);
const failures=computed(()=>learningCache.value.courses.filter(c=>failed(key(c))).length);
const blocked=computed(()=>learningBusy.value||saving.value||learningCache.value.issues.connection==='VERIFY');
const courses=computed(()=>learningCache.value.courses.filter(c=>c.name.toLowerCase().includes(search.value.trim().toLowerCase())&&(scope.value==='all'||scope.value==='followed'&&followed(key(c))||scope.value==='failed'&&failed(key(c)))).sort((a,b)=>Number(followed(key(b)))-Number(followed(key(a)))));
function state(k:string){const r=learningCache.value.courseSync[k];return !r?'还未读取':r.status==='ok'?`已读取 ${r.count} 份作业`:r.status==='partial'?`已保留 ${r.count} 份 · 未读完整`:'读取未成功'}
async function follow(k:string){if(blocked.value)return;try{saving.value=true;error.value='';const remove=followed(k);await selectLearningCourses(remove?learningCache.value.selectedCourses.filter(v=>v!==k):[...learningCache.value.selectedCourses,k]);if(!remove)await syncLearning({force:true,courseKeys:[k]})}catch{error.value='课程关注未保存，请重试'}finally{saving.value=false}}
</script>
<template>
<section class="lc-courses" aria-label="课程管理">
 <div class="lc-section-head"><div><h3>我的课程</h3><p>关注常用课程，下次一起更新。</p></div><span>{{learningCache.selectedCourses.length}} 门已关注</span></div>
 <div class="lc-search"><Search :size="18"/><input v-model="search" type="search" placeholder="搜索课程" aria-label="搜索同步课程"/></div>
 <div class="lc-course-filters" aria-label="课程筛选"><button :aria-pressed="scope==='all'" @click="scope='all'">全部 {{learningCache.courses.length}}</button><button :aria-pressed="scope==='followed'" @click="scope='followed'">已关注 {{learningCache.selectedCourses.length}}</button><button :aria-pressed="scope==='failed'" @click="scope='failed'">需处理 {{failures}}</button></div>
 <p v-if="error" role="alert">{{error}}</p>
 <article v-for="c in courses" :key="key(c)" class="lc-course" :class="{failed:failed(key(c))}">
  <button class="learning-course-button" @click="emit('view',key(c))"><span class="lc-book"><BookOpen :size="20"/></span><span><strong>{{c.name}}</strong><small>{{state(key(c))}}</small></span><ChevronRight :size="17"/></button>
  <div class="lc-course-actions"><button :disabled="blocked" :aria-pressed="followed(key(c))" :aria-label="(followed(key(c))?'取消关注 ':'关注并读取 ')+c.name" @click="follow(key(c))"><Check v-if="followed(key(c))" :size="15"/><Plus v-else :size="15"/>{{followed(key(c))?'已关注':'关注并读取'}}</button><button :disabled="blocked" :aria-label="'更新 '+c.name" @click="syncLearning({force:true,courseKeys:[key(c)]})"><RefreshCw :size="14"/>{{failed(key(c))?'重试读取':'更新作业'}}</button></div>
  <details v-if="failed(key(c))" class="lc-course-reason"><summary>为什么没读到？</summary><p>{{learningCourseStatus(learningCache.courseSync[key(c)])}}</p><p>可在“我的”导出反馈并发送到 QQ。已有作业会保留。</p></details>
 </article>
 <div v-if="!courses.length" class="task-empty"><strong>{{search?'没有匹配课程':scope==='failed'?'没有读取失败的课程':scope==='followed'?'还没有关注课程':'还没有读取到课程'}}</strong><p>{{scope==='followed'?'切换到全部，关注本学期需要的课程。':'可以切换筛选或稍后刷新。'}}</p><button v-if="scope!=='all'" class="text-button" @click="scope='all'">查看全部课程</button></div>
</section>
</template>
