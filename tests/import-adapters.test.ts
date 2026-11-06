import { it, expect } from "vitest";
import {
  parseCourseFile,
  courseImportAdapters,
} from "../src/services/import-adapters";
import {
  csvTemplate,
  guessMapping,
  previewRows,
} from "../src/services/import-courses";
import { defaultState } from "../src/domain/schedule";
it("normalizes a trusted CSV adapter into the existing preview without saving data", async () => {
  const semester = defaultState().semesters[0],
    result = await parseCourseFile(
      "课程.CSV",
      new TextEncoder().encode(csvTemplate).buffer,
      { semester, existing: [] },
    );
  expect(result.kind).toBe("table");
  if (result.kind === "table")
    expect(
      previewRows(
        result.table,
        guessMapping(result.table.headers),
        semester,
        [],
      ).courses,
    ).toHaveLength(1);
  expect(courseImportAdapters.map((a) => a.id)).toEqual(["csv", "xlsx", "ics"]);
});
it("rejects unsupported sources and gives actionable parse errors", async () => {
  const context = { semester: defaultState().semesters[0], existing: [] };
  await expect(
    parseCourseFile("script.js", new ArrayBuffer(0), context),
  ).rejects.toThrow("请选择");
  await expect(
    parseCourseFile(
      "bad.xlsx",
      new TextEncoder().encode("not a workbook").buffer,
      context,
    ),
  ).rejects.toThrow("CSV 标准模板");
});
