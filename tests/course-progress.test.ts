// @vitest-environment jsdom
import {describe,it,expect} from 'vitest';
import {createApp,h,nextTick,ref} from 'vue';
import {courseProgress} from '../src/domain/course-progress';
import HomeCourseTimeline from '../src/components/HomeCourseTimeline.vue';
import type {Course} from '../src/domain/academic';

const course:Course={id:'weekly-course',name:'形势与政策七',teacher:'测试教师',room:'测试教室',day:3,start:'14:30',end:'15:55',period:'7-8',weeks:[1,2],color:'#7041ce'};
const at=(h:number,m:number,s=0)=>new Date(2026,10,11,h,m,s);
describe('课程实际时段进度',()=>{
 it('starts at zero, advances at actual time and ends at 100 percent',()=>{
  expect(courseProgress(course,at(14,29))).toMatchObject({state:'scheduled',percent:0,elapsedMinutes:0,remainingMinutes:85});
  expect(courseProgress(course,at(14,30))).toMatchObject({state:'current',percent:0,elapsedMinutes:0,remainingMinutes:85});
  expect(courseProgress(course,at(15,10))).toMatchObject({state:'current',elapsedMinutes:40,remainingMinutes:45});
  expect(courseProgress(course,at(15,10)).percent).toBeCloseTo(40/85*100);
  expect(courseProgress(course,at(15,55))).toMatchObject({state:'ended',percent:100,elapsedMinutes:85,remainingMinutes:0});
  expect(courseProgress(course,at(22,0)).percent).toBe(100);
 });
 it('uses seconds and does not report zero remaining before the end',()=>{
  expect(courseProgress(course,at(15,54,59)).remainingMinutes).toBe(1);
  expect(courseProgress(course,at(15,10,30)).percent).toBeGreaterThan(courseProgress(course,at(15,10)).percent);
 });
 it('does not turn invalid or zero duration times into a fake moving bar',()=>{
  for(const times of [{start:'15:55',end:'15:55'},{start:'25:00',end:'26:00'},{start:'bad',end:'15:55'}])expect(courseProgress(times,at(15,10))).toMatchObject({state:'invalid',percent:0});
 });
 it('updates a mounted single-course marker when time changes and de-emphasizes the ended occurrence',async()=>{
  const root=document.createElement('div');document.body.append(root);
  const now=ref(at(15,10));const app=createApp({render:()=>h(HomeCourseTimeline,{courses:[course],now:now.value})});app.mount(root);
  try{
   const marker=root.querySelector<HTMLElement>('.course-time-marker')!;
   const first=parseFloat(marker.style.left);
   expect(root.textContent).toContain('还剩45分钟');
   expect(root.querySelector('.home-timeline')?.classList.contains('is-single')).toBe(true);
   now.value=at(15,20);await nextTick();
   expect(parseFloat(marker.style.left)).toBeGreaterThan(first);expect(root.textContent).toContain('还剩35分钟');
   now.value=at(16,0);await nextTick();
   expect(root.textContent).toContain('已结束');expect(root.querySelector('.is-next')).toBeNull();
   expect(root.querySelector('[role="progressbar"]')?.getAttribute('aria-valuenow')).toBe('100');
  }finally{app.unmount();root.remove()}
 });
 it('keeps future courses at zero through the break and highlights only the next occurrence today',()=>{
  const root=document.createElement('div');const second={...course,id:'later',start:'16:30',end:'18:05'};
  const app=createApp({render:()=>h(HomeCourseTimeline,{courses:[course,second],now:at(16,0)})});app.mount(root);
  try{expect(root.querySelectorAll('.is-next')).toHaveLength(1);expect(root.querySelector('.is-next strong')?.textContent).toBe(second.name);expect(root.querySelector('.is-ended.is-next')).toBeNull()}finally{app.unmount()}
 });
});
