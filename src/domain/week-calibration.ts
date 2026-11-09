import type {Semester} from './schedule';
export const calendarKey=(s:Semester)=>s.academicYear.replace(/[–—]/g,'-')+'/'+s.season;
export function firstMondayForWeek(today:Date,week:number){
 if(!Number.isInteger(week)||week<1||week>40||!Number.isFinite(+today))throw Error('请输入 1 至 40 的教学周');
 const d=new Date(Date.UTC(today.getFullYear(),today.getMonth(),today.getDate()));
 d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7)-(week-1)*7);
 return d.toISOString().slice(0,10);
}
export function validWeekMonday(value:unknown):value is string {
 if(typeof value!=='string'||!/^20\d\d-\d\d-\d\d$/.test(value))return false;
 const d=new Date(value+'T00:00:00Z');return Number.isFinite(+d)&&d.toISOString().slice(0,10)===value&&d.getUTCDay()===1;
}
/** Verified against the owner's 2026–2027 calendar PDF. Preserve custom start dates. */
export function correctLegacyCalendar(s:Semester):Semester {
 if(calendarKey(s)!=='2026-2027/秋季'||s.startDate!=='2026-09-07'||s.weekStartDate!=='2026-09-07')return s;
 return {...s,startDate:'2026-09-14',weekStartDate:'2026-09-14',weekCount:Math.max(19,s.weekCount)};
}
