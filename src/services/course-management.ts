import {
  validateCourse,
  validateState,
  collisions,
  type ScheduleState,
  type ManagedCourse,
} from "../domain/schedule";
/** Runs inside the serialized store transaction, rechecking conflicts against the latest snapshot. */
export function upsertCourse(
  state: ScheduleState,
  course: ManagedCourse,
  allowConflicts = false,
) {
  const term = state.semesters.find((t) => t.id === course.semesterId);
  if (!term) throw Error("课程所属学期不存在");
  validateCourse(course, term);
  const proposed = validateState({
    ...state,
    courses: [...state.courses.filter((c) => c.id !== course.id), course],
  });
  const saved = proposed.courses.find((c) => c.id === course.id)!;
  const issues = collisions(saved, proposed.courses);
  if (issues.some((i) => i.kind === "duplicate"))
    throw Error("存在完全重复的上课安排");
  if (issues.length && !allowConflicts)
    throw Error("时间冲突：" + issues.map((i) => i.message).join("；"));
  Object.assign(state, proposed, { mode: "personal" });
}
