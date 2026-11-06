import type {Course,Exam} from './academic';
import type {Semester} from './schedule';
export interface CampusTask {id:string;title:string;course:string;deadline:string|null;notes:string;completed:boolean;remindMinutes:number|null;createdAt:string;updatedAt:string}
export interface TaskSnapshot {version:1;tasks:CampusTask[];notificationsEnabled:boolean;updatedAt:string}
export interface CourseSeries {semester:Semester;courses:Course[];source:'school'|'personal'}
export interface AgendaEvent {id:string;kind:'course'|'exam'|'task';title:string;date:string;time:string;startAt:number|null;endAt:number|null;location:string;source:string;completed:boolean;taskId?:string;course?:Course}
export const emptyTasks=():TaskSnapshot=>({version:1,tasks:[],notificationsEnabled:false,updatedAt:new Date().toISOString()});
export function beijingDay(now=new Date()){const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now).map(p=>[p.type,p.value]));return `${parts.year}-${parts.month}-${parts.day}`}
export function validDay(value:string){if(!/^20\d{2}-\d{2}-\d{2}$/.test(value))return false;const d=new Date(value+'T00:00:00Z');return !Number.isNaN(+d)&&d.toISOString().slice(0,10)===value}
export function beijingTimestamp(value:string){const [day,time]=value.split('T');if(!validDay(day)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(time||''))throw Error('请填写有效的北京时间');return +new Date(`${day}T${time}:00+08:00`)}
export function shiftDay(day:string,offset:number){if(!validDay(day)||!Number.isInteger(offset))throw Error('日期无效');return new Date(+new Date(day+'T00:00:00Z')+offset*86400000).toISOString().slice(0,10)}
const bounded=(v:unknown,max:number)=>{if(typeof v!=='string'||v.length>max)throw Error('待办内容或格式无效');return v.trim()};
export function validateTask(value:unknown):CampusTask {
 const r=value as CampusTask;if(!r||typeof r.completed!=='boolean')throw Error('待办格式无效');
 const id=bounded(r.id,100),title=bounded(r.title,100),course=bounded(r.course,100),notes=bounded(r.notes,1000);if(!id||!title)throw Error('请填写待办标题');
 if(r.deadline!==null){if(typeof r.deadline!=='string')throw Error('截止时间无效');beijingTimestamp(r.deadline)}
 if(r.remindMinutes!==null&&![0,5,10,30,60,1440].includes(r.remindMinutes))throw Error('提醒时间无效');
 for(const key of ['createdAt','updatedAt'] as const)if(typeof r[key]!=='string'||Number.isNaN(Date.parse(r[key])))throw Error('待办时间戳无效');
 return {id,title,course,notes,deadline:r.deadline,completed:r.completed,remindMinutes:r.deadline?r.remindMinutes:null,createdAt:r.createdAt,updatedAt:r.updatedAt};
}
export function validateTaskSnapshot(value:unknown):TaskSnapshot {
 const r=value as TaskSnapshot;if(!r||r.version!==1||typeof r.notificationsEnabled!=='boolean'||!Array.isArray(r.tasks)||r.tasks.length>500||typeof r.updatedAt!=='string'||Number.isNaN(Date.parse(r.updatedAt)))throw Error('待办备份格式无法识别');
 const tasks=r.tasks.map(validateTask);if(new Set(tasks.map(t=>t.id)).size!==tasks.length)throw Error('待办编号重复');return {version:1,tasks,notificationsEnabled:r.notificationsEnabled,updatedAt:r.updatedAt};
}
export function mergeTaskBackup(current:TaskSnapshot,backup:unknown){const incoming=validateTaskSnapshot(backup),ids=new Set(current.tasks.map(t=>t.id));return validateTaskSnapshot({...current,tasks:[...current.tasks,...incoming.tasks.filter(t=>!ids.has(t.id))]})}
export function taskReminderPlan(snapshot:TaskSnapshot,now=new Date()){
 if(!snapshot.notificationsEnabled)return [];
 return snapshot.tasks.filter(t=>!t.completed&&t.deadline&&t.remindMinutes!==null).map(t=>({task:t,at:new Date(beijingTimestamp(t.deadline!)-t.remindMinutes!*60000)})).filter(t=>+t.at>+now).sort((a,b)=>+a.at-+b.at).slice(0,30).map((p,i)=>({id:410000+i,title:`待办提醒：${p.task.title}`,body:`${p.task.deadline!.replace('T',' ')} 截止${p.task.course?' · '+p.task.course:''}`,schedule:{at:p.at,allowWhileIdle:true},extra:{owner:'handan-task',taskId:p.task.id}}));
}
export function buildAgenda(series:CourseSeries[],exams:Exam[],tasks:CampusTask[],from:string,days=7,now=new Date()){
 if(!validDay(from)||!Number.isInteger(days)||days<1||days>31)throw Error('日程日期范围无效');const to=shiftDay(from,days),events:AgendaEvent[]=[],seen=new Set<string>();
 const add=(e:AgendaEvent)=>{if(e.date>=from&&e.date<to&&!seen.has(e.id)){events.push(e);seen.add(e.id)}};
 for(const s of series)for(const c of s.courses)for(const week of c.weeks){if(!Number.isInteger(week)||week<1||week>s.semester.weekCount||c.day<1||c.day>7||!validDay(s.semester.weekStartDate))continue;const day=shiftDay(s.semester.weekStartDate,(week-1)*7+c.day-1);let startAt:number,endAt:number;try{startAt=beijingTimestamp(day+'T'+c.start);endAt=beijingTimestamp(day+'T'+c.end);if(endAt<=startAt)continue}catch{continue}add({id:`${s.source}/${s.semester.id}/${c.id}/${day}/${c.start}`,kind:'course',title:c.name,date:day,time:`${c.start}–${c.end}`,startAt,endAt,location:c.room,source:s.source==='school'?'学校课表缓存':'个人课表',completed:false,course:c})}
 let unknownExams=0;
 for(const [i,e] of exams.entries()){
  if(typeof e.date!=='string'||typeof e.time!=='string'){unknownExams++;continue}const date=e.date.replaceAll('/','-');if(!validDay(date)){unknownExams++;continue}
  const match=e.time.trim().match(/^([0-2]\d:[0-5]\d)\s*[-–—~至]\s*([0-2]\d:[0-5]\d)$/);let startAt:number|null=null,endAt:number|null=null;
  if(match)try{startAt=beijingTimestamp(date+'T'+match[1]);endAt=beijingTimestamp(date+'T'+match[2]);if(endAt<=startAt){startAt=null;endAt=null}}catch{startAt=null;endAt=null}
  add({id:`exam/${e.name}/${date}/${e.time}/${e.room}`,kind:'exam',title:e.name,date,time:e.time||'时间待学校发布',startAt,endAt,location:e.room,source:'学校考试缓存',completed:false});
 }
 for(const t of tasks){if(!t.deadline)continue;const at=beijingTimestamp(t.deadline);add({id:'task/'+t.id,kind:'task',title:t.title,date:t.deadline.slice(0,10),time:t.deadline.slice(11)+' 截止',startAt:at,endAt:at,location:t.course,source:'个人待办',completed:t.completed,taskId:t.id})}
 events.sort((a,b)=>a.date.localeCompare(b.date)||(a.startAt??Infinity)-(b.startAt??Infinity)||a.id.localeCompare(b.id));
 return {events,unknownExams,overdue:tasks.filter(t=>!t.completed&&t.deadline&&t.deadline.slice(0,10)<from&&beijingTimestamp(t.deadline)<+now),undated:tasks.filter(t=>!t.deadline)};
}
