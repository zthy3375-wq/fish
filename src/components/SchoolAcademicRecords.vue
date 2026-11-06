<script setup lang="ts">
import {ref,computed} from 'vue';
import {academicCache,schoolTerm} from '../composables/handan-academic';
import SchoolConnection from './SchoolConnection.vue';
const props=defineProps<{section:string}>();const term=ref('all'),query=ref('');
const grades=computed(()=>(academicCache.value.grades.data||[]).filter(g=>(term.value==='all'||g.term===term.value)&&g.name.includes(query.value)));
const numeric=computed(()=>grades.value.filter(g=>/^\d+(?:\.\d+)?$/.test(g.scoreText)&&g.credit!=null&&g.credit>0));
const average=computed(()=>{const total=numeric.value.reduce((s,g)=>s+g.credit!,0);return total?(numeric.value.reduce((s,g)=>s+Number(g.scoreText)*g.credit!,0)/total).toFixed(2):'—'});
const profile=computed(()=>academicCache.value.profile.data);
const stamp=(s:string|null)=>s?new Date(s).toLocaleString('zh-CN',{hour12:false}):'尚未获取';
</script>
<template>
 <SchoolConnection v-if="section==='official'" />
 <section v-else-if="section==='grades'" class="panel">
  <h2>成绩查询</h2><p class="muted">{{academicCache.grades.error||('更新时间：'+stamp(academicCache.grades.updatedAt))}}</p>
  <div class="schedule-toolbar"><select v-model="term" aria-label="成绩学期"><option value="all">全部学期</option><option v-for="t in [...new Set(academicCache.grades.data?.map(g=>g.term))]" :key="t">{{t}}</option></select><input v-model="query" placeholder="搜索课程" aria-label="搜索成绩课程" /></div>
  <p class="inline-note">数值成绩加权平均：{{average}} · 等级成绩保留学校原文，绩点仅显示学校返回值。</p>
  <div class="grade-list"><article v-for="(g,i) in grades" :key="`${g.term}-${g.name}-${i}`" class="grade-row"><div><h3>{{g.name}}</h3><small>{{g.term}} · {{g.kind}} · {{g.credit??'—'}} 学分<span v-if="g.gpa!=null"> · 绩点 {{g.gpa}}</span></small></div><strong>{{g.scoreText}}</strong></article></div>
  <p v-if="!grades.length" class="inline-note">{{academicCache.grades.updatedAt?'学校本次查询没有成绩记录':'成绩待学校连接验证，当前没有本人数据'}}</p>
 </section>
 <section v-else-if="section==='exams'" class="panel"><h2>考试安排</h2><p class="muted">{{academicCache.exams.error||('更新时间：'+stamp(academicCache.exams.updatedAt))}}</p>
  <article v-for="(e,i) in academicCache.exams.data" :key="i" class="exam-card"><div><h3>{{e.name}}</h3><p>{{e.date}} {{e.time}}</p><p>{{e.room}}<span v-if="e.seat"> · 座位 {{e.seat}}</span></p></div></article>
  <p v-if="!academicCache.exams.data?.length" class="inline-note">{{academicCache.exams.updatedAt?'学校本次查询没有考试安排':'考试待学校连接验证，当前没有本人数据'}}</p>
 </section>
 <section v-else-if="section==='study'" class="panel"><h2>学籍资料</h2><p class="muted">{{academicCache.profile.error||('更新时间：'+stamp(academicCache.profile.updatedAt))}}</p><dl><dt>姓名</dt><dd>{{profile?.name||'—'}}</dd><dt>专业</dt><dd>{{profile?.major||'—'}}</dd><dt>班级</dt><dd>{{profile?.className||'—'}}</dd><dt>年级</dt><dd>{{profile?.year||'—'}}</dd></dl><p class="footnote">未取得的字段保留为空。</p>
 <template v-if="schoolTerm?.data?.practice.length"><h3>实践与实验安排</h3><p v-for="(p,i) in schoolTerm.data.practice" :key="i">{{p.name}} · {{p.teacher}} · {{p.weeks||'学校尚未提供具体时间'}}</p></template>
 </section>
</template>
