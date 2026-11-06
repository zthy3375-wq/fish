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
