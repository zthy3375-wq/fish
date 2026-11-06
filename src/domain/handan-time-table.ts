import type {TimeTable} from './schedule';
/** Transcribed from the student's supplied 邯郸学院上课时间表 image, 2026-11-06.
 * Not fetched from an official API; select explicitly and confirm against current school arrangements.
 */
export function handanTimeTable():TimeTable {
  return {id:'handan-40min-student-supplied',name:'邯郸学院 · 40分钟 · 13节（用户提供）',slots:[
    ['08:00','08:40'],['08:45','09:25'],['09:45','10:25'],['10:30','11:10'],['11:15','11:55'],
    ['14:30','15:10'],['15:15','15:55'],['16:15','16:55'],['17:00','17:40'],['17:45','18:25'],
    ['19:00','19:40'],['19:45','20:25'],['20:30','21:10'],
  ].map(([start,end],i)=>({number:i+1,start,end}))};
}
