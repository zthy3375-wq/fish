import {describe,it,expect} from 'vitest';
import {applySchoolAdjustments,schoolCourseKey,updateSchoolAdjustments,adjustmentConflicts,inactiveAdjustmentCount,validateSchoolAdjustments,type CourseTimeChange} from '../src/domain/school-course-adjustments';
import type {Course} from '../src/domain/academic';
import {handanTimeTable} from '../src/domain/handan-time-table';
import {buildAgenda} from '../src/domain/agenda';
import {defaultState} from '../src/domain/schedule';
const table=handanTimeTable(),term='2026-3';
const original=():Course=>({id:'school-course/a',courseId:'school-course',arrangementId:'a',name:'合成调课测试',teacher:'教师',room:'原教室',day:2,start:'08:00',end:'09:25',startPeriod:1,endPeriod:2,timeMode:'period',period:'1–2 节',weeks:[1,3,5,7,9,11],color:'blue'});
const change:CourseTimeChange={day:4,room:'新教室',start:'14:30',end:'15:55',startPeriod:6,endPeriod:7,timeMode:'period'};
const project=(records:ReturnType<typeof updateSchoolAdjustments>,courses=[original()])=>applySchoolAdjustments(courses,term,records,table);
describe('学校课程按周调整',()=>{
 it('moves exactly one occurrence without changing the school cache or other weeks',()=>{
  const source=original(),before=structuredClone(source),records=updateSchoolAdjustments([],term,source,[5],change,table),courses=project(records);
  expect(source).toEqual(before);expect(courses).toHaveLength(2);
  expect(courses[0]).toMatchObject({day:2,weeks:[1,3,7,9,11]});expect(courses[1]).toMatchObject({day:4,weeks:[5],room:'新教室',start:'14:30',end:'15:55',locallyAdjusted:true});
 });
 it('future changes retain odd weeks instead of creating missing even-week lessons',()=>{
  const source=original(),records=updateSchoolAdjustments([],term,source,source.weeks.filter(w=>w>=7),change,table);
  expect(project(records)[1].weeks).toEqual([7,9,11]);expect(project(records)[0].weeks).toEqual([1,3,5]);
 });
 it('allows different targets for different weeks, then restores selected weeks only',()=>{
  const source=original();let records=updateSchoolAdjustments([],term,source,[5,7],change,table);
  records=updateSchoolAdjustments(records,term,source,[7],{...change,day:6},table);
  expect(project(records).filter(c=>c.locallyAdjusted).map(c=>[c.day,c.weeks])).toEqual([[4,[5]],[6,[7]]]);
  records=updateSchoolAdjustments(records,term,source,[5],{...change,day:source.day,room:source.room,startPeriod:1,endPeriod:2},table);
  expect(project(records)[0].weeks).toContain(5);expect(project(records).find(c=>c.locallyAdjusted)?.weeks).toEqual([7]);
 });
 it('survives refresh and changed cache IDs, but never leaks to another term',()=>{
  const records=updateSchoolAdjustments([],term,original(),[5],change,table),refreshed={...original(),id:'replacement',courseId:'new-id'};
  expect(project(records,[refreshed]).find(c=>c.locallyAdjusted)?.day).toBe(4);
  expect(applySchoolAdjustments([refreshed],'2025-12',records,table)).toEqual([{...refreshed,adjustmentSourceKey:schoolCourseKey(refreshed)}]);
 });
 it('pauses an old override when the school changes the original room/time',()=>{
  const records=updateSchoolAdjustments([],term,original(),[5],change,table),refreshed={...original(),room:'老师最新教室'};
  expect(project(records,[refreshed])).toHaveLength(1);expect(project(records,[refreshed])[0].room).toBe('老师最新教室');
  expect(inactiveAdjustmentCount([refreshed],term,records,table)).toBe(1);
 });
 it('ignores removed weeks and ambiguous duplicate originals',()=>{
  const records=updateSchoolAdjustments([],term,original(),[5],change,table);
  expect(project(records,[{...original(),weeks:[1,3]}]).some(c=>c.locallyAdjusted)).toBe(false);
  expect(project(records,[original(),{...original(),id:'duplicate'}]).some(c=>c.locallyAdjusted)).toBe(false);
 });
 it('rejects empty, duplicate and nonexistent weeks or invalid time ranges',()=>{
  for(const weeks of [[],[5,5],[2]])expect(()=>updateSchoolAdjustments([],term,original(),weeks,change,table)).toThrow();
  for(const bad of [{day:8},{startPeriod:14},{timeMode:'custom',start:'11:00',end:'10:00'},{timeMode:'custom',start:'25:00'}])expect(()=>updateSchoolAdjustments([],term,original(),[5],{...change,...bad} as CourseTimeChange,table)).toThrow();
 });
 it('detects real overlapping lessons, while adjacent time or another week is allowed',()=>{
  const changed=project(updateSchoolAdjustments([],term,original(),[5],change,table));
  const other={...original(),id:'other',name:'另一个课程',day:4,start:'15:00',end:'16:00',weeks:[5]};
  expect(adjustmentConflicts([...changed,other],schoolCourseKey(original()),[5])).toEqual(['另一个课程']);
  expect(adjustmentConflicts([...changed,{...other,weeks:[7]}],schoolCourseKey(original()),[5])).toEqual([]);
  expect(adjustmentConflicts([...changed,{...other,start:'15:55'}],schoolCourseKey(original()),[5])).toEqual([]);
 });
 it('updates agenda dates without leaving the original occurrence behind',()=>{
  const semester={...defaultState().semesters[0],weekStartDate:'2026-09-14',weekCount:18};
  const courses=project(updateSchoolAdjustments([],term,original(),[5],change,table));
  const events=buildAgenda([{semester,courses,source:'school'}],[],[],'2026-10-12',7).events;
  expect(events.map(e=>[e.date,e.time,e.location,e.course?.occurrenceWeek])).toEqual([['2026-10-15','14:30–15:55','新教室',5]]);
 });
 it('preserves custom times when school periods change and validates persisted records',()=>{
  const records=updateSchoolAdjustments([],term,original(),[5],{...change,timeMode:'custom',start:'13:12',end:'14:13'},table);
  expect(project(records)[1]).toMatchObject({start:'13:12',end:'14:13',startPeriod:null});
  expect(validateSchoolAdjustments(JSON.parse(JSON.stringify(records)))).toEqual(records);
  expect(()=>validateSchoolAdjustments([...records,...records])).toThrow();
 });
});
