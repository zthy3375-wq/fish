<script setup lang="ts">
import type {Course} from '../domain/academic';import {MapPin,ChevronRight} from 'lucide-vue-next';
defineProps<{course:Course;status?:string;next?:boolean;grouped?:boolean}>();defineEmits<{select:[course:Course]}>();
</script>
<template><button class="course-card" :class="[course.color,status,{isNext:next,'course-row':grouped}]" @click="$emit('select',course)"><span class="course-time"><strong>{{course.start}}</strong><small>{{course.end}}</small></span><span class="course-stripe"/><span class="course-copy"><span class="course-title"><strong :title="course.name">{{course.name}}</strong><span class="course-status" :class="{live:status==='current'}">{{status==='current'?'正在上课':status==='ended'?'已结束':next?'下一节':course.period}}</span></span><span class="course-place"><MapPin :size="13"/>{{course.room}}<span>· {{course.teacher}}</span></span></span><ChevronRight class="row-chevron" :size="16"/></button></template>
