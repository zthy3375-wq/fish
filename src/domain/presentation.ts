import type { Course } from './academic';
import { coursesForDay, teachingWeek } from './academic';
export const semesterStart = new Date(2026, 8, 7);
export const semesterWeeks = 18;
export const weekdays = ['一','二','三','四','五','六','日'];
export function campusNow() {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(new Date()).map(p=>[p.type,p.value]));
  return new Date(+p.year,+p.month-1,+p.day,+p.hour,+p.minute,+p.second);
}
export function dayNumber(date:Date) { return date.getDay() || 7; }
export function timeOf(date:Date) { return `${String(date.getHours()).padStart(2,'0')}:${String(date.getMinutes()).padStart(2,'0')}`; }
export function currentWeek(date:Date) {return teachingWeek(date,semesterStart)}
export function courseState(c:Course, now:Date, onToday=true) {
  if(!onToday)return 'scheduled';
  const time=timeOf(now);
  return time>=c.end?'ended':time>=c.start?'current':'scheduled';
}
export interface Occurrence {course:Course;date:Date;minutes:number;week:number}
export function nextOccurrence(courses:Course[], now:Date):Occurrence|undefined {
  const startWeek=currentWeek(now);
  // Bounded to the mock semester; never repeat expired sample classes indefinitely.
  for(let offset=0;offset<=semesterWeeks*7;offset++) {
    const date=new Date(now.getFullYear(),now.getMonth(),now.getDate()+offset);
    const week=currentWeek(date);
    if(week>semesterWeeks)break;
    if(week<1)continue;
    const course=coursesForDay(courses,dayNumber(date),week).find(c=>offset>0||c.start>timeOf(now));
    if(course){const [h,m]=course.start.split(':').map(Number);date.setHours(h,m,0,0);return {course,date,week,minutes:Math.ceil((date.getTime()-now.getTime())/60000)}}
  }
  return undefined;
}
export function untilLabel(minutes:number) {return minutes<60?`${minutes} 分钟后开始`:minutes<1440?`${Math.floor(minutes/60)} 小时${minutes%60?` ${minutes%60} 分钟`:''}后开始`:`${Math.floor(minutes/1440)} 天后开始`}
export function dateLabel(date:Date){return `${date.getMonth()+1}月${date.getDate()}日`}
export function upcomingExams<T extends {date:string}>(exams:T[],date:Date){const stamp=`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;return [...exams].filter(e=>e.date>=stamp).sort((a,b)=>a.date.localeCompare(b.date))}
