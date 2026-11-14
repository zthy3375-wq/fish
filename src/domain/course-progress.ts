import type {Course} from './academic';

/** Progress for a course occurrence already selected for the campus-local day. */
export function courseProgress(course:Pick<Course,'start'|'end'>,now:Date){
 const minutes=(value:string)=>{
  if(!/^\d{2}:\d{2}$/.test(value))return NaN;
  const [h,m]=value.split(':').map(Number);
  return h<24&&m<60?h*60+m:NaN;
 };
 const start=minutes(course.start),end=minutes(course.end);
 const at=now.getHours()*60+now.getMinutes()+now.getSeconds()/60+now.getMilliseconds()/60000;
 if(!Number.isFinite(start)||!Number.isFinite(end)||!Number.isFinite(at)||end<=start)return {state:'invalid' as const,percent:0,elapsedMinutes:0,remainingMinutes:0};
 const elapsed=Math.min(end-start,Math.max(0,at-start));
 return {
  state:at>=end?'ended' as const:at>=start?'current' as const:'scheduled' as const,
  percent:elapsed/(end-start)*100,
  elapsedMinutes:Math.floor(elapsed),
  remainingMinutes:Math.ceil(Math.max(0,end-start-elapsed)),
 };
}
