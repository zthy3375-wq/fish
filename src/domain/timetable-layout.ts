import type { Course } from "./academic";
import type { TimeTable, TimeSlot } from "./schedule";
export const minute = (s: string) =>
  Number(s.slice(0, 2)) * 60 + Number(s.slice(3));
export interface AxisSegment {
  start: number;
  end: number;
  from: number;
  to: number;
  slot?: TimeSlot;
}
export interface TimeAxis {
  segments: AxisSegment[];
  units: number;
}
/** Each teaching period is one unit; breaks stay visible but compress to at most .35 units. */
export function buildTimeAxis(
  table: TimeTable,
  courses: Course[] = [],
): TimeAxis {
  const slots = table.slots,
    segments: AxisSegment[] = [];
  let unit = 0;
  const add = (start: number, end: number, span: number, slot?: TimeSlot) => {
    if (end > start) {
      segments.push({ start, end, from: unit, to: unit + span, slot });
      unit += span;
    }
  };
  const first = Math.min(
    minute(slots[0].start),
    ...courses.map((c) => minute(c.start)),
  );
  if (first < minute(slots[0].start))
    add(first, minute(slots[0].start), (minute(slots[0].start) - first) / 45);
  for (const [i, slot] of slots.entries()) {
    if (i) {
      const previous = minute(slots[i - 1].end);
      const next = minute(slot.start);
      const occupied = courses.some(
        (c) =>
          (minute(c.start) >= previous && minute(c.start) < next) ||
          (minute(c.end) > previous && minute(c.end) <= next),
      );
      add(
        previous,
        next,
        occupied
          ? (next - previous) / 45
          : Math.min((next - previous) / 45, 0.35),
      );
    }
    add(minute(slot.start), minute(slot.end), 1, slot);
  }
  const end = Math.max(
    minute(slots.at(-1)!.end),
    ...courses.map((c) => minute(c.end)),
  );
  if (end > minute(slots.at(-1)!.end))
    add(minute(slots.at(-1)!.end), end, (end - minute(slots.at(-1)!.end)) / 45);
  return { segments, units: unit };
}
export function timePosition(axis: TimeAxis, time: string) {
  const value = minute(time);
  for (const s of axis.segments)
    if (value >= s.start && value <= s.end)
      return s.from + ((value - s.start) / (s.end - s.start)) * (s.to - s.from);
  return value < axis.segments[0].start ? 0 : axis.units;
}
export interface PositionedCourse {
  course: Course;
  top: number;
  bottom: number;
  lane: number;
  lanes: number;
}
export interface CourseCluster {
  day: number;
  top: number;
  bottom: number;
  items: PositionedCourse[];
}
/** Connected overlap groups expose every course; touching endpoints never conflict. */
export function layoutWeek(
  courses: Course[],
  week: number,
  axis: TimeAxis,
): CourseCluster[] {
  const result: CourseCluster[] = [];
  for (let day = 1; day <= 7; day++) {
    const items = courses
      .filter((c) => c.day === day && c.weeks.includes(week))
      .sort(
        (a, b) =>
          a.start.localeCompare(b.start) ||
          a.end.localeCompare(b.end) ||
          a.id.localeCompare(b.id),
      );
    let cluster: CourseCluster | undefined;
    let end = "";
    for (const c of items) {
      if (!cluster || c.start >= end) {
        cluster = {
          day,
          top: timePosition(axis, c.start),
          bottom: timePosition(axis, c.end),
          items: [],
        };
        result.push(cluster);
        end = c.end;
      } else {
        end = end > c.end ? end : c.end;
        cluster.bottom = Math.max(cluster.bottom, timePosition(axis, c.end));
      }
      cluster.items.push({
        course: c,
        top: timePosition(axis, c.start),
        bottom: timePosition(axis, c.end),
        lane: 0,
        lanes: 1,
      });
    }
  }
  for (const cluster of result) {
    const ends: number[] = [];
    for (const item of cluster.items) {
      let lane = ends.findIndex((end) => end <= minute(item.course.start));
      if (lane < 0) lane = ends.length;
      ends[lane] = minute(item.course.end);
      item.lane = lane;
    }
    for (const item of cluster.items) item.lanes = ends.length;
  }
  return result;
}
export function coursePosition(axis: TimeAxis, course: Course) {
  return {
    top: timePosition(axis, course.start),
    height: timePosition(axis, course.end) - timePosition(axis, course.start),
  };
}
