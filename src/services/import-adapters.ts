import {
  readTable,
  previewICS,
  type Table,
  type ImportPreview,
} from "./import-courses";
import type { Semester, ManagedCourse } from "../domain/schedule";
export interface ImportContext {
  semester: Semester;
  existing: ManagedCourse[];
}
export type ImportResult =
  | { kind: "table"; table: Table }
  | { kind: "courses"; preview: ImportPreview };
/** Trusted, compiled-in adapters only. A future authorized school export adapter can return the same preview contract. */
export interface CourseImportAdapter {
  id: string;
  extensions: string[];
  parse(buffer: ArrayBuffer, context: ImportContext): Promise<ImportResult>;
}
export const courseImportAdapters: CourseImportAdapter[] = [
  {
    id: "csv",
    extensions: ["csv"],
    async parse(buffer) {
      return { kind: "table", table: await readTable("courses.csv", buffer) };
    },
  },
  {
    id: "xlsx",
    extensions: ["xlsx"],
    async parse(buffer) {
      return { kind: "table", table: await readTable("courses.xlsx", buffer) };
    },
  },
  {
    id: "ics",
    extensions: ["ics"],
    async parse(buffer, context) {
      return {
        kind: "courses",
        preview: await previewICS(buffer, context.semester, context.existing),
      };
    },
  },
];
export async function parseCourseFile(
  name: string,
  buffer: ArrayBuffer,
  context: ImportContext,
) {
  const extension = name.split(".").at(-1)?.toLowerCase();
  const adapter = courseImportAdapters.find((a) =>
    a.extensions.includes(extension ?? ""),
  );
  if (!adapter)
    throw Error("请选择 CSV、XLSX 或 ICS 课程文件；JSON 备份请到“数据”恢复");
  try {
    return await adapter.parse(buffer, context);
  } catch (e) {
    throw Error(
      `无法解析 ${name}：${(e as Error).message}。请核对文件格式，或使用 CSV 标准模板。`,
    );
  }
}
