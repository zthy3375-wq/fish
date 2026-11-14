import {beforeEach,it,expect,vi} from 'vitest';
import {toRaw} from 'vue';
const disk=vi.hoisted(()=>({value:'',fail:false}));
vi.mock('@capacitor/preferences',()=>({Preferences:{get:async()=>({value:disk.value}),set:async({value}:{value:string})=>{if(disk.fail)throw Error('DISK');disk.value=value}}}));
import {academicCache,originalSchoolCourses,schoolCourses,saveSchoolCourseAdjustment,restoreSchoolCourseAdjustment} from '../src/composables/handan-academic';
import {applyAcademicResult,emptyAcademicCache} from '../src/services/academic-sync-engine';
import {schedule} from '../src/composables/schedule';
import {defaultState,arrangementFromCell} from '../src/domain/schedule';
import {schoolCourseKey,type CourseTimeChange} from '../src/domain/school-course-adjustments';
const target:CourseTimeChange={day:2,room:'调课教室',start:'09:45',end:'11:10',startPeriod:3,endPeriod:4,timeMode:'period'};
beforeEach(()=>{
 disk.fail=false;schedule.value=defaultState();
 academicCache.value=applyAcademicResult(emptyAcademicCache(),{session:'valid',modules:{timetable:{status:'ok',data:{term:{xnm:'2026',xqm:'3'},kbList:[{kcmc:'合成课程',xm:'教师',cdmc:'原教室',xqj:'1',jcs:'1-2',zcd:'1-18周'}],practice:[]}}}},schedule.value.semesters);
 disk.value=JSON.stringify(academicCache.value);
});
it('persists an edit before publishing it and restores every affected week without changing school source',async()=>{
 const scope=academicCache.value.localScope!,term=academicCache.value.selectedTerm!,key=schoolCourseKey(originalSchoolCourses.value[0]);
 const original=JSON.stringify(academicCache.value.terms);
 await saveSchoolCourseAdjustment(scope,term,key,[5,6],target);
 expect(JSON.parse(disk.value).courseAdjustments.map((a:{week:number})=>a.week)).toEqual([5,6]);
 expect(schoolCourses.value.find(c=>c.locallyAdjusted)).toMatchObject({day:2,weeks:[5,6],room:'调课教室'});
 expect(JSON.stringify(academicCache.value.terms)).toBe(original);
 await restoreSchoolCourseAdjustment(scope,term,key);
 expect(schoolCourses.value).toHaveLength(1);expect(schoolCourses.value[0].day).toBe(1);
 expect(JSON.parse(disk.value).courseAdjustments).toEqual([]);
});
it('checks conflicts against personal lessons in the same academic term before allowing a confirmed save',async()=>{
 const scope=academicCache.value.localScope!,term=academicCache.value.selectedTerm!,data=academicCache.value.terms[term].data!,key=schoolCourseKey(originalSchoolCourses.value[0]);
 const semester=schedule.value.semesters[0];semester.academicYear=data.semester.academicYear;semester.season=data.semester.season;
 const arrangement=arrangementFromCell(data.table,semester.weekCount,{day:2,period:3,week:5});
 Object.assign(arrangement,{startPeriod:3,endPeriod:4,rule:'custom',startWeek:5,endWeek:5,customWeeks:[5]});
 schedule.value.courses=[{id:'personal-conflict',semesterId:semester.id,name:'个人冲突课程',teacher:'',notes:'',color:'blue',arrangements:[arrangement]}];
 await expect(saveSchoolCourseAdjustment(scope,term,key,[5],target)).rejects.toThrow('个人冲突课程');
 expect(academicCache.value.courseAdjustments).toBeUndefined();
 await saveSchoolCourseAdjustment(scope,term,key,[5],target,true);
 expect(schoolCourses.value.some(c=>c.locallyAdjusted)).toBe(true);
});
it('failed storage and stale account editors never publish or persist a new adjustment',async()=>{
 const scope=academicCache.value.localScope!,term=academicCache.value.selectedTerm!,key=schoolCourseKey(originalSchoolCourses.value[0]),before=structuredClone(toRaw(academicCache.value)),stored=disk.value;
 disk.fail=true;await expect(saveSchoolCourseAdjustment(scope,term,key,[5],target)).rejects.toThrow('DISK');
 expect(toRaw(academicCache.value)).toEqual(before);expect(disk.value).toBe(stored);
 disk.fail=false;academicCache.value.localScope='another-account';
 await expect(saveSchoolCourseAdjustment(scope,term,key,[5],target)).rejects.toThrow('账号或学期');
 expect(disk.value).toBe(stored);
});
