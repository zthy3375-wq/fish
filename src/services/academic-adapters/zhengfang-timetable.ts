import {
  periodTimes,
  validateSemester,
  validateTimeTable,
  type Semester,
  type TimeTable,
} from "../../domain/schedule";
import {
  previewRows,
  type ImportPreview,
  type Mapping,
  type Table,
} from "../import-courses";
import type { ImportContext } from "../import-adapters";

/** Offline format adapter, NOT a school login connector. No fetch, cookies, JS execution or storage.
 * kbList field names are evidenced by the reviewed GDUST upstream adapter, not by a Handan response.
 * Callers must supply the selected term and a verified/user-confirmed timetable: no inferred dates/times.
 */
export interface ZhengfangContext extends ImportContext {
  timeTable: TimeTable;
  /** Optional exact source term identifiers supplied by an approved transport, never guessed here. */
  sourceTerm?: { xnm: string; xqm: string };
}
export interface ZhengfangPreview {
  kind: "offline-format-preview";
  authentication: "not-verified";
  semester: Semester;
  timeTable: TimeTable;
  preview: ImportPreview;
}
const MAX_BYTES = 1024 * 1024;
const MAX_ROWS = 500;
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
function field(v: unknown, max: number, required = false): string {
  if (v === undefined && !required) return "";
  if (typeof v !== "string" || v.length > max || (required && !v.trim()))
    throw Error("字段缺失、类型错误或长度超限");
  return v.trim();
}
/** Complete grammar, bounded before expansion; unknown fragments must not become an empty/partial week set. */
export function parseZhengfangWeeks(value: string, max: number): number[] {
  if (
    typeof value !== "string" ||
    value.length > 250 ||
    !Number.isInteger(max) ||
    max < 1 ||
    max > 40
  )
    throw Error("教学周格式或范围无效");
  const normalized = value.normalize("NFKC")
    .replace(/[\s\u200b-\u200d\ufeff]/g, "")
    .replace(/（/g, "(")
    .replace(/）/g, ")")
    .replace(/[，、；;]/g, ",")
    .replace(/[–—−~～至到]/g, "-");
  const weeks = new Set<number>();
  for (const segment of normalized.split(",")) {
    // 正方会将单双周放在“周”之前或之后；只接受完整的数值范围。
    const match = /^(?:第)?(\d{1,2})(?:-(?:第)?(\d{1,2}))?(?:周)?(?:\((单|双)(?:周)?\)(?:周)?|(单|双)(?:周)?)?$/.exec(segment);
    if (!match)
      throw Error("无法完整识别教学周；支持第1-16周、1-16(单)周、2-16双周、1,3,5周");
    const parity = match[3] ?? match[4];
    const first = Number(match[1]),
      last = Number(match[2] ?? match[1]);
    if (first < 1 || last < first || last > max)
      throw Error("教学周超出所选学期");
    for (let week = first; week <= last; week++) {
      if (parity === "单" && week % 2 === 0) continue;
      if (parity === "双" && week % 2 === 1) continue;
      weeks.add(week);
    }
  }
  if (!weeks.size) throw Error("单双周筛选后没有上课周次");
  return [...weeks].sort((a, b) => a - b);
}
function periods(value: unknown): [number, number] {
  const match = /^(\d{1,2})(?:-(\d{1,2}))?(?:节)?$/.exec(
    field(value, 20, true),
  );
  if (!match) throw Error("节次仅支持连续范围；非连续节次请分开提供");
  const first = Number(match[1]),
    last = Number(match[2] ?? match[1]);
  if (first < 1 || last > 24 || last < first) throw Error("节次范围无效");
  return [first, last];
}
function checkTerm(row: Record<string, unknown>, context: ZhengfangContext) {
  for (const key of ["xnm", "xqm"] as const) {
    if (row[key] === undefined) continue;
    if (
      !context.sourceTerm ||
      typeof row[key] !== "string" ||
      row[key] !== context.sourceTerm[key]
    )
      throw Error("来源学年学期未确认或不匹配；不能自动猜测学期编码");
  }
}
export function previewZhengfangTimetable(
  raw: unknown,
  context: ZhengfangContext,
): ZhengfangPreview {
  validateSemester(context.semester);
  validateTimeTable(context.timeTable);
  if (
    context.semester.timeTableId &&
    context.semester.timeTableId !== context.timeTable.id
  )
    throw Error("作息方案与所选学期不匹配");
  if (!record(raw) || !Array.isArray(raw.kbList))
    throw Error(
      "需要包含 kbList 数组的正方格式数据；登录页面或其他返回结构不可导入",
    );
  if (raw.kbList.length > MAX_ROWS) throw Error("超过 500 条安排，请拆分数据");
  if (
    raw.sjkList !== undefined &&
    (!Array.isArray(raw.sjkList) || raw.sjkList.length)
  )
    throw Error("包含尚未适配的实践课 sjkList，不能静默丢弃；请单独核对录入");
  checkTerm(raw, context);
  const rows: Record<string, string>[] = [];
  const errors: string[] = [];
  const warnings = [
    "仅验证离线正方数据格式，不证明学校授权、账号身份或邯郸学院兼容性。",
    "学期日期、总周数与作息来自调用方确认的配置，未从学校接口验证。",
  ];
  for (const [index, value] of raw.kbList.entries()) {
    try {
      if (!record(value)) throw Error("课程记录必须是对象");
      checkTerm(value, context);
      const name = field(value.kcmc, 150, true);
      const teacher = field(value.xm, 100),
        room = field(value.cdmc, 150);
      const day = value.xqj;
      if (
        !(
          (typeof day === "number" &&
            Number.isInteger(day) &&
            day >= 1 &&
            day <= 7) ||
          (typeof day === "string" && /^[1-7]$/.test(day))
        )
      )
        throw Error("星期必须为 1–7");
      const [startPeriod, endPeriod] = periods(value.jcs);
      const times = periodTimes(context.timeTable, startPeriod, endPeriod);
      const weeks = parseZhengfangWeeks(
        field(value.zcd, 250, true),
        context.semester.weekCount,
      );
      rows.push({
        name,
        teacher,
        room,
        day: String(day),
        startPeriod: String(startPeriod),
        endPeriod: String(endPeriod),
        ...times,
        weeks: weeks.join(","),
        notes: "",
      });
      if (!teacher || !room)
        warnings.push("部分课程缺少教师或教室，已留空，未丢弃课程或推测内容。");
    } catch (error) {
      // Only our controlled diagnostics; never stringify raw response/exception data into the UI.
      errors.push(`第 ${index + 1} 条安排：${(error as Error).message}`);
    }
  }
  const keys = [
    "name",
    "teacher",
    "room",
    "day",
    "startPeriod",
    "endPeriod",
    "start",
    "end",
    "weeks",
    "notes",
  ];
  const table: Table = { headers: keys, rows, warnings };
  const mapping = Object.fromEntries(keys.map((k) => [k, k])) as Mapping;
  const preview = previewRows(
    table,
    mapping,
    context.semester,
    context.existing,
  );
  preview.errors.unshift(...errors);
  for (const course of preview.courses)
    for (const arrangement of course.arrangements)
      arrangement.timeMode = "period";
  if (!raw.kbList.length)
    preview.warnings.push(
      "源课表为空；不能据此自动清空已有课表，必须由用户核对学期并确认。",
    );
  // Whitelist context too: credentials or arbitrary metadata must not be carried to a later backup.
  const s = context.semester,
    t = context.timeTable;
  return {
    kind: "offline-format-preview",
    authentication: "not-verified",
    semester: {
      id: s.id,
      academicYear: s.academicYear,
      season: s.season,
      startDate: s.startDate,
      weekStartDate: s.weekStartDate,
      weekCount: s.weekCount,
      timeTableId: t.id,
    },
    timeTable: {
      id: t.id,
      name: t.name,
      slots: t.slots.map(({ number, start, end }) => ({ number, start, end })),
    },
    preview,
  };
}
/** Decodes only user-supplied/local fixture bytes. Not registered as a general .json/backup import. */
export function parseZhengfangTimetableFile(
  buffer: ArrayBuffer,
  context: ZhengfangContext,
): ZhengfangPreview {
  if (!buffer.byteLength || buffer.byteLength > MAX_BYTES)
    throw Error("正方测试数据须为 1 B–1 MB");
  let raw: unknown;
  try {
    raw = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer));
  } catch {
    throw Error("需要 UTF-8 JSON 数据，不接受 HTML、脚本或错误编码");
  }
  return previewZhengfangTimetable(raw, context);
}
