<script setup lang="ts">
import {computed} from 'vue';
import type {Course} from '../domain/academic';
import {courseProgress} from '../domain/course-progress';
import {timeOf} from '../domain/presentation';
const props=defineProps<{courses:Course[];now:Date}>();
defineEmits<{select:[course:Course]}>();
const items=computed(()=>props.courses.map(course=>({course,...courseProgress(course,props.now)})));
const nextId=computed(()=>items.value.some(i=>i.state==='current')?undefined:items.value.find(i=>i.state==='scheduled')?.course.id);
const label=(state:string)=>state==='current'?'上课中':state==='ended'?'已结束':state==='invalid'?'时间待核对':'未开始';
</script>

<template>
 <div class="home-timeline" :class="{'is-single':items.length===1}" aria-label="今日课程时间线">
  <button v-for="item in items" :key="item.course.id" class="course-time-item" :class="{'is-current':item.state==='current','is-ended':item.state==='ended','is-next':item.course.id===nextId}" :aria-label="`${item.course.name} ${item.course.start}–${item.course.end} ${item.course.room} ${label(item.state)}${item.state==='current'?'，还剩'+item.remainingMinutes+'分钟':''}`" @click="$emit('select',item.course)">
   <span class="course-time-track" role="progressbar" :aria-label="`${item.course.name}上课进度`" aria-valuemin="0" aria-valuemax="100" :aria-valuenow="Math.round(item.percent)" :aria-valuetext="item.state==='current'?`已进行${item.elapsedMinutes}分钟，还剩${item.remainingMinutes}分钟`:label(item.state)">
    <span class="course-time-fill" :style="{width:item.percent+'%'}"/>
    <span class="course-time-marker" :style="{left:item.percent+'%'}"/>
   </span>
   <span class="course-time-heading"><strong>{{item.course.name}}</strong><small>{{label(item.state)}}</small><time v-if="item.state==='current'&&items.length===1" class="course-time-now">{{timeOf(now)}}</time></span>
   <span class="course-time-caption"><time>{{item.course.start}}</time><span v-if="item.state==='current'">{{items.length===1?'已进行'+item.elapsedMinutes+'分钟 · ':''}}还剩{{item.remainingMinutes}}分钟</span><time>{{item.course.end}}</time></span>
  </button>
 </div>
</template>

<style scoped>
.home-timeline{display:flex;overflow-x:auto;gap:16px;padding:4px 16px 12px;scroll-snap-type:x proximity}
.course-time-item{position:relative;flex:1 0 150px;min-width:0;padding:0;text-align:left;scroll-snap-align:start;color:var(--color-muted);font-variant-numeric:tabular-nums}
.is-single .course-time-item{flex:1 1 100%}
.course-time-track{position:relative;display:block;height:3px;margin:5px 5px 10px;background:var(--color-divider);border-radius:5px}
.course-time-fill{position:absolute;inset:0 auto 0 0;border-radius:inherit;background:var(--color-border);transition:width 1s linear}
.course-time-marker{position:absolute;top:50%;width:8px;height:8px;border-radius:50%;background:var(--color-border);transform:translate(-50%,-50%);transition:left 1s linear}
.is-current .course-time-fill{background:var(--color-primary)}
.is-current .course-time-marker,.is-next .course-time-marker{background:var(--color-primary);box-shadow:0 0 0 3px var(--color-tint)}
.course-time-heading{display:flex;align-items:center;gap:5px;min-width:0;font-size:11px;line-height:1.5}
.course-time-heading strong{min-width:0;font-weight:550;white-space:nowrap;text-overflow:ellipsis;overflow:hidden;color:var(--color-text)}
.course-time-heading small{flex-shrink:0;font-size:9px}
.course-time-now{margin-left:auto;font-size:10px}
.is-current .course-time-heading,.is-current strong,.is-next strong{color:var(--color-primary)}
.is-ended strong{color:var(--color-muted)}
.course-time-caption{display:flex;justify-content:space-between;gap:6px;margin-top:4px;font-size:10px;line-height:1.5;color:var(--color-muted);white-space:nowrap}
.course-time-caption span{font-size:9px}
@media(prefers-reduced-motion:reduce){.course-time-fill,.course-time-marker{transition:none}}
</style>
