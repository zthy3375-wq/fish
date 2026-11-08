import type { Course } from "./academic";
import { teachingWeek } from "./academic";
export type WeekRule = "all" | "odd" | "even" | "custom";
export interface TimeSlot {
  number: number;
  start: string;
  end: string;
}
export interface TimeTable {
  id: string;
  name: string;
  slots: TimeSlot[];
}
export interface Semester {
  timeTableId?: string;
  id: string;
  academicYear: string;
  season: "春季" | "秋季";
  startDate: string;
  weekStartDate: string;
  weekCount: number;
}
export interface Arrangement {
  timeMode?: "custom" | "period";
  id: string;
  day: number;
  startPeriod: number | null;
  endPeriod: number | null;
  start: string;
  end: string;
  room: string;
  startWeek: number;
  endWeek: number;
  rule: WeekRule;
  customWeeks: number[];
}
export interface ManagedCourse {
  id: string;
  semesterId: string;
  name: string;
  teacher: string;
  color: string;
  notes: string;
  arrangements: Arrangement[];
}
export interface ScheduleState {
  version: 2;
  timeTables: TimeTable[];
  mode: "demo" | "personal";
  activeSemesterId: string;
  semesters: Semester[];
  courses: ManagedCourse[];
  reminders: { enabled: boolean; minutes: number };
  updatedAt: string;
}
export const colors = ["blue", "purple", "green", "orange"];
export function uid() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const h = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
export function parseDate(s: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw Error("日期格式应为 YYYY-MM-DD");
  const d = new Date(s + "T00:00:00");
  if (
    Number.isNaN(+d) ||
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` !==
      s
  )
    throw Error("日期不存在");
  return d;
}
export function standardTimeTable(id = "standard-45"): TimeTable {
  return {
    id,
    name: "45 分钟 · 示例作息",
    slots: [
      ["08:00", "08:45"],
      ["08:50", "09:35"],
      ["10:00", "10:45"],
      ["10:50", "11:35"],
      ["14:00", "14:45"],
      ["14:50", "15:35"],
      ["16:00", "16:45"],
      ["16:50", "17:35"],
      ["19:00", "19:45"],
      ["19:50", "20:35"],
      ["20:45", "21:30"],
      ["21:35", "22:20"],
    ].map(([start, end], i) => ({ number: i + 1, start, end })),
  };
}
export function defaultState(): ScheduleState {
  return {
    version: 2,
    timeTables: [standardTimeTable()],
    mode: "demo",
    activeSemesterId: "term-2026-autumn",
    semesters: [
      {
        id: "term-2026-autumn",
        academicYear: "2026–2027",
        season: "秋季",
        startDate: "2026-09-07",
        weekStartDate: "2026-09-07",
        weekCount: 18,
        timeTableId: "standard-45",
      },
    ],
    courses: [],
    reminders: { enabled: false, minutes: 10 },
    updatedAt: new Date().toISOString(),
  };
}
export const validClock = (s: unknown): s is string =>
  typeof s === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(s);
export function validateTimeTable(t: TimeTable) {
  if (
    !t ||
    !text(t.id, 100) ||
    !t.id ||
    !text(t.name, 60) ||
    !t.name.trim() ||
    !Array.isArray(t.slots) ||
    !t.slots.length ||
    t.slots.length > 24
  )
    throw Error("作息方案需有名称和 1–24 节课");
  let end = "";
  for (const [i, slot] of t.slots.entries()) {
    if (
      slot.number !== i + 1 ||
      !validClock(slot.start) ||
      !validClock(slot.end) ||
      slot.end <= slot.start ||
      slot.start < end
    )
      throw Error("作息节次必须连续编号、按时间排序且不能重叠");
    end = slot.end;
  }
}
export function periodTimes(
  table: TimeTable,
  start: number | null,
  end: number | null,
) {
  const first = table.slots.find((s) => s.number === start),
    last = table.slots.find((s) => s.number === end);
  if (!first || !last || start! > end!)
    throw Error("所选作息方案中不存在这些节次，请先调整课程");
  return { start: first.start, end: last.end };
}
export function resolveArrangement(
  a: Arrangement,
  table?: TimeTable,
): Arrangement {
  return a.timeMode === "period" && table
    ? { ...a, ...periodTimes(table, a.startPeriod, a.endPeriod) }
    : a;
}
export function tableForSemester(
  state: ScheduleState,
  id = state.activeSemesterId,
) {
  const term = state.semesters.find((s) => s.id === id);
  return state.timeTables.find((t) => t.id === term?.timeTableId)!;
}
export interface CellPreset {
  day: number;
  period: number;
  week: number;
}
export function arrangementFromCell(
  table: TimeTable,
  weeks: number,
  preset?: CellPreset,
): Arrangement {
  const n = preset?.period ?? 1;
  return {
    ...newArrangement(weeks),
    day: preset?.day ?? 1,
    startPeriod: n,
    endPeriod: n,
    ...periodTimes(table, n, n),
    timeMode: "period",
  };
}
export function semesterWeek(date: Date, s: Semester) {
  return teachingWeek(date, parseDate(s.weekStartDate));
}
export function semesterDate(s: Semester, week: number, day: number) {
  const d = parseDate(s.weekStartDate);
  d.setDate(d.getDate() + (week - 1) * 7 + day - 1);
  return d;
}
export function activeWeeks(a: Arrangement) {
  return Array.from(
    { length: Math.max(0, a.endWeek - a.startWeek + 1) },
    (_, i) => i + a.startWeek,
  ).filter(
    (w) =>
      a.rule === "all" ||
      (a.rule === "odd" && w % 2 === 1) ||
      (a.rule === "even" && w % 2 === 0) ||
      (a.rule === "custom" && a.customWeeks.includes(w)),
  );
}
function integer(v: unknown, min: number, max: number) {
  return typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;
}
const text = (v: unknown, max: number) =>
  typeof v === "string" && v.length <= max;
export function validateSemester(s: Semester) {
  if (
    !s ||
    !text(s.id, 100) ||
    !s.id ||
    !text(s.academicYear, 30) ||
    !s.academicYear.trim() ||
    !["春季", "秋季"].includes(s.season) ||
    !integer(s.weekCount, 1, 40)
  )
    throw Error("学期信息不完整，教学周应为 1–40");
  parseDate(s.startDate);
  if (parseDate(s.weekStartDate).getDay() !== 1)
    throw Error("第一教学周必须从星期一开始");
}
export function validateCourse(c: ManagedCourse, s: Semester) {
  if (
    !c ||
    !text(c.id, 100) ||
    !c.id ||
    c.semesterId !== s.id ||
    !text(c.name, 150) ||
    !c.name.trim() ||
    !text(c.teacher, 100) ||
    !text(c.notes, 2000) ||
    !colors.includes(c.color) ||
    !Array.isArray(c.arrangements) ||
    !c.arrangements.length ||
    c.arrangements.length > 100
  )
    throw Error("课程名称必填，且至少保留一个上课安排");
  const ids = new Set<string>();
  for (const a of c.arrangements) {
    if (
      !a ||
      !text(a.id, 100) ||
      !a.id ||
      ids.has(a.id) ||
      !integer(a.day, 1, 7) ||
      !text(a.room, 150)
    )
      throw Error("星期、地点或安排编号无效");
    ids.add(a.id);
    if (
      !/^([01]\d|2[0-3]):[0-5]\d$/.test(a.start) ||
      !/^([01]\d|2[0-3]):[0-5]\d$/.test(a.end) ||
      a.end <= a.start
    )
      throw Error("结束时间必须晚于开始时间，时间格式为 HH:mm");
    if (
      (a.startPeriod !== null || a.endPeriod !== null) &&
      (!integer(a.startPeriod, 1, 24) ||
        !integer(a.endPeriod, 1, 24) ||
        a.endPeriod! < a.startPeriod!)
    )
      throw Error("节次范围应在 1–24 之间");
    if (
      !integer(a.startWeek, 1, s.weekCount) ||
      !integer(a.endWeek, a.startWeek, s.weekCount) ||
      !["all", "odd", "even", "custom"].includes(a.rule) ||
      !Array.isArray(a.customWeeks) ||
      a.customWeeks.some((w) => !integer(w, a.startWeek, a.endWeek)) ||
      !activeWeeks(a).length
    )
      throw Error("教学周范围或单双周设置无效");
  }
}
export function validateState(raw: unknown): ScheduleState {
  const x = raw as ScheduleState;
  if (!x || ![1, 2].includes(x.version)) throw Error("不支持的课表备份版本");
  if (
    !["demo", "personal"].includes(x.mode) ||
    !Array.isArray(x.semesters) ||
    !x.semesters.length ||
    x.semesters.length > 30 ||
    !Array.isArray(x.courses) ||
    x.courses.length > 3000 ||
    !x.reminders ||
    typeof x.reminders.enabled !== "boolean" ||
    !integer(x.reminders.minutes, 1, 120)
  )
    throw Error("课表数据库结构无效");
  const legacy = Number(x.version) === 1;
  const timeTables: TimeTable[] = legacy
    ? x.semesters.map((_, i) => standardTimeTable("legacy-times-" + (i + 1)))
    : x.timeTables;
  if (
    !Array.isArray(timeTables) ||
    !timeTables.length ||
    timeTables.length > 60
  )
    throw Error("作息方案数据无效");
  const tableIds = new Set<string>();
  for (const t of timeTables) {
    validateTimeTable(t);
    if (tableIds.has(t.id)) throw Error("作息方案编号重复");
    tableIds.add(t.id);
  }
  const terms = new Map<string, Semester>();
  const semesters = x.semesters.map((s, i) => {
    validateSemester(s);
    if (terms.has(s.id)) throw Error("学期编号重复");
    const term = {
      id: s.id,
      academicYear: s.academicYear,
      season: s.season,
      startDate: s.startDate,
      weekStartDate: s.weekStartDate,
      weekCount: s.weekCount,
      timeTableId: legacy ? timeTables[i].id : s.timeTableId,
    };
    if (!term.timeTableId || !tableIds.has(term.timeTableId))
      throw Error("学期关联的作息方案不存在");
    terms.set(s.id, term);
    return term;
  });
  if (!terms.has(x.activeSemesterId)) throw Error("当前学期不存在");
  const ids = new Set<string>();
  const courses = x.courses.map((c) => {
    const term = terms.get(c.semesterId);
    if (!term || ids.has(c.id)) throw Error("课程所属学期不存在或编号重复");
    ids.add(c.id);
    validateCourse(c, term);
    const table = timeTables.find((t) => t.id === term.timeTableId)!;
    const course = {
      id: c.id,
      semesterId: c.semesterId,
      name: c.name,
      teacher: c.teacher,
      color: c.color,
      notes: c.notes,
      arrangements: c.arrangements.map((a) => {
        if (
          !legacy &&
          a.timeMode !== undefined &&
          !["custom", "period"].includes(a.timeMode)
        )
          throw Error("课程时间模式无效");
        const clean: Arrangement = {
          id: a.id,
          day: a.day,
          startPeriod: a.startPeriod,
          endPeriod: a.endPeriod,
          start: a.start,
          end: a.end,
          room: a.room,
          startWeek: a.startWeek,
          endWeek: a.endWeek,
          rule: a.rule,
          customWeeks: [...a.customWeeks],
          timeMode: legacy ? "custom" : (a.timeMode ?? "custom"),
        };
        return resolveArrangement(clean, table);
      }),
    };
    validateCourse(course, term);
    return course;
  });
  return {
    version: 2,
    timeTables: timeTables.map((t) => ({
      id: t.id,
      name: t.name,
      slots: t.slots.map((s) => ({
        number: s.number,
        start: s.start,
        end: s.end,
      })),
    })),
    mode: x.mode,
    activeSemesterId: x.activeSemesterId,
    semesters,
    courses,
    reminders: { enabled: x.reminders.enabled, minutes: x.reminders.minutes },
    updatedAt:
      typeof x.updatedAt === "string" ? x.updatedAt : new Date().toISOString(),
  };
}
export function flatten(
  courses: ManagedCourse[],
  semesterId: string,
  table?: TimeTable,
): Course[] {
  return courses
    .filter((c) => c.semesterId === semesterId)
    .flatMap((c) =>
      c.arrangements.map((raw) => {
        const a = resolveArrangement(raw, table);
        return {
          id: `${c.id}/${a.id}`,
          courseId: c.id,
          arrangementId: a.id,
          semesterId,
          name: c.name,
          teacher: c.teacher,
          notes: c.notes,
          color: c.color,
          room: a.room,
          day: a.day,
          start: a.start,
          end: a.end,
          period:
            a.startPeriod === null
              ? "未指定节次"
              : `${a.startPeriod}–${a.endPeriod} 节`,
          weeks: activeWeeks(a),
          startPeriod: a.startPeriod,
          endPeriod: a.endPeriod,
          timeMode: a.timeMode ?? "custom",
        };
      }),
    );
}
export interface Collision {
  kind: "duplicate" | "conflict";
  message: string;
}
export function collisions(
  candidate: ManagedCourse,
  courses: ManagedCourse[],
): Collision[] {
  const found: Collision[] = [];
  const all = [...courses.filter((c) => c.id !== candidate.id), candidate];
  for (let i = 0; i < candidate.arrangements.length; i++) {
    const a = candidate.arrangements[i];
    for (const c of all) {
      if (c.semesterId !== candidate.semesterId) continue;
      for (let j = 0; j < c.arrangements.length; j++) {
        if (c.id === candidate.id && j >= i) continue;
        const b = c.arrangements[j];
        if (
          a.day !== b.day ||
          a.start >= b.end ||
          b.start >= a.end ||
          !activeWeeks(a).some((w) => activeWeeks(b).includes(w))
        )
          continue;
        const duplicate =
          c.name.trim() === candidate.name.trim() &&
          c.teacher.trim() === candidate.teacher.trim() &&
          a.start === b.start &&
          a.end === b.end &&
          a.room === b.room &&
          JSON.stringify(activeWeeks(a)) === JSON.stringify(activeWeeks(b));
        found.push({
          kind: duplicate ? "duplicate" : "conflict",
          message: `${candidate.name} 与 ${c.name}：周${a.day} ${a.start}–${a.end} 教学周重叠`,
        });
      }
    }
  }
  return found;
}
export function newArrangement(weeks: number): Arrangement {
  return {
    timeMode: "custom",
    id: uid(),
    day: 1,
    startPeriod: 1,
    endPeriod: 2,
    start: "08:00",
    end: "09:35",
    room: "",
    startWeek: 1,
    endWeek: weeks,
    rule: "all",
    customWeeks: [],
  };
}
export function backup(state: ScheduleState) {
  return JSON.stringify(
    {
      format: "handan-campus-schedule",
      exportedAt: new Date().toISOString(),
      data: state,
    },
    null,
    2,
  );
}
export function restoreBackup(input: string) {
  const x = JSON.parse(input);
  if (x.format !== "handan-campus-schedule")
    throw Error("不是邯院通课表备份");
  return validateState(x.data);
}
