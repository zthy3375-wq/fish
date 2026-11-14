import {flatten} from '../domain/schedule';
import {applySchoolAdjustments,schoolCourseKey,updateSchoolAdjustments,adjustmentConflicts,inactiveAdjustmentCount,type CourseTimeChange} from '../domain/school-course-adjustments';
import {isSchoolPageSemester} from '../services/legacy-school-semester';
import {computed,ref,toRaw} from 'vue';
import {Preferences} from '@capacitor/preferences';
import {AcademicSyncEngine,emptyAcademicCache,validateAcademicCache,termKey,type AcademicCache} from '../services/academic-sync-engine';
import {handanAcademicClient,schoolConnectionSupported,type SchoolTerm} from '../services/handan-academic-client';
import {schedule} from './schedule';
const KEY='handan.academic.cache.v050';
export const academicCache=ref<AcademicCache>(emptyAcademicCache());
export const academicBusy=ref(false),academicError=ref('');
export const schoolTerm=computed(()=>academicCache.value.selectedTerm?academicCache.value.terms[academicCache.value.selectedTerm!]:null);
export const originalSchoolCourses=computed(()=>{const s=schoolTerm.value?.data;return s?flatten(s.courses,s.semester.id,s.table):[]});
export const schoolCourses=computed(()=>{const s=schoolTerm.value?.data;return s?applySchoolAdjustments(originalSchoolCourses.value,academicCache.value.selectedTerm!,academicCache.value.courseAdjustments??[],s.table):[]});
export const pausedCourseAdjustments=computed(()=>{const s=schoolTerm.value?.data;return s?inactiveAdjustmentCount(originalSchoolCourses.value,academicCache.value.selectedTerm!,academicCache.value.courseAdjustments??[],s.table):0});
export function saveSchoolCourseAdjustment(scope:string,term:string,key:string,weeks:number[],change:CourseTimeChange,allowConflicts=false){
 return engine.updateCourseAdjustments(scope,term,cache=>{
  const s=cache.terms[term]?.data;if(!s)throw Error('学校课表已更新，请重新打开');
  const originals=flatten(s.courses,s.semester.id,s.table),matches=originals.filter(c=>schoolCourseKey(c)===key);
  if(matches.length!==1)throw Error('学校原安排已变化或存在重复，请同步后重新核对');
  const records=updateSchoolAdjustments(cache.courseAdjustments??[],term,matches[0],weeks,change,s.table);
  const personal=schedule.value.courses.filter(c=>{const t=schedule.value.semesters.find(t=>t.id===c.semesterId);return !isSchoolPageSemester(c.semesterId)&&t?.academicYear.replace(/[–—]/g,'-')===s.semester.academicYear.replace(/[–—]/g,'-')&&t?.season===s.semester.season});
  const projected=[...applySchoolAdjustments(originals,term,records,s.table),...personal.flatMap(c=>flatten([c],c.semesterId,s.table))];
  const conflicts=adjustmentConflicts(projected,key,weeks);
  if(conflicts.length&&!allowConflicts)throw Error('时间与'+conflicts.join('、')+'重叠，请核对后确认保留');
  cache.courseAdjustments=records;
 });
}
export function restoreSchoolCourseAdjustment(scope:string,term:string,key:string){return engine.updateCourseAdjustments(scope,term,cache=>{cache.courseAdjustments=(cache.courseAdjustments??[]).filter(a=>a.term!==term||a.sourceKey!==key)})}
async function commit(c:AcademicCache){await Preferences.set({key:KEY,value:JSON.stringify(c)});academicCache.value=c}
const engine=new AcademicSyncEngine(handanAcademicClient,()=>structuredClone(toRaw(academicCache.value)),commit,()=>schedule.value.semesters);
let initialized=false,lastAuto=0;
export async function initAcademic(){if(initialized)return;try{const {value}=await Preferences.get({key:KEY});if(value)academicCache.value=validateAcademicCache(JSON.parse(value));initialized=true}catch{academicError.value='无法读取学校缓存，个人课表仍可使用'}}
export async function syncAcademic(login=false,term?:SchoolTerm){
 if(!schoolConnectionSupported()){academicError.value='学校连接仅支持 Android 客户端';return}
 if(academicBusy.value)return;
 academicBusy.value=true;academicError.value='';
 try{await engine.sync(term,login);lastAuto=Date.now();if(academicCache.value.session==='expired')academicError.value='学校登录已过期，请重新连接'}
 catch(e){if((e as {code?:string}).code!=='CANCELLED')academicError.value='学校连接未完成，已保留上次数据'}finally{academicBusy.value=false;if(login&&academicCache.value.connected)setTimeout(()=>void syncAcademic(),0)}
}
export function autoSyncAcademic(){if(academicCache.value.connected&&Date.now()-lastAuto>120000)return syncAcademic()}
export async function disconnectAcademic(){if(academicBusy.value)return;try{await engine.logout();academicError.value=''}catch{academicError.value='退出未完成，请重试'}}
export async function selectSchoolTerm(t:SchoolTerm){if(academicBusy.value)return;const key=termKey(t);if(academicCache.value.terms[key]?.data)await commit({...toRaw(academicCache.value),selectedTerm:key,exams:academicCache.value.examsByTerm?.[key]??{data:null,updatedAt:null,error:'当前学期考试尚未更新'}});await syncAcademic(false,t)}
