import {uid,validateCourse,validateSemester,validateTimeTable, type Semester,type ManagedCourse,type TimeTable} from '../domain/schedule';
import {handanTimeTable} from '../domain/handan-time-table';
import {previewZhengfangTimetable} from './academic-adapters/zhengfang-timetable';
import type {HandanAcademicClient,NativeAcademicResult,SchoolTerm,SchoolProfile,SchoolGrade,SchoolExam,SessionState,SchoolTimetable} from './handan-academic-client';
export interface CachedModule<T> {data:T|null;updatedAt:string|null;error:string|null}
export interface SchoolTermCache {term:SchoolTerm;semester:Semester;table:TimeTable;courses:ManagedCourse[];practice:SchoolTimetable['practice']}
export interface AcademicCache {
 version:1;connected:boolean;session:SessionState;selectedTerm:string|null;lastError:string|null;
 terms:Record<string,CachedModule<SchoolTermCache>>;semesters:CachedModule<SchoolTerm[]>;
 profile:CachedModule<SchoolProfile>;grades:CachedModule<SchoolGrade[]>;exams:CachedModule<SchoolExam[]>;
}
export const emptyModule=<T>():CachedModule<T>=>({data:null,updatedAt:null,error:null});
export const emptyAcademicCache=():AcademicCache=>({version:1,connected:false,session:'disconnected',selectedTerm:null,lastError:null,terms:{},semesters:emptyModule(),profile:emptyModule(),grades:emptyModule(),exams:emptyModule()});
export const termKey=(t:SchoolTerm)=>`${t.xnm}-${t.xqm}`;
export function validTerm(t:SchoolTerm){if(!t||!/^20\d{2}$/.test(t.xnm)||!['3','12'].includes(t.xqm))throw Error('TERM');return t}
const messages:Record<string,string>={EMPTY:'学校本次未返回课程，保留上次课表',TERM:'未能确认学校当前学期',SCHEMA:'学校数据格式需要适配',NETWORK:'学校网络暂不可用',HTTP:'学校服务暂不可用',EXPIRED:'登录已过期，请重新连接',LIMIT:'学校返回的数据超过处理范围'};
export const schoolError=(code?:string)=>messages[code||'']||'同步未完成，保留上次数据';
function normalizeTimetable(value:unknown,calendar:Semester[],previous?:SchoolTermCache|null):SchoolTermCache {
 const t=value as SchoolTimetable;validTerm(t.term);if(!Array.isArray(t.kbList)||!Array.isArray(t.practice)||t.practice.length>500)throw Error('SCHEMA');
 let table=handanTimeTable();if(t.periods){table={id:'handan-server-periods',name:'学校作息',slots:t.periods};validateTimeTable(table)}
 const key=termKey(t.term),year=Number(t.term.xnm),season=t.term.xqm==='3'?'秋季':'春季';
 // Reuse the existing local calendar. This date is configuration, never claimed as school API data.
 const existing=calendar.find(s=>s.academicYear.replace(/[–—]/g,'-')===`${year}-${year+1}`&&s.season===season)??calendar[0];
 if(!existing)throw Error('TERM');
 const semester:Semester={...existing,id:`handan-${key}`,academicYear:existing.academicYear.replace(/[–—]/g,'-')===`${year}-${year+1}`?existing.academicYear:`${year}–${year+1}`,season,timeTableId:table.id};
 const preview=previewZhengfangTimetable({kbList:t.kbList},{semester,timeTable:table,existing:[],sourceTerm:t.term}).preview;
 if(preview.errors.length)throw Error('SCHEMA');if(!preview.courses.length&&!t.practice.length)throw Error('EMPTY');
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
export function applyAcademicResult(cache:AcademicCache,result:NativeAcademicResult,calendar:Semester[]):AcademicCache {
 const next=structuredClone(cache);next.session=result.session;next.lastError=result.modules?.timetable?null:cache.lastError;
 if(result.session==='valid')next.connected=true;
 for(const [name,module] of Object.entries(result.modules||{})){
  let target:CachedModule<any>|undefined;
  if(name==='timetable'){
   const raw=module.data as SchoolTimetable|undefined;
   const key=raw?.term?termKey(validTerm(raw.term)):next.selectedTerm;
   if(!key){next.lastError=schoolError(module.code);continue;}
   target=next.terms[key]??=emptyModule<SchoolTermCache>();
   if(module.status==='ok'){
    try{target.data=normalizeTimetable(raw,calendar,target.data);target.updatedAt=new Date().toISOString();target.error=null;next.selectedTerm=key}
    catch(e){target.error=schoolError((e as Error).message);next.lastError=target.error}
   }else {target.error=schoolError(module.code);next.lastError=target.error;}
   continue;
  }
  if(!['profile','semesters','grades','exams'].includes(name))continue;
  target=next[name as 'profile'];
  if(module.status!=='ok'){target.error=schoolError(module.code);continue}
  try{
   let data:unknown=module.data;
   if(name==='semesters')data=validateArray<SchoolTerm>(data,r=>{try{validTerm(r);return true}catch{return false}});
   if(name==='grades')data=validateArray<SchoolGrade>(data,r=>typeof r.name==='string'&&r.name.length<=150&&typeof r.scoreText==='string'&&r.scoreText.length<=40&&(r.credit===null||Number.isFinite(r.credit))&&(r.gpa===null||Number.isFinite(r.gpa)));
   if(name==='exams')data=validateArray<SchoolExam>(data,r=>['name','date','time','room','seat'].every(k=>typeof r[k]==='string'&&r[k].length<=150));
   if(name==='profile'){
    const p=data as SchoolProfile;if(!p||!['name','major','className','year'].every(k=>typeof p[k as keyof SchoolProfile]==='string'&&p[k as keyof SchoolProfile].length<=150))throw Error('SCHEMA');
    data={name:p.name,major:p.major,className:p.className,year:p.year};
   }
   if(name==='grades')data=(data as SchoolGrade[]).map(({name,scoreText,credit,gpa,term,kind})=>({name,scoreText,credit,gpa,term,kind}));
   if(name==='exams')data=(data as SchoolExam[]).map(({name,date,time,room,seat})=>({name,date,time,room,seat}));
   target.data=data;target.updatedAt=new Date().toISOString();target.error=null;
  }catch{target.error=schoolError('SCHEMA')}
 }
 return next;
}
export function validateAcademicCache(raw:unknown):AcademicCache {
 const c=raw as AcademicCache;if(!c||c.version!==1||!c.terms||typeof c.connected!=='boolean'||Object.keys(c.terms).length>100)throw Error('学校缓存无法识别');
 for(const v of Object.values(c.terms)){if(v.data){validTerm(v.data.term);validateSemester(v.data.semester);validateTimeTable(v.data.table);if(!Array.isArray(v.data.courses)||v.data.courses.length>500)throw Error('学校缓存无法识别')}}
 return c;
}
export class AcademicSyncEngine {
 private running:Promise<void>|null=null;private generation=0;
 constructor(private client:HandanAcademicClient,private read:()=>AcademicCache,private commit:(c:AcademicCache)=>Promise<void>,private calendar:()=>Semester[]){}
 sync(term?:SchoolTerm,login=false):Promise<void>{
  if(this.running)return this.running;
  const token=this.generation;
  const job=(async()=>{
   try{
    const response=login?await this.client.login():await (this.client.getTimetable?.(term)??this.client.syncAll(term));
    if(token!==this.generation)return;
    // A successful new interactive login starts a new account scope. Cancel/failure preserves prior cache.
    const base=login&&response.session==='valid'?emptyAcademicCache():this.read();
    const next=applyAcademicResult(base,response,this.calendar());
    if(!response.modules?.timetable&&next.selectedTerm&&next.terms[next.selectedTerm])next.terms[next.selectedTerm].error=schoolError('SCHEMA');
    await this.commit(next);
    if(response.session==='valid'&&!login){
     // Commit timetable before records. A slow/failed records module cannot hold the P1 path hostage.
     for(const name of ['grades','exams'] as const){
      if(token!==this.generation)return;
      const query=name==='grades'?this.client.getGrades:this.client.getExams;
      if(!query)continue;
      let r:NativeAcademicResult;
      try{r=await query.call(this.client,term)}catch{r={session:this.read().session,modules:{[name]:{status:'error',code:'NETWORK'}}}}
      if(token!==this.generation)return;
      await this.commit(applyAcademicResult(this.read(),r,this.calendar()));
      if(r.session==='expired')break;
     }
    }
   }catch(e){
    if(token===this.generation){const next=structuredClone(this.read());if((e as {code?:string}).code!=='CANCELLED'){
     next.session='unknown';next.lastError=schoolError('NETWORK');if(next.selectedTerm)next.terms[next.selectedTerm].error=schoolError('NETWORK');await this.commit(next);
    }}throw e;
   }
  })();
  this.running=job.finally(()=>{this.running=null});return this.running;
 }
 async logout(){this.generation++;await this.client.logout();await this.commit(emptyAcademicCache())}
}
