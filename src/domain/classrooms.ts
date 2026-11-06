export interface RoomOption {id:string;name:string}
export interface RoomPeriod {number:number;start:string;end:string}
export interface ClassroomOptions {
  term:{xnm:string;xqm:string};campusId:string;terms:RoomOption[];campuses:RoomOption[];buildings:RoomOption[];
  periods:RoomPeriod[];weeks:number[];weekStartDate:string;minDate:string;maxDate:string;
}
export interface ClassroomQuery {xnm:string;xqm:string;date:string;week:number;weekday:number;campusId:string;buildingId:string;startPeriod:number;endPeriod:number}
export interface Classroom {id:string;termRoomId:string;number:string;name:string;buildingId:string;building:string;campus:string;type:string;capacity:number|null}
export type RoomState='free'|'occupied'|'unknown';
export interface ClassroomResults {rooms:Classroom[];total:number;query:ClassroomQuery;periods:RoomPeriod[]}
export interface ClassroomDay {roomId:string;date:string;slots:(RoomPeriod&{state:RoomState})[]}
export const ROOM_TTL=5*60*1000;
export function isRoomDate(value:string){return /^20\d{2}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00:00Z'))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value}
export function schoolDate(now=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(now)}
export function schoolTime(now=new Date()){return new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(now)}
export function dateSelection(date:string,options:ClassroomOptions){
  if(!isRoomDate(date)||date<options.minDate||date>options.maxDate)throw Error('日期不在学校开放的本学期范围内');
  const days=Math.round((Date.parse(date+'T00:00:00Z')-Date.parse(options.weekStartDate+'T00:00:00Z'))/86400000);
  const week=Math.floor(days/7)+1,weekday=new Date(date+'T00:00:00Z').getUTCDay()||7;
  if(!options.weeks.includes(week))throw Error('学校未开放该教学周查询');
  return {week,weekday};
}
export function dateForWeek(week:number,weekday:number,options:ClassroomOptions){return new Date(Date.parse(options.weekStartDate+'T00:00:00Z')+((week-1)*7+weekday-1)*86400000).toISOString().slice(0,10)}
export function currentRoomPeriod(periods:RoomPeriod[],now=new Date()){
  const time=schoolTime(now);return periods.find(p=>p.start<=time&&time<p.end)?.number??null;
}
export function roomQueryKey(q:ClassroomQuery){return JSON.stringify([q.xnm,q.xqm,q.date,q.week,q.weekday,q.campusId,q.buildingId,q.startPeriod,q.endPeriod])}
export function freeRuns(slots:ClassroomDay['slots']){
  const runs:{start:number;end:number;count:number;startTime:string;endTime:string}[]=[];
  for(const p of slots){if(p.state!=='free')continue;const last=runs.at(-1);if(last&&last.end===p.number-1){last.end=p.number;last.count++;last.endTime=p.end}else runs.push({start:p.number,end:p.number,count:1,startTime:p.start,endTime:p.end})}
  return runs;
}
