import { describe, it, expect } from "vitest";
import {
  buildTimeAxis,
  timePosition,
  layoutWeek,
  coursePosition,
} from "../src/domain/timetable-layout";
import {
  standardTimeTable,
  defaultState,
  newArrangement,
  arrangementFromCell,
  validateState,
  flatten,
  tableForSemester,
  backup,
  restoreBackup,
  type ManagedCourse,
} from "../src/domain/schedule";
import { upsertCourse } from "../src/services/course-management";
import type { Course } from "../src/domain/academic";
const table = standardTimeTable();
const make = (
  id: string,
  start = "08:00",
  end = "09:35",
  day = 1,
  weeks = [1],
): Course => ({
  id,
  name: "课程" + id,
  teacher: "教师",
  room: "A301",
  day,
  start,
  end,
  period: "1–2节",
  weeks,
  color: "blue",
});
describe("period geometry", () => {
  it("positions starts and spans all intervening teaching sections instead of grouping starts into rows", () => {
    const axis = buildTimeAxis(table);
    const short = coursePosition(axis, make("a", "08:00", "08:45"));
    const double = coursePosition(axis, make("b"));
    const four = coursePosition(axis, make("c", "08:00", "11:35"));
    expect(short).toEqual({ top: 0, height: 1 });
    expect(double.height).toBeCloseTo(2 + 5 / 45);
    expect(four.height).toBeCloseTo(4 + 10 / 45 + 0.35);
    expect(timePosition(axis, "10:00")).toBeCloseTo(2 + 5 / 45 + 0.35);
  });
  it("maps custom start/end times inside periods and breaks with fractional units", () => {
    const axis = buildTimeAxis(table);
    expect(timePosition(axis, "08:15")).toBeCloseTo(1 / 3);
    const p = coursePosition(axis, make("a", "08:15", "09:10"));
    expect(p.top).toBeCloseTo(1 / 3);
    expect(p.height).toBeGreaterThan(1);
    expect(timePosition(axis, "09:45")).toBeGreaterThan(
      timePosition(axis, "09:35"),
    );
    expect(timePosition(axis, "09:45")).toBeLessThan(
      timePosition(axis, "10:00"),
    );
  });
  it("includes courses outside the configured daily time range without clipping", () => {
    const c = make("early", "06:00", "07:00"),
      late = make("late", "22:30", "23:30");
    const axis = buildTimeAxis(table, [c, late]);
    expect(timePosition(axis, "06:00")).toBe(0);
    expect(timePosition(axis, "23:30")).toBe(axis.units);
    expect(timePosition(axis, "08:00")).toBeGreaterThan(0);
  });
  it("separates days and touching intervals; connected conflicts retain every course and stable lanes", () => {
    const axis = buildTimeAxis(table),
      a = make("a"),
      b = make("b", "08:30", "10:30"),
      c = make("c", "10:00", "11:35"),
      d = make("d", "11:35", "12:00"),
      e = make("e", "08:00", "09:35", 2);
    const layout = layoutWeek([e, d, c, b, a], 1, axis);
    expect(layout).toHaveLength(3);
    expect(layout[0].items.map((i) => i.course.id)).toEqual(["a", "b", "c"]);
    expect(layout[0].items.map((i) => i.lane)).toEqual([0, 1, 0]);
    expect(layout[0].items.map((i) => i.lanes)).toEqual([2, 2, 2]);
    expect(layout[1].items[0].course.id).toBe("d");
    expect(layout[2].day).toBe(2);
  });
  it("filters actual teaching weeks and returns empty layout when the week has no courses", () => {
    const axis = buildTimeAxis(table);
    expect(
      layoutWeek(
        [
          make("odd", "08:00", "09:35", 1, [1, 3, 5]),
          make("even", "08:00", "09:35", 1, [2, 4, 6]),
        ],
        2,
        axis,
      )[0].items[0].course.id,
    ).toBe("even");
    expect(
      layoutWeek([make("custom", "08:00", "09:35", 1, [2, 7])], 3, axis),
    ).toEqual([]);
  });
  it("supports customized non-45-minute school periods", () => {
    const custom = {
      ...table,
      slots: [
        { number: 1, start: "09:00", end: "09:50" },
        { number: 2, start: "10:00", end: "10:40" },
      ],
    };
    const axis = buildTimeAxis(custom);
    expect(timePosition(axis, "09:25")).toBe(0.5);
    expect(timePosition(axis, "10:20")).toBeCloseTo(1 + 10 / 45 + 0.5);
  });
});
describe("period-linked editing", () => {
  it("prefills the selected empty cell using its own timetable", () => {
    const a = arrangementFromCell(table, 18, { day: 4, period: 3, week: 8 });
    expect(a).toMatchObject({
      day: 4,
      startPeriod: 3,
      endPeriod: 3,
      start: "10:00",
      end: "10:45",
      timeMode: "period",
      startWeek: 1,
      endWeek: 18,
    });
  });
  it("atomically saves period changes and gives home/day/week the same resolved times", () => {
    const s = defaultState(),
      a = arrangementFromCell(table, 18, { day: 2, period: 3, week: 8 });
    a.endPeriod = 4;
    const c: ManagedCourse = {
      id: "course",
      semesterId: s.activeSemesterId,
      name: "新课程",
      teacher: "",
      color: "blue",
      notes: "",
      arrangements: [a],
    };
    upsertCourse(s, c);
    expect(s.mode).toBe("personal");
    expect(s.courses[0].arrangements[0].end).toBe("11:35");
    const flat = flatten(s.courses, s.activeSemesterId, tableForSemester(s));
    expect(flat[0].start).toBe("10:00");
    expect(flat[0].end).toBe("11:35");
  });
  it("rejects duplicates and conflicts unless conflict preservation was explicitly confirmed", () => {
    const s = defaultState(),
      a = arrangementFromCell(table, 18);
    const c: ManagedCourse = {
      id: "a",
      semesterId: s.activeSemesterId,
      name: "课程A",
      teacher: "",
      color: "blue",
      notes: "",
      arrangements: [a],
    };
    upsertCourse(s, c);
    expect(() => upsertCourse(s, { ...c, id: "copy" })).toThrow("重复");
    const other = { ...c, id: "b", name: "课程B" };
    expect(() => upsertCourse(s, other)).toThrow("冲突");
    upsertCourse(s, other, true);
    expect(s.courses).toHaveLength(2);
  });
  it("changes linked courses when their timetable changes, but leaves independent courses untouched", () => {
    const s = defaultState(),
      a = arrangementFromCell(table, 18);
    s.courses = [
      {
        id: "linked",
        semesterId: s.activeSemesterId,
        name: "联动课程",
        teacher: "",
        color: "blue",
        notes: "",
        arrangements: [a],
      },
      {
        id: "independent",
        semesterId: s.activeSemesterId,
        name: "原课程",
        teacher: "",
        color: "green",
        notes: "",
        arrangements: [{ ...newArrangement(18), timeMode: "custom" }],
      },
    ];
    s.timeTables[0].slots[0].start = "07:50";
    const clean = validateState(s);
    expect(clean.courses[0].arrangements[0].start).toBe("07:50");
    expect(clean.courses[1].arrangements[0].start).toBe("08:00");
    expect(restoreBackup(backup(clean))).toEqual(clean);
  });
  it("rejects invalid or overlapping timetables and removing periods still used by linked courses", () => {
    const s = defaultState();
    s.timeTables[0].slots[1].start = "08:30";
    expect(() => validateState(s)).toThrow("重叠");
    const next = defaultState();
    next.courses = [
      {
        id: "last",
        semesterId: next.activeSemesterId,
        name: "晚课",
        teacher: "",
        color: "blue",
        notes: "",
        arrangements: [
          arrangementFromCell(table, 18, { day: 1, period: 12, week: 1 }),
        ],
      },
    ];
    next.timeTables[0].slots.pop();
    expect(() => validateState(next)).toThrow("不存在这些节次");
  });
});

it("does not compress a real custom course placed inside the lunch break into an unreadable sliver", () => {
  const course = make("lunch", "12:00", "12:45");
  const axis = buildTimeAxis(table, [course]);
  expect(coursePosition(axis, course).height).toBeCloseTo(1);
});
