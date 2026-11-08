<script setup lang="ts">
import {computed,defineAsyncComponent} from 'vue';
import {academicCache,schoolTerm} from '../composables/handan-academic';
import SchoolConnection from './SchoolConnection.vue';
const GradeAnalysis=defineAsyncComponent(()=>import('./GradeAnalysis.vue'));
defineProps<{section:string}>();
const profile=computed(()=>academicCache.value.profile.data);
const stamp=(s:string|null)=>s?new Date(s).toLocaleString('zh-CN',{hour12:false}):'尚未获取';
</script>
<template>
 <SchoolConnection v-if="section==='official'" />
 <GradeAnalysis v-else-if="section==='grades'" />
 <section v-else-if="section==='exams'" class="panel"><h2>考试安排</h2><p class="muted">{{academicCache.exams.error||('更新时间：'+stamp(academicCache.exams.updatedAt))}}</p>
  <article v-for="(e,i) in academicCache.exams.data" :key="i" class="exam-card"><div><h3>{{e.name}}</h3><p>{{e.date}} {{e.time}}</p><p>{{e.room}}<span v-if="e.seat"> · 座位 {{e.seat}}</span></p></div></article>
  <p v-if="!academicCache.exams.data?.length" class="inline-note">{{academicCache.exams.updatedAt?'学校本次查询没有考试安排':'考试待学校连接验证，当前没有本人数据'}}</p>
 </section>
 <template v-else-if="section==='study'"><GradeAnalysis center/><section class="panel"><h2>学籍资料</h2><p class="muted">{{academicCache.profile.error||('更新时间：'+stamp(academicCache.profile.updatedAt))}}</p><dl><dt>姓名</dt><dd>{{profile?.name||'—'}}</dd><dt>专业</dt><dd>{{profile?.major||'—'}}</dd><dt>班级</dt><dd>{{profile?.className||'—'}}</dd><dt>年级</dt><dd>{{profile?.year||'—'}}</dd></dl><p class="footnote">未取得的字段保留为空。</p>
 <template v-if="schoolTerm?.data?.practice.length"><h3>实践与实验安排</h3><p v-for="(p,i) in schoolTerm.data.practice" :key="i">{{p.name}} · {{p.teacher}} · {{p.weeks||'学校尚未提供具体时间'}}</p></template>
 </section></template>
</template>
