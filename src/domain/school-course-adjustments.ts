import type { Course } from './academic';
import { periodTimes, type TimeTable } from './schedule';

export interface CourseTimeChange {
  day: number; room: string; start: string; end: string;
  startPeriod: number | null; endPeriod: number | null;
  timeMode: 'period' | 'custom';
}
export interface SchoolCourseAdjustment extends CourseTimeChange {
  term: string; sourceKey: string; week: number;
}
/** Identity excludes week ranges and random cache IDs, but includes the original place/time.
 * A changed official arrangement must be reviewed rather than silently overridden. */
export function schoolCourseKey(c: Course): string {
  return JSON.stringify([c.name, c.teacher, c.room, c.day, c.start, c.end, c.startPeriod ?? null, c.endPeriod ?? null]);
}
export function normalizeCourseTime(change: CourseTimeChange, table?: TimeTable): CourseTimeChange {
  const next: CourseTimeChange = { day: change.day, room: change.room.trim(), start: change.start, end: change.end, startPeriod: change.startPeriod, endPeriod: change.endPeriod, timeMode: change.timeMode };
  if (!Number.isInteger(next.day) || next.day < 1 || next.day > 7 || next.room.length > 150)
    throw Error('请检查星期和教室');
  if (!['period', 'custom'].includes(next.timeMode)) throw Error('请选择时间方式');
  if (next.timeMode === 'period') {
    if (!Number.isInteger(next.startPeriod) || !Number.isInteger(next.endPeriod) || next.startPeriod! < 1 || next.endPeriod! > 24 || next.startPeriod! > next.endPeriod!) throw Error('请检查上课节次');
    if (table) Object.assign(next, periodTimes(table, next.startPeriod, next.endPeriod));
  } else { next.startPeriod = null; next.endPeriod = null; }
  if (![next.start, next.end].every(t => /^([01]\d|2[0-3]):[0-5]\d$/.test(t)) || next.end <= next.start)
    throw Error('结束时间需晚于开始时间');
  return next;
}
export function validateSchoolAdjustments(value: unknown): SchoolCourseAdjustment[] {
  if (!Array.isArray(value) || value.length > 4000) throw Error('本地调课记录无法识别');
  const identities = new Set<string>();
  return value.map(a => {
    if (!a || typeof a.term !== 'string' || !/^20\d{2}-(3|12)$/.test(a.term) || typeof a.sourceKey !== 'string' || a.sourceKey.length > 2000 || !Number.isInteger(a.week) || a.week < 1 || a.week > 60 || typeof a.room !== 'string') throw Error('本地调课记录无法识别');
    const identity = JSON.stringify([a.term, a.sourceKey, a.week]);
    if (identities.has(identity)) throw Error('本地调课记录重复');
    identities.add(identity);
    return { ...normalizeCourseTime(a), term: a.term, sourceKey: a.sourceKey, week: a.week };
  });
}
export function applySchoolAdjustments(courses: Course[], term: string, adjustments: SchoolCourseAdjustment[], table: TimeTable): Course[] {
  const keys = courses.map(schoolCourseKey);
  return courses.flatMap((course, index) => {
    const key = keys[index];
    const records = keys.filter(k => k === key).length === 1
      ? adjustments.filter(a => a.term === term && a.sourceKey === key && course.weeks.includes(a.week)) : [];
    const groups = new Map<string, { change: CourseTimeChange; weeks: number[] }>();
    for (const record of records) {
      let change: CourseTimeChange;
      try { change = normalizeCourseTime(record, table); } catch { continue; }
      const groupKey = JSON.stringify([change.day, change.room, change.start, change.end, change.startPeriod, change.endPeriod, change.timeMode]);
      const group = groups.get(groupKey) ?? { change, weeks: [] };
      group.weeks.push(record.week); groups.set(groupKey, group);
    }
    const changedWeeks = [...groups.values()].flatMap(g => g.weeks);
    const remaining = course.weeks.filter(w => !changedWeeks.includes(w));
    const result: Course[] = remaining.length ? [{ ...course, weeks: remaining, adjustmentSourceKey: key }] : [];
    for (const { change, weeks } of groups.values()) {
      weeks.sort((a, b) => a - b);
      result.push({ ...course, ...change, weeks, id: `${course.id}/local-${weeks[0]}`, adjustmentSourceKey: key, locallyAdjusted: true,
        period: change.timeMode === 'period' ? `${change.startPeriod}–${change.endPeriod} 节` : '自定义时间' });
    }
    return result;
  });
}
export function updateSchoolAdjustments(records: SchoolCourseAdjustment[], term: string, source: Course, weeks: number[], change: CourseTimeChange, table: TimeTable): SchoolCourseAdjustment[] {
  if (!weeks.length || new Set(weeks).size !== weeks.length || weeks.some(w => !source.weeks.includes(w))) throw Error('请选择原课程实际有课的教学周');
  const value = normalizeCourseTime(change, table), sourceKey = schoolCourseKey(source);
  const remaining = records.filter(a => !(a.term === term && a.sourceKey === sourceKey && weeks.includes(a.week)));
  // Selecting the original time/place restores only the chosen weeks.
  const restored = value.day === source.day && value.room === source.room && value.start === source.start && value.end === source.end;
  return validateSchoolAdjustments([...remaining, ...(restored ? [] : weeks.map(week => ({ ...value, term, sourceKey, week })))]);
}
export function adjustmentConflicts(courses: Course[], sourceKey: string, weeks: number[]): string[] {
  const changed = courses.filter(c => c.adjustmentSourceKey === sourceKey && c.weeks.some(w => weeks.includes(w)));
  const names = new Set<string>();
  for (const a of changed) for (const b of courses) {
    if (a.id !== b.id && a.day === b.day && a.start < b.end && b.start < a.end && a.weeks.some(w => weeks.includes(w) && b.weeks.includes(w))) names.add(b.name);
  }
  return [...names];
}
export function inactiveAdjustmentCount(courses: Course[], term: string, records: SchoolCourseAdjustment[], table: TimeTable): number {
  return records.filter(a => a.term === term && (courses.filter(c => schoolCourseKey(c) === a.sourceKey && c.weeks.includes(a.week)).length !== 1 || (() => { try { normalizeCourseTime(a, table); return false; } catch { return true; } })())).length;
}
