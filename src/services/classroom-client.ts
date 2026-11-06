import {Capacitor} from '@capacitor/core';
import {handanNativeTransport} from './handan-academic-client';
import {isRoomDate,roomQueryKey,ROOM_TTL,type ClassroomOptions,type ClassroomQuery,type ClassroomResults,type ClassroomDay,type RoomPeriod} from '../domain/classrooms';
interface Reply {session:string;classrooms?:{status:string;data?:unknown;code?:string;updatedAt?:string}}
interface NativeRooms {getClassroomOptions(q:Record<string,unknown>):Promise<Reply>;getFreeClassrooms(q:ClassroomQuery):Promise<Reply>;getClassroomDay(q:Record<string,unknown>):Promise<Reply>}
const native=handanNativeTransport as unknown as NativeRooms;
export const classroomSupported=()=>Capacitor.getPlatform()==='android';
const errorMessages:Record<string,string>={EXPIRED:'学校会话已过期，请重新连接学校账号',FORBIDDEN:'学校暂未向当前账号开放教室查询',DATE:'日期与学校教学周不一致或超出开放范围，请重新选择',FILTER:'学校筛选项已变化，请重新加载',SCHEMA:'学校教室数据格式需要适配，本次结果未知',LIMIT:'学校返回数据超过安全处理范围，请缩小教学楼筛选',NETWORK:'学校网络暂不可用，本次空闲状态未知',HTTP:'学校服务暂不可用，本次空闲状态未知',CALENDAR:'未取得可靠的学校校历，不能推算空闲状态',BUSY:'教务同步仍在进行，请稍后查询'};
export class ClassroomError extends Error {constructor(public code:string){super(errorMessages[code]||'查询未完成，本次空闲状态未知')}}
function invalid():never{throw new ClassroomError('SCHEMA')}
const array=(v:unknown,max:number):any[]=>Array.isArray(v)&&v.length<=max?v:invalid();
const string=(v:unknown)=>typeof v==='string'&&v.length<=200?v:invalid();
const num=(v:unknown,a:number,b:number)=>typeof v==='number'&&Number.isInteger(v)&&v>=a&&v<=b?v:invalid();
function period(p:any):RoomPeriod{if(!p||!/^\d{2}:\d{2}$/.test(p.start)||!/^\d{2}:\d{2}$/.test(p.end)||p.end<=p.start)invalid();return {number:num(p.number,1,24),start:p.start,end:p.end}}
function option(o:any){return {id:string(o.id),name:string(o.name)}}
function options(v:any):ClassroomOptions{
 if(!v||!/^20\d{2}$/.test(v.term?.xnm)||!['3','12','16'].includes(v.term?.xqm))invalid();
 for(const field of ['weekStartDate','minDate','maxDate'])if(!isRoomDate(v[field]))invalid();
 const p=array(v.periods,24).map(period);if(!p.length||p.some((r,i)=>r.number!==i+1))invalid();
 return {...v,term:{xnm:v.term.xnm,xqm:v.term.xqm},campusId:string(v.campusId),terms:array(v.terms,150).map(option),campuses:array(v.campuses,100).map(option),buildings:array(v.buildings,300).map(option),periods:p,weeks:array(v.weeks,53).map(w=>num(w,1,53))};
}
function result(v:any,q:ClassroomQuery):ClassroomResults{
 if(!v||roomQueryKey(v.query)!==roomQueryKey(q))invalid();
 const rooms=array(v.rooms,5000).map(r=>{
  for(const key of ['id','termRoomId','number','name','buildingId','building','campus','type'])string(r[key]);
  if(!r.id||!r.name||r.capacity!==null&&(typeof r.capacity!=='number'||r.capacity<0))invalid();return r;
 });
 if(num(v.total,0,5000)!==rooms.length||new Set(rooms.map(r=>r.id)).size!==rooms.length)invalid();
 return {rooms,total:v.total,query:{...q},periods:array(v.periods,24).map(period)};
}
function day(v:any,id:string,date:string):ClassroomDay{
 if(v?.roomId!==id||v?.date!==date)invalid();
 const slots=array(v.slots,24).map(p=>{if(!['free','occupied','unknown'].includes(p.state))invalid();return {...period(p),state:p.state}});
 if(!slots.length||slots.some((s,i)=>s.number!==i+1))invalid();return {roomId:id,date,slots};
}
let epoch=0;
const pending=new Map<string,Promise<any>>();
const cache=new Map<string,{data:ClassroomResults;updatedAt:string}>();
export function clearClassroomCache(){epoch++;cache.clear();pending.clear()}
export function cachedClassrooms(q:ClassroomQuery){const c=cache.get(roomQueryKey(q));return c?{...c,expired:Date.now()-Date.parse(c.updatedAt)>=ROOM_TTL}:null}
async function invoke(task:()=>Promise<Reply>){
 if(!classroomSupported())throw new ClassroomError('UNSUPPORTED');
 for(let attempt=0;attempt<30;attempt++){
  try{const r=await task();if(r.session==='expired')throw new ClassroomError('EXPIRED');if(r.classrooms?.status!=='ok')throw new ClassroomError(r.classrooms?.code||'SCHEMA');return r.classrooms}
  catch(e){if((e as any).code==='BUSY'&&attempt<29){await new Promise(r=>setTimeout(r,1000));continue}if(e instanceof ClassroomError)throw e;throw new ClassroomError((e as any).code==='BUSY'?'BUSY':'NETWORK')}
 }
 throw new ClassroomError('BUSY');
}
function single<T>(key:string,task:()=>Promise<T>):Promise<T>{
 const existing=pending.get(key);if(existing)return existing;
 const scope=epoch;
 const p=task().then(value=>{if(scope!==epoch)throw new ClassroomError('EXPIRED');return value}).finally(()=>{if(pending.get(key)===p)pending.delete(key)});
 pending.set(key,p);return p;
}
export const classroomClient={
 options(q:Record<string,unknown>={}){return single('options/'+JSON.stringify(q),async()=>options((await invoke(()=>native.getClassroomOptions(q))).data))},
 query(q:ClassroomQuery){const key=roomQueryKey(q);return single(key,async()=>{const scope=epoch,r=await invoke(()=>native.getFreeClassrooms(q)),data=result(r.data,q);if(scope!==epoch)throw new ClassroomError('EXPIRED');const updatedAt=new Date().toISOString();if(cache.size>=6)cache.delete(cache.keys().next().value!);cache.set(key,{data,updatedAt});return {data,updatedAt}})},
 day(q:ClassroomQuery,roomId:string,roomName:string){return single('day/'+roomQueryKey(q)+'/'+roomId,async()=>day((await invoke(()=>native.getClassroomDay({...q,roomId,roomName}))).data,roomId,q.date))},
};
