<script setup lang="ts">
import {ref,watch,computed} from 'vue';
import {learningCache,learningBusy,selectLearningCourses,syncLearning,pauseLearning} from '../composables/learning';
const selected=ref<string[]>([]),search=ref(''),error=ref('');
watch(()=>learningCache.value.selectedCourses,v=>selected.value=[...v],{immediate:true});
const courses=computed(()=>learningCache.value.courses.filter(c=>c.name.toLowerCase().includes(search.value.trim().toLowerCase())));
const key=(c:{courseId:string;classId:string})=>c.courseId+'/'+c.classId;
function state(k:string){const s=learningCache.value.courseSync[k];return !s?'尚未读取':s.status==='ok'?`已读取 ${s.count} 份作业`:s.status==='partial'?'仅取得部分作业':'读取失败，可单独重试'}
async function start(){try{error.value='';await selectLearningCourses(selected.value);await syncLearning({force:true,courseKeys:selected.value})}catch(e){error.value=(e as Error).message}}
</script>
<template>
<section v-if="learningCache.connected" class="sync-panel">
 <div class="sync-panel-head"><strong>课程同步</strong><span>{{learningCache.selectedCourses.length}} 门已关注</span></div>
 <p>先选择本学期需要关注的课程，历史课程可随时添加。</p>
 <div v-if="learningCache.plannedCount" class="sync-progress"><progress :max="learningCache.plannedCount" :value="learningCache.completedCount"/><small>本轮已处理 {{learningCache.completedCount}} / {{learningCache.plannedCount}} 门 · 成功情况见下方课程</small></div>
 <button v-if="learningBusy" class="text-button" @click="pauseLearning">本门完成后暂停</button>
 <button v-else-if="learningCache.remaining && !learningCache.issues.connection" class="text-button" @click="syncLearning({force:true})">继续剩余 {{learningCache.remaining}} 门</button>
 <details :open="!learningCache.selectedCourses.length"><summary>选择课程与查看同步结果</summary>
  <input v-model="search" class="learning-course-select" type="search" placeholder="搜索课程" aria-label="搜索同步课程"/>
  <p v-if="error" role="alert">{{error}}</p>
  <div class="sync-course-list"><div v-for="c in courses" :key="key(c)" class="sync-course-row">
   <label><input v-model="selected" :value="key(c)" type="checkbox" :disabled="learningBusy"/><span><strong>{{c.name}}</strong><small>{{state(key(c))}}</small></span></label>
   <button class="text-button" :disabled="learningBusy||learningCache.issues.connection==='VERIFY'" @click="syncLearning({force:true,courseKeys:[key(c)]})">更新</button>
  </div></div>
  <button class="primary" :disabled="learningBusy||!selected.length||learningCache.issues.connection==='VERIFY'" @click="start">保存并更新 {{selected.length}} 门课程</button>
 </details>
</section>
</template>
