import type {AcademicCache} from './academic-sync-engine';
import {schoolError} from './academic-sync-engine';
import type {LearningCache} from '../domain/learning';
const schoolCodes=['LIVE_EMPTY','LIVE_SPECIAL','EMPTY','TERM','SCHEMA','NETWORK','TIMETABLE_JSON','COURSE_FIELDS','WEEKS','PERIODS','LOCAL_SCHEMA','HTTP','EXPIRED','LIMIT'];
const learningCodes=new Set(['WORK_ENC','WORK_SCHEMA','AUTH','VERIFY','RATE_LIMIT','NETWORK','URL','REDIRECT','LIMIT','CANCELLED','COURSE_SELECTION','COURSES_SCHEMA','COURSES_PARTIAL','PARTIAL','ACCOUNT_CHANGED','EXAMS_SCHEMA','EXAMS_PARTIAL','NOTICES_SCHEMA']);
const stamp=(v:unknown)=>typeof v==='string'&&/^\d{4}-\d\d-\d\dT[\d:.]+Z$/.test(v)?v:null;
const session=(v:unknown)=>['valid','expired','unknown','disconnected'].includes(String(v))?v:'unknown';
const count=(v:unknown)=>Number.isInteger(v)&&Number(v)>=0&&Number(v)<=100000?Number(v):0;
function schoolFailure(error:unknown){
 if(typeof error!=='string'||!error)return null;
 const code=schoolCodes.find(c=>error===schoolError(c)||c==='WEEKS'&&error.startsWith(schoolError(c)+'（周次格式：'))||'UNKNOWN';
 const match=code==='WEEKS'?error.match(/（周次格式：([0-9第周单双至到,、;；()\[\]{}~～—–−/\-]{1,250})）$/):null;
 return {code,...(match?{weekFormats:match[1].split('；').slice(0,3)}:{})};
}
function learningCode(v:unknown){return typeof v==='string'&&(learningCodes.has(v)||/^HTTP_[45]\d{2}$/.test(v))?v:'UNKNOWN'}
export function buildFailureFeedback(academic:AcademicCache,learning:LearningCache,version:string,platform:string,now=new Date()){
 const numericKeys=['httpStatus','courseChannels','workRows','workLinks','workRejected','workEncInputs','workContainers','workFrames','workTaskHandlers'];
 const diagnostics:Record<string,number|string>={};
 for(const key of numericKeys)if(Number.isInteger(learning.diagnostics?.[key]))diagnostics[key]=count(learning.diagnostics[key]);
 const stage=learning.diagnostics?.stage;if(stage==='course-entry'||stage==='work-list')diagnostics.stage=stage;
 const outcomes:Record<string,number>={};
 for(const result of Object.values(learning.courseSync||{})){
  const key=result.status==='ok'?'ok':result.status==='partial'?'partial':learningCode(result.code);
  outcomes[key]=(outcomes[key]||0)+1;
 }
 const module=(v:{updatedAt:string|null;error:string|null;data:unknown})=>({hasCache:v.data!==null,updatedAt:stamp(v.updatedAt),failure:schoolFailure(v.error)});
 return {schema:1,app:'邯院通',version,exportedAt:now.toISOString(),platform:['android','web'].includes(platform)?platform:'unknown',
  privacy:'仅同步状态、数量、受控错误码和周次格式；不含账号、密码、登录凭证、课程名称或作业正文。',
  academic:{connected:academic.connected,session:session(academic.session),lastFailure:schoolFailure(academic.lastError),
   timetables:Object.values(academic.terms).slice(0,100).map(v=>({...module(v),courseCount:v.data?.courses?.length||0})),
   grades:module(academic.grades),exams:module(academic.exams),profile:module(academic.profile)},
  learning:{connected:learning.connected,session:session(learning.session),lastAttempt:stamp(learning.lastAttempt),updatedAt:stamp(learning.updatedAt),
   courseCount:learning.courses.length,selectedCount:learning.selectedCourses.length,taskCount:learning.items.length,
   progress:{planned:count(learning.plannedCount),processed:count(learning.completedCount),remaining:count(learning.remaining)},
   errorCodes:[...new Set(Object.values(learning.issues).map(learningCode))],courseResults:outcomes,diagnostics}}
}
