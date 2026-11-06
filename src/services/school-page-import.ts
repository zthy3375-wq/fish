import { uid, validateState, type ScheduleState } from "../domain/schedule";
import type { ZhengfangPreview } from "./academic-adapters/zhengfang-timetable";
/** Deliberate user-confirmed import into a NEW semester partition, never an automatic sync or replacement. */
export function saveSchoolPagePreview(
  state: ScheduleState,
  result: ZhengfangPreview,
  confirmed: boolean,
) {
  if (!confirmed) throw Error("请核对学校网页、学期和作息后再保存");
  if (result.preview.errors.length || !result.preview.courses.length)
    throw Error("存在解析错误或没有可保存的课程");
  if (result.preview.issues.length)
    throw Error("存在时间冲突，请先核对；本次未保存");
  const id = "school-page-" + uid();
  const semester = { ...result.semester, id, timeTableId: result.timeTable.id };
  const next = validateState({
    ...state,
    timeTables: state.timeTables.some(t=>t.id===result.timeTable.id)?state.timeTables:[...state.timeTables,result.timeTable],
    mode: "personal",
    activeSemesterId: id,
    semesters: [...state.semesters, semester],
    courses: [
      ...state.courses,
      ...result.preview.courses.map((c) => ({
        ...c,
        id: uid(),
        semesterId: id,
      })),
    ],
  });
  Object.assign(state, next);
  return id;
}
export function isSchoolPageSemester(id: string) {
  return id.startsWith("school-page-");
}

/** Update only the bound school partition; content keys preserve IDs without relying on row order. */
export function refreshSchoolPage(state:ScheduleState,result:ZhengfangPreview){
  const target=state.semesters.find(s=>s.id===state.activeSemesterId&&isSchoolPageSemester(s.id));
  if(!target)return saveSchoolPagePreview(state,result,true);
  if(target.academicYear!==result.semester.academicYear||target.season!==result.semester.season)throw Error('学期变化，请先确认新学期');
  if(result.preview.errors.length||result.preview.issues.length||!result.preview.courses.length)throw Error('课表不完整，保留上次课程');
  const old=state.courses.filter(c=>c.semesterId===target.id);
  const nextCourses=result.preview.courses.map(c=>{
    const previous=old.find(p=>p.name===c.name&&p.teacher===c.teacher);
    return {...c,id:previous?.id??uid(),semesterId:target.id,arrangements:c.arrangements.map(a=>{
      const p=previous?.arrangements.find(b=>b.day===a.day&&b.startPeriod===a.startPeriod&&b.endPeriod===a.endPeriod&&b.room===a.room);
      return {...a,id:p?.id??a.id};
    })};
  });
  const next=validateState({...state,timeTables:[...state.timeTables.filter(t=>t.id!==result.timeTable.id),result.timeTable],
    semesters:state.semesters.map(s=>s.id===target.id?{...s,timeTableId:result.timeTable.id}:s),
    courses:[...state.courses.filter(c=>c.semesterId!==target.id),...nextCourses]});
  Object.assign(state,next);return target.id;
}
