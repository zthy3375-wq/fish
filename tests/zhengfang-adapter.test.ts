import "fake-indexeddb/auto";
import { describe, it, expect, vi } from "vitest";
import fixture from "./fixtures/academic/zhengfang-synthetic.json";
import {
  parseZhengfangWeeks,
  previewZhengfangTimetable,
  parseZhengfangTimetableFile,
  type ZhengfangContext,
} from "../src/services/academic-adapters/zhengfang-timetable";
import {
  defaultState,
  flatten,
  backup,
  restoreBackup,
  standardTimeTable,
  semesterWeek,
} from "../src/domain/schedule";
import { coursesForDay } from "../src/domain/academic";
import { nextOccurrence } from "../src/domain/presentation";
import { upsertCourse } from "../src/services/course-management";
import { readSchedule, writeSchedule } from "../src/services/schedule-storage";
import { normalizeAuthorizedAcademicData } from "../src/services/academic-connection";
import { getAuthorizedAcademicConnector } from "../src/services/authorized-connector-registry";
function context(): ZhengfangContext {
  const state = defaultState();
  return {
    semester: state.semesters[0],
    timeTable: state.timeTables[0],
    existing: [],
  };
}
const row = () => structuredClone(fixture.kbList[0]);
const bytes = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value)).buffer;
describe("offline Zhengfang adapter — synthetic fixtures, no school connection", () => {
  it("maps repeated courses to multiple arrangements and explicit timetable times", () => {
    const c = context(),
      result = previewZhengfangTimetable(fixture, c);
    expect(result.kind).toBe("offline-format-preview");
    expect(result.authentication).toBe("not-verified");
    expect(result.preview.errors).toEqual([]);
    expect(result.preview.courses).toHaveLength(2);
    const arrangements = result.preview.courses[0].arrangements;
    expect(arrangements).toHaveLength(2);
    expect(arrangements[0]).toMatchObject({
      day: 1,
      startPeriod: 1,
      endPeriod: 2,
      start: "08:00",
      end: "09:35",
      timeMode: "period",
    });
    expect(arrangements[0].customWeeks).toEqual([1, 3, 5, 7, 9, 11, 13, 15]);
    expect(arrangements[1]).toMatchObject({
      day: 3,
      room: "测试教室202",
      startPeriod: 3,
      endPeriod: 5,
    });
    expect(result.preview.warnings.join("")).toContain("缺少教师或教室");
  });
  it.each([
    ["1-16周(单)", [1, 3, 5, 7, 9, 11, 13, 15]],
    ["2-16周（双周）", [2, 4, 6, 8, 10, 12, 14, 16]],
    ["1、3、5周, 8-10周(双)", [1, 3, 5, 8, 10]],
    ["1-3周,2周", [1, 2, 3]],
  ])("fully parses week expression %s", (input, expected) =>
    expect(parseZhengfangWeeks(input, 18)).toEqual(expected),
  );
  it.each([
    "",
    "0-18周",
    "1-19周",
    "16-2周",
    "1-999999999周",
    "1-16周(未知)",
    "1-16周 extra",
    "1,,3",
    "2周(单)",
    "1-3周(单)(双)",
  ])("rejects ambiguous/bounded week expression %s", (input) =>
    expect(() => parseZhengfangWeeks(input, 18)).toThrow(),
  );
  it("uses a supplied 13-period configuration rather than hardcoded example times", () => {
    const c = context();
    c.timeTable = {
      id: c.timeTable.id,
      name: "人工测试作息，非学校配置",
      slots: Array.from({ length: 13 }, (_, i) => ({
        number: i + 1,
        start: `${String(6 + i).padStart(2, "0")}:00`,
        end: `${String(6 + i).padStart(2, "0")}:40`,
      })),
    };
    const result = previewZhengfangTimetable(
      { kbList: [{ ...row(), jcs: "11-13" }] },
      c,
    );
    expect(result.preview.errors).toEqual([]);
    expect(result.preview.courses[0].arrangements[0]).toMatchObject({
      start: "16:00",
      end: "18:40",
    });
  });
  it("requires a valid associated timetable and never guesses missing periods", () => {
    const c = context();
    expect(() =>
      previewZhengfangTimetable(fixture, { ...c, timeTable: undefined! }),
    ).toThrow();
    expect(() =>
      previewZhengfangTimetable(fixture, {
        ...c,
        timeTable: standardTimeTable("other"),
      }),
    ).toThrow("不匹配");
    const result = previewZhengfangTimetable(
      { kbList: [{ ...row(), jcs: "11-13" }] },
      c,
    );
    expect(result.preview.errors.join("")).toContain("不存在这些节次");
    expect(result.preview.courses).toHaveLength(0);
  });
  it.each([
    { jcs: "1,3" },
    { jcs: "2-1" },
    { jcs: "0" },
    { xqj: "8" },
    { xqj: "1x" },
    { kcmc: "" },
    { zcd: "待定" },
  ])(
    "reports malformed arrangements instead of silently omitting them: %j",
    (patch) => {
      const result = previewZhengfangTimetable(
        { kbList: [{ ...row(), ...patch }] },
        context(),
      );
      expect(result.preview.errors).toHaveLength(1);
      expect(result.preview.courses).toHaveLength(0);
    },
  );
  it("rejects login/unknown/oversized schemas and unsupported practice courses", () => {
    for (const value of [
      "<html>登录</html>",
      {},
      { kbList: {} },
      { kbList: Array(501).fill(row()) },
      { kbList: [], sjkList: [{}] },
      { kbList: [], sjkList: "x" },
    ])
      expect(() => previewZhengfangTimetable(value, context())).toThrow();
  });
  it("does not interpret source term codes or merge mismatched semesters", () => {
    const c = context(),
      raw = { kbList: [{ ...row(), xnm: "2026", xqm: "3" }] };
    expect(previewZhengfangTimetable(raw, c).preview.errors.join("")).toContain(
      "未确认",
    );
    c.sourceTerm = { xnm: "2026", xqm: "3" };
    expect(previewZhengfangTimetable(raw, c).preview.errors).toEqual([]);
    expect(
      previewZhengfangTimetable(
        { kbList: [{ ...raw.kbList[0], xqm: "12" }] },
        c,
      ).preview.errors.join(""),
    ).toContain("不匹配");
    expect(() => previewZhengfangTimetable({ ...raw, xnm: "2025" }, c)).toThrow(
      "不匹配",
    );
  });
  it("reuses duplicate and conflict detection without mutating local courses", () => {
    const c = context(),
      imported = previewZhengfangTimetable(fixture, c).preview.courses;
    c.existing = imported;
    const before = structuredClone(c);
    const duplicate = previewZhengfangTimetable(fixture, c).preview;
    expect(duplicate.duplicates).toBe(3);
    expect(duplicate.courses).toHaveLength(0);
    const conflict = previewZhengfangTimetable(
      { kbList: [{ ...row(), kcmc: "另一门课程" }] },
      c,
    ).preview;
    expect(conflict.issues.join("")).toContain("重叠");
    expect(c).toEqual(before);
  });
  it("reports empty sources without treating them as an instruction to clear data", () => {
    const c = context();
    c.existing = previewZhengfangTimetable(fixture, c).preview.courses;
    const before = structuredClone(c);
    const result = previewZhengfangTimetable({ kbList: [] }, c);
    expect(result.preview.courses).toHaveLength(0);
    expect(result.preview.warnings.join("")).toContain("不能据此自动清空");
    expect(c).toEqual(before);
  });
  it("bounds and safely decodes file bytes, never evaluating injected scripts or carrying credentials", () => {
    const c = context();
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    try {
      const maliciousName =
        "<img src=x onerror=\"fetch('https://evil.invalid')\">";
      const result = parseZhengfangTimetableFile(
        bytes({
          kbList: [{ ...row(), kcmc: maliciousName, token: "secret" }],
          cookie: "secret",
          __proto__: { polluted: true },
        }),
        c,
      );
      expect(result.preview.courses[0].name).toBe(maliciousName); // plain Vue-escaped text, never HTML
      expect(JSON.stringify(result)).not.toContain("secret");
      expect(fetchSpy).not.toHaveBeenCalled();
      expect(Object.prototype).not.toHaveProperty("polluted");
      for (const buffer of [
        new ArrayBuffer(0),
        new ArrayBuffer(1024 * 1024 + 1),
        new Uint8Array([255]).buffer,
        new TextEncoder().encode("<script>alert(1)</script>").buffer,
      ])
        expect(() => parseZhengfangTimetableFile(buffer, c)).toThrow();
    } finally {
      vi.unstubAllGlobals();
    }
  });
  it("adapts to v0.4 normalization without claiming that authentication was performed", () => {
    const c = context(),
      result = previewZhengfangTimetable(fixture, c);
    const normalized = normalizeAuthorizedAcademicData(
      {
        semester: result.semester,
        timeTable: result.timeTable,
        courses: flatten(result.preview.courses, c.semester.id, c.timeTable),
        grades: [],
        exams: [],
      },
      "format-test-only",
    );
    expect(normalized.courses).toHaveLength(3);
    expect(normalized.grades).toEqual([]);
    expect(getAuthorizedAcademicConnector()).toBeNull();
  });
  it("round-trips reviewed synthetic courses through existing CRUD, backup, IndexedDB and shared selectors", async () => {
    const c = context(),
      result = previewZhengfangTimetable(fixture, c);
    const state = defaultState();
    state.reminders.minutes = 15;
    const originalTerm = structuredClone(state.semesters[0]);
    // This explicit test-only commit is separate from the adapter's pure preview.
    for (const course of result.preview.courses) upsertCourse(state, course);
    const local = flatten(
      state.courses,
      state.activeSemesterId,
      state.timeTables[0],
    );
    const monday = new Date(2026, 8, 7, 7, 0);
    expect(semesterWeek(monday, state.semesters[0])).toBe(1);
    expect(coursesForDay(local, 1, 1)).toHaveLength(1);
    expect(coursesForDay(local, 1, 2)).toHaveLength(0);
    expect(coursesForDay(local, 3, 2)[0].room).toBe("测试教室202");
    expect(nextOccurrence(local, monday, state.semesters[0])?.course.name).toBe(
      "格式测试课程甲",
    );
    await writeSchedule(state);
    expect(await readSchedule()).toEqual(state);
    expect(restoreBackup(backup(state))).toEqual(state);
    expect(state.semesters[0]).toEqual(originalTerm);
    expect(state.reminders.minutes).toBe(15);
  });
});
