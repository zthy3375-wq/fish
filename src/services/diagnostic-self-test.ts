import { previewZhengfangTimetable } from "./academic-adapters/zhengfang-timetable";
import { defaultState } from "../domain/schedule";
import { createFixtureReport } from "./academic-diagnostics";
/** In-memory synthetic structure only; no file/network/user timetable reads or writes. */
export function runDiagnosticSelfTest() {
  try {
    const state = defaultState();
    const result = previewZhengfangTimetable(
      {
        kbList: [
          {
            kcmc: "人工结构样本",
            xm: "人工教师",
            cdmc: "人工位置",
            xqj: "1",
            jcs: "1-2",
            zcd: "1-16周(单)",
          },
          {
            kcmc: "人工结构样本",
            xm: "人工教师",
            cdmc: "人工位置",
            xqj: "3",
            jcs: "3-5",
            zcd: "2-16周(双)",
          },
        ],
      },
      {
        semester: state.semesters[0],
        timeTable: state.timeTables[0],
        existing: [],
      },
    );
    const c = result.preview.courses[0];
    const passed =
      !result.preview.errors.length &&
      result.preview.courses.length === 1 &&
      c.arrangements.length === 2 &&
      c.arrangements[0].customWeeks.length === 8 &&
      c.arrangements[1].customWeeks.every((w) => w % 2 === 0);
    return createFixtureReport(passed);
  } catch {
    return createFixtureReport(false);
  }
}
