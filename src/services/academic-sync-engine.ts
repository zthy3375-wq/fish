import {validateSchoolAdjustments,type SchoolCourseAdjustment} from '../domain/school-course-adjustments';
import {normalizeGrade} from '../domain/grade-analysis';
import {uid,validateCourse,validateSemester,validateTimeTable, type Semester,type ManagedCourse,type TimeTable} from '../domain/schedule';
import {handanTimeTable} from '../domain/handan-time-table';
import {previewZhengfangTimetable,parseZhengfangWeeks} from './academic-adapters/zhengfang-timetable';
import type {HandanAcademicClient,NativeAcademicResult,SchoolTerm,SchoolProfile,SchoolGrade,SchoolExam,SessionState,SchoolTimetable} from './handan-academic-client';
export interface CachedModule<T> {data:T|null;updatedAt:string|null;error:string|null;scope?:'all'|'term'|'unknown'}
export interface SchoolTermCache {term:SchoolTerm;semester:Semester;table:TimeTable;courses:ManagedCourse[];practice:SchoolTimetable['practice']}
export interface AcademicCache {
 localScope?:string;courseAdjustments?:SchoolCourseAdjustment[];
 version:1;connected:boolean;session:SessionState;selectedTerm:string|null;lastError:string|null;
 terms:Record<string,CachedModule<SchoolTermCache>>;semesters:CachedModule<SchoolTerm[]>;
 profile:CachedModule<SchoolProfile>;grades:CachedModule<SchoolGrade[]>;exams:CachedModule<SchoolExam[]>;
 examsByTerm?:Record<string,CachedModule<SchoolExam[]>>;
}
export const emptyModule=<T>():CachedModule<T>=>({data:null,updatedAt:null,error:null});
export const emptyAcademicCache=():AcademicCache=>({version:1,connected:false,session:'disconnected',selectedTerm:null,lastError:null,terms:{},semesters:emptyModule(),profile:emptyModule(),grades:emptyModule(),exams:emptyModule()});
export const termKey=(t:SchoolTerm)=>`${t.xnm}-${t.xqm}`;
export function validTerm(t:SchoolTerm){if(!t||!/^20\d{2}$/.test(t.xnm)||!['3','12'].includes(t.xqm))throw Error('TERM');return t}
const messages:Record<string,string>={LIVE_EMPTY:'已自动加载学校课表页面，但未识别到完整课程，请反馈此提示',LIVE_SPECIAL:'学校课表含特殊实践安排，需要补充适配，未保存部分课表',EMPTY:'学校本次未返回课程，保留上次课表',TERM:'未能确认学校当前学期',SCHEMA:'学校数据格式需要适配',NETWORK:'学校网络暂不可用',TIMETABLE_JSON:'课表查询未返回课程 JSON（成绩连接正常时仍可能是课表请求参数问题）',COURSE_FIELDS:'课表已返回，但课程的星期、节次或周次字段尚不兼容',WEEKS:'课表教学周表达式尚不兼容',PERIODS:'课表节次超出可用作息范围',LOCAL_SCHEMA:'课表返回成功，本机课程转换尚不兼容',HTTP:'学校请求未成功，尚未取得课表',EXPIRED:'登录已过期，请重新连接',LIMIT:'学校返回的数据超过处理范围'};
export const schoolError=(code?:string)=>messages[code||'']||'同步未完成，保留上次数据';
function normalizeTimetable(value:unknown,calendar:Semester[],previous?:SchoolTermCache|null):SchoolTermCache {
 const t=value as SchoolTimetable;validTerm(t.term);if(!Array.isArray(t.kbList)||!Array.isArray(t.practice)||t.practice.length>500)throw Error('SCHEMA');
 let table=handanTimeTable();if(t.periods){table={id:'handan-server-periods',name:'学校作息',slots:t.periods};validateTimeTable(table)}
 const key=termKey(t.term),year=Number(t.term.xnm),season=t.term.xqm==='3'?'秋季':'春季';
 // Reuse the existing local calendar. This date is configuration, never claimed as school API data.
 const existing=calendar.find(s=>s.academicYear.replace(/[–—]/g,'-')===`${year}-${year+1}`&&s.season===season)??calendar[0];
 if(!existing)throw Error('TERM');
 let maxWeek=existing.weekCount;
 for(const item of t.kbList){const value=(item as {zcd?:unknown})?.zcd;if(typeof value==='string')for(const n of value.normalize("NFKC").match(/\d+/g)||[]){const week=Number(n);if(week>=1&&week<=40)maxWeek=Math.max(maxWeek,week)}}
 const semester:Semester={...existing,weekCount:maxWeek,id:`handan-${key}`,academicYear:existing.academicYear.replace(/[–—]/g,'-')===`${year}-${year+1}`?existing.academicYear:`${year}–${year+1}`,season,timeTableId:table.id};
 const preview=previewZhengfangTimetable({kbList:t.kbList},{semester,timeTable:table,existing:[],sourceTerm:t.term}).preview;
 if(preview.errors.length){const errors=preview.errors.join(' ');throw Error(/教学周|周次|单双周/.test(errors)?'WEEKS':/节次/.test(errors)?'PERIODS':'LOCAL_SCHEMA')}if(!preview.courses.length&&!t.practice.length)throw Error('EMPTY');
 // School conflicts are real arrangements; preserve and let the existing grid render overlap.
 const courses=preview.courses.map(c=>{
  const old=previous?.courses.find(p=>p.name===c.name&&p.teacher===c.teacher);
  const next={...c,id:old?.id??`school-${uid()}`,semesterId:semester.id,arrangements:c.arrangements.map(a=>{
   const prior=old?.arrangements.find(p=>p.day===a.day&&p.startPeriod===a.startPeriod&&p.endPeriod===a.endPeriod&&p.room===a.room);
   return {...a,id:prior?.id??a.id};
  })};validateCourse(next,semester);return next;
 });
 const practice=t.practice.map(p=>{if(typeof p.name!=='string'||!p.name||p.name.length>150)throw Error('SCHEMA');return {name:p.name,teacher:typeof p.teacher==='string'?p.teacher.slice(0,150):'',weeks:typeof p.weeks==='string'?p.weeks.slice(0,250):''}});
 return {term:t.term,semester,table,courses,practice};
}
function validateArray<T>(raw:unknown,validate:(r:any)=>boolean):T[]{if(!Array.isArray(raw)||raw.length>2000||raw.some(r=>!r||!validate(r)))throw Error('SCHEMA');return raw as T[]}
export function applyAcademicResult(cache:AcademicCache,result:NativeAcademicResult,calendar:Semester[],requestedTerm?:SchoolTerm):AcademicCache {
 const next=structuredClone(cache);next.session=result.session;next.lastError=result.modules?.timetable?null:cache.lastError;
 next.examsByTerm??={};
 // Migrate the existing snapshot once; future responses always carry a verified term.
 if(cache.selectedTerm&&!next.examsByTerm[cache.selectedTerm]&&cache.exams.data!==null)next.examsByTerm[cache.selectedTerm]=structuredClone(cache.exams);
 let examKey:string|undefined;
 try {const term=result.resolvedTerm??(result.modules?.timetable?.data as SchoolTimetable|undefined)?.term??requestedTerm;if(term)examKey=termKey(validTerm(term))}catch{/* Unknown scope must not replace an exam snapshot. */}
 if(result.session==='valid'){next.connected=true;next.localScope??=uid();}
 for(const [name,module] of Object.entries(result.modules||{})){
  let target:CachedModule<any>|undefined;
  if(name==='timetable'){
   const raw=module.data as SchoolTimetable|undefined;
   let key=next.selectedTerm;
   try{if(raw?.term)key=termKey(validTerm(raw.term))}catch{next.lastError=schoolError('TERM');continue;}
   if(!key){next.lastError=module.code==='HTTP'?`学校${module.stage==='page'?'课表页面':'数据查询'}请求返回 HTTP ${module.httpStatus??'错误'}，尚未取得课程`:schoolError(module.code);continue;}
   target=next.terms[key]??=emptyModule<SchoolTermCache>();
   if(module.status==='ok'){
    try{target.data=normalizeTimetable(raw,calendar,target.data);target.updatedAt=new Date().toISOString();target.error=null;next.selectedTerm=key}
    catch(e){
     const code=(e as Error).message;target.error=schoolError(code);
     if(code==='WEEKS'&&Array.isArray(raw?.kbList)){
      const examples:string[]=[];
      for(const row of raw.kbList){const v=(row as {zcd?:unknown})?.zcd;if(typeof v!=='string')continue;
       try{parseZhengfangWeeks(v,40)}catch{
        const safe=v.normalize('NFKC').replace(/[\s\u200b-\u200d\ufeff]/g,'');
        if(safe.length<=80&&/^[0-9第周单双至到,、;()\[\]{}~～—–−/\-]+$/.test(safe)&&!examples.includes(safe))examples.push(safe);
       }
       if(examples.length===3)break;
      }
      if(examples.length)target.error+='（周次格式：'+examples.join('；')+'）';
     }
     next.lastError=target.error;
    }
   }else {target.error=schoolError(module.code);next.lastError=target.error;}
   continue;
  }
  if(!['profile','semesters','grades','exams'].includes(name))continue;
  target=next[name as 'profile'];
  if(name==='exams'){
   if(!examKey){const error='未能确认考试所属学期，保留上次记录';next.exams.error=error;if(next.selectedTerm&&next.examsByTerm[next.selectedTerm])next.examsByTerm[next.selectedTerm].error=error;continue;}
   target=next.examsByTerm[examKey]??=emptyModule<SchoolExam[]>();
  }
  if(module.status!=='ok'){target.error=schoolError(module.code);continue}
  try{
   let data:unknown=module.data;
   if(name==='semesters')data=validateArray<SchoolTerm>(data,r=>{try{validTerm(r);return true}catch{return false}});
   if(name==='grades'){
    if(module.scope==='term'&&target.scope==='all'&&target.data?.length)throw Error('GRADE_SCOPE');
    if(!Array.isArray(data)||data.length>2000)throw Error('SCHEMA');
    data=data.map(normalizeGrade);
    if(!(data as SchoolGrade[]).length&&target.data?.length)throw Error('EMPTY');
   }
   if(name==='exams')data=validateArray<SchoolExam>(data,r=>['name','date','time','room','seat'].every(k=>typeof r[k]==='string'&&r[k].length<=150));
   if(name==='profile'){
    const p=data as SchoolProfile;if(!p||!['name','major','className','year'].every(k=>typeof p[k as keyof SchoolProfile]==='string'&&p[k as keyof SchoolProfile].length<=150))throw Error('SCHEMA');
    data={name:p.name,major:p.major,className:p.className,year:p.year};
   }
   if(name==='exams')data=(data as SchoolExam[]).map(({name,date,time,room,seat})=>({name,date,time,room,seat}));
   if(name==='grades')target.scope=module.scope??'unknown';
   target.data=data;target.updatedAt=new Date().toISOString();target.error=null;
  }catch(e){target.error=(e as Error).message==='EMPTY'?'学校返回空成绩，保留上次记录':(e as Error).message==='GRADE_SCOPE'?'仅收到单学期成绩，保留历年缓存':schoolError('SCHEMA')}
 }
 if(next.selectedTerm){
  const scoped=next.examsByTerm[next.selectedTerm];
  if(scoped)next.exams=structuredClone(scoped);
  else if(next.selectedTerm!==cache.selectedTerm)next.exams={...emptyModule<SchoolExam[]>(),error:'当前学期考试尚未更新'};
 }
 return next;
}
export function validateAcademicCache(raw:unknown):AcademicCache {
 const c=raw as AcademicCache;if(!c||c.version!==1||!c.terms||typeof c.connected!=='boolean'||Object.keys(c.terms).length>100)throw Error('学校缓存无法识别');
 for(const v of Object.values(c.terms)){if(v.data){validTerm(v.data.term);validateSemester(v.data.semester);validateTimeTable(v.data.table);if(!Array.isArray(v.data.courses)||v.data.courses.length>500)throw Error('学校缓存无法识别')}}
 if(c.connected)c.localScope??=uid();
 if(c.courseAdjustments)c.courseAdjustments=validateSchoolAdjustments(c.courseAdjustments);
 return c;
}
export class AcademicSyncEngine {
 private running:Promise<void>|null=null;private generation=0;
 private writes:Promise<void>=Promise.resolve();private loggingOut:Promise<void>|null=null;
 constructor(private client:HandanAcademicClient,private read:()=>AcademicCache,private commit:(c:AcademicCache)=>Promise<void>,private calendar:()=>Semester[]){}
 private save(cache:AcademicCache,token:number){
  const write=this.writes.catch(()=>{}).then(async()=>{if(token===this.generation){const latest=this.read();if(cache.localScope&&cache.localScope===latest.localScope)cache.courseAdjustments=latest.courseAdjustments;await this.commit(cache)}});
  this.writes=write;return write;
 }
 /** Local edits share the same storage queue as sync and logout. */
 updateCourseAdjustments(scope:string,term:string,mutate:(cache:AcademicCache)=>void):Promise<void>{
  const token=this.generation;
  const job=this.writes.catch(()=>{}).then(async()=>{
   const next=structuredClone(this.read());
   if(token!==this.generation||!scope||next.localScope!==scope||next.selectedTerm!==term||!next.connected)throw Error('学校账号或学期已变化，请返回课表重新打开');
   mutate(next);if(next.courseAdjustments)validateSchoolAdjustments(next.courseAdjustments);
   await this.commit(next);
  });
  this.writes=job;return job;
 }
 sync(term?:SchoolTerm,login=false):Promise<void>{
  if(this.loggingOut)return this.loggingOut.then(()=>this.sync(term,login));
  if(this.running)return this.running;
  const token=this.generation;
  const job=(async()=>{
   try{
    const response=login?await this.client.login():await (this.client.getTimetable?.(term)??this.client.syncAll(term));
    if(token!==this.generation)return;
    // A successful new interactive login starts a new account scope. Cancel/failure preserves prior cache.
    const base=login&&response.session==='valid'?emptyAcademicCache():this.read();
    const next=applyAcademicResult(base,response,this.calendar(),term);
    if(!response.modules?.timetable&&next.selectedTerm&&next.terms[next.selectedTerm])next.terms[next.selectedTerm].error=schoolError('SCHEMA');
    await this.save(next,token);
    if(response.session==='valid'&&!login){
     // Commit timetable before records. A slow/failed records module cannot hold the P1 path hostage.
     for(const name of ['grades','exams'] as const){
      if(token!==this.generation)return;
      const query=name==='grades'?this.client.getGrades:this.client.getExams;
      if(!query)continue;
      let r:NativeAcademicResult;
      const queryTerm=name==='grades'?undefined:term??response.resolvedTerm??(response.modules?.timetable?.data as SchoolTimetable|undefined)?.term;
      try{r=await query.call(this.client,queryTerm)}catch{r={session:this.read().session,modules:{[name]:{status:'error',code:'NETWORK'}}}}
      if(token!==this.generation)return;
      await this.save(applyAcademicResult(this.read(),r,this.calendar(),queryTerm),token);
      if(r.session==='expired')break;
     }
    }
   }catch(e){
    if(token===this.generation){const next=structuredClone(this.read());if((e as {code?:string}).code!=='CANCELLED'){
     next.session='unknown';next.lastError=schoolError('NETWORK');if(next.selectedTerm&&next.terms[next.selectedTerm])next.terms[next.selectedTerm].error=schoolError('NETWORK');await this.save(next,token);
    }}throw e;
   }
  })();
  const tracked=job.finally(()=>{if(this.running===tracked)this.running=null});this.running=tracked;return tracked;
 }
 logout():Promise<void>{
  if(this.loggingOut)return this.loggingOut;
  const token=++this.generation;this.running=null;
  const task=(async()=>{await this.client.logout();await this.save(emptyAcademicCache(),token)})();
  const tracked=task.finally(()=>{if(this.loggingOut===tracked)this.loggingOut=null});this.loggingOut=tracked;return tracked;
 }
}
