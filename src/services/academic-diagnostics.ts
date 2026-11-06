import { Capacitor, registerPlugin } from "@capacitor/core";
export const DIAGNOSTIC_BUILD =
  import.meta.env.VITE_ANDROID_DIAGNOSTICS === "true";
export const OFFICIAL_LOGIN = "https://jwgl.hdc.edu.cn/xtgl/login_slogin.html";
interface DiagnosticNative {
  openSchoolWindow(options?:{automatic:boolean}): Promise<{
    automatic?:boolean;
    cancelled?: true;
    observation?: unknown;
    kbList?: unknown[];
  }>;
  getCapabilities(): Promise<{
    enabled: boolean;
    canReadPage: false;
    schoolPermission: "unverified";
    browser: "external-system-browser";
  }>;
  openOfficialBrowser(): Promise<{
    opened: true;
    loginStatus: "not-observable";
  }>;
  checkCurrentPage(): Promise<{
    readPerformed: false;
    reason: "permission-and-browser-isolation";
  }>;
}
const native = registerPlugin<DiagnosticNative>("AcademicDiagnostics");
export function mayUseDiagnostics(
  build: boolean,
  platform: string,
  nativeEnabled: boolean,
) {
  return build && platform === "android" && nativeEnabled;
}
export async function boundedNative<T>(
  request: Promise<T>,
  milliseconds = 8000,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  try {
    return await Promise.race([
      request,
      new Promise<T>((_, reject) => {
        timer = setTimeout(
          () => reject(Error("原生操作确认超时，未判断学校登录状态")),
          milliseconds,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer!);
  }
}
export async function diagnosticAvailability() {
  if (!DIAGNOSTIC_BUILD || Capacitor.getPlatform() !== "android") return false;
  try {
    return mayUseDiagnostics(
      DIAGNOSTIC_BUILD,
      Capacitor.getPlatform(),
      (await boundedNative(native.getCapabilities(), 3000)).enabled,
    );
  } catch {
    return false;
  }
}
async function requireDiagnostic() {
  if (!(await diagnosticAvailability()))
    throw Error("诊断工具仅在 Android 专用测试构建中启用");
}
export async function openDiagnosticBrowser() {
  await requireDiagnostic();
  try {
    return await boundedNative(native.openOfficialBrowser());
  } catch (error) {
    const code = (error as { code?: string })?.code;
    // Do not display exception strings which might contain URLs or device identifiers.
    throw Error(
      code === "NETWORK_UNAVAILABLE"
        ? "设备当前离线，请联网后重试。"
        : code === "BROWSER_UNAVAILABLE"
          ? "未找到系统浏览器，请安装或启用浏览器后重试。"
          : "系统未能打开浏览器，请检查默认浏览器设置后重试。",
    );
  }
}
export async function checkDiagnosticPage() {
  await requireDiagnostic();
  const result = await boundedNative(native.checkCurrentPage());
  if (
    result.readPerformed !== false ||
    result.reason !== "permission-and-browser-isolation"
  )
    throw Error("诊断返回结构异常，已停止生成报告");
  return createBoundaryReport();
}
const unknownFields = () =>
  ({
    courseName: "unknown",
    teacher: "unknown",
    room: "unknown",
    weekday: "unknown",
    periods: "unknown",
    weeks: "unknown",
  }) as const;
export function createBoundaryReport() {
  return {
    schemaVersion: 1,
    toolVersion: "0.4.2",
    source: "external-browser-boundary",
    result: "blocked",
    officialLogin: "not-observable",
    schoolPermission: "unverified",
    pageRead: false,
    personalCoursesParsed: false,
    thirdPartySyncAuthorized: false,
    automaticSync: false,
    pageType: "unobserved",
    containerType: "unobserved",
    fields: unknownFields(),
    dateStructure: "unobserved",
    periodStructure: "unobserved",
    weekStructure: "unobserved",
    oddEvenWeeks: "unknown",
    exportFunction: "unknown",
    unknownFieldCount: null,
    parserCompatibility: "not-verified",
    reasons: ["school-permission-unverified", "external-browser-dom-isolated"],
    nextStep: "request-approved-interface-or-redacted-structural-sample",
  } as const;
}
export function createFixtureReport(passed: boolean) {
  return {
    ...createBoundaryReport(),
    source: "synthetic-offline-self-test",
    result: passed ? "passed" : "failed",
    pageType: "synthetic-json",
    containerType: "kbList-fixture",
    fields: {
      courseName: "present",
      teacher: "present",
      room: "present",
      weekday: "present",
      periods: "present",
      weeks: "present",
    },
    dateStructure: "caller-supplied-test-semester",
    periodStructure: "explicit-test-time-table",
    weekStructure: "explicit-week-numbers",
    oddEvenWeeks: "synthetic-only",
    parserCompatibility: passed
      ? "synthetic-fixture-passed"
      : "synthetic-fixture-failed",
    reasons: ["not-a-school-response"],
    nextStep: "verify-permission-and-real-redacted-schema",
  } as const;
}
export type DiagnosticReport =
  | ReturnType<typeof createBoundaryReport>
  | ReturnType<typeof createFixtureReport>
  | ReturnType<typeof createSchoolPageReport>;
/** Only these closed templates can leave the tool. Unknown/raw fields are NEVER serialized. */
export function sanitizeReport(raw: unknown): DiagnosticReport {
  if (!raw || typeof raw !== "object") throw Error("报告结构无效");
  const value = raw as Record<string, unknown>;
  if (value.schemaVersion !== 1 || value.toolVersion !== "0.4.2")
    throw Error("报告版本无效");
  if (
    value.source === "external-browser-boundary" &&
    value.result === "blocked"
  )
    return createBoundaryReport();
  if (
    value.source === "synthetic-offline-self-test" &&
    ["passed", "failed"].includes(String(value.result))
  )
    return createFixtureReport(value.result === "passed");
  if (value.source === "native-webview-user-action")
    return createSchoolPageReport(value.observation);
  throw Error("报告包含无法安全过滤的类型，已停止导出");
}
export const reportJSON = (raw: unknown) =>
  JSON.stringify(sanitizeReport(raw), null, 2);
const REPORT_KEY = "handan-campus.diagnostic-report.v1";
export function saveDiagnosticReport(report: DiagnosticReport) {
  localStorage.setItem(REPORT_KEY, reportJSON(report));
}
export function loadDiagnosticReport(): DiagnosticReport | null {
  const text = localStorage.getItem(REPORT_KEY);
  if (!text) return null;
  if (text.length > 12000) throw Error("本机报告异常，请删除后重试");
  try {
    return sanitizeReport(JSON.parse(text));
  } catch {
    throw Error("本机报告无法安全读取，请删除后重试");
  }
}
export function deleteDiagnosticReport() {
  localStorage.removeItem(REPORT_KEY);
}
export async function exportDiagnosticReport(report: DiagnosticReport) {
  await requireDiagnostic();
  const data = reportJSON(report);
  const [{ Filesystem, Directory, Encoding }, { Share }] = await Promise.all([
    import("@capacitor/filesystem"),
    import("@capacitor/share"),
  ]);
  const path = "academic-diagnostic-report.json";
  try {
    const { uri } = await Filesystem.writeFile({
      path,
      data,
      directory: Directory.Cache,
      encoding: Encoding.UTF8,
    });
    await Share.share({ title: "审核后的教务脱敏诊断报告", url: uri });
  } finally {
    // Only created by an explicit export. OS/user-owned shared copies are outside app control.
    await Filesystem.deleteFile({ path, directory: Directory.Cache }).catch(
      () => {},
    );
  }
}

export interface SchoolPageObservation {
  termYear?:string; termCode?:string;
  container: "unrecognized" | "kbList" | "zf-grid" | "zf-list";
  fields: {
    courseName: boolean;
    teacher: boolean;
    room: boolean;
    weekday: boolean;
    periods: boolean;
    weeks: boolean;
  };
  recordCount: number;
  invalidCount: number;
  specialArrangements: boolean;
  exportControl: boolean;
  frameLimit: boolean;
}
export function validateObservation(raw: unknown): SchoolPageObservation {
  if (!raw || typeof raw !== "object") throw Error("结构报告无效");
  const v = raw as Record<string, unknown>;
  if (
    !["unrecognized", "kbList", "zf-grid", "zf-list"].includes(
      String(v.container),
    ) ||
    !v.fields ||
    typeof v.fields !== "object"
  )
    throw Error("未知课表容器");
  const f = v.fields as Record<string, unknown>,
    fields = {} as SchoolPageObservation["fields"];
  for (const key of [
    "courseName",
    "teacher",
    "room",
    "weekday",
    "periods",
    "weeks",
  ] as const) {
    if (typeof f[key] !== "boolean") throw Error("字段存在性无效");
    fields[key] = f[key];
  }
  for (const key of ["recordCount", "invalidCount"] as const)
    if (!Number.isInteger(v[key]) || Number(v[key]) < 0 || Number(v[key]) > 501)
      throw Error("结构计数超限");
  for (const key of [
    "specialArrangements",
    "exportControl",
    "frameLimit",
  ] as const)
    if (typeof v[key] !== "boolean") throw Error("结构状态无效");
  return {
    ...(typeof v.termYear==="string" && /^20\d{2}$/.test(v.termYear) && ["3","12"].includes(String(v.termCode))?{termYear:v.termYear,termCode:String(v.termCode)}:{}),
    container: v.container as SchoolPageObservation["container"],
    fields,
    recordCount: v.recordCount as number,
    invalidCount: v.invalidCount as number,
    specialArrangements: v.specialArrangements as boolean,
    exportControl: v.exportControl as boolean,
    frameLimit: v.frameLimit as boolean,
  };
}
export function createSchoolPageReport(raw: unknown) {
  const observation = validateObservation(raw);
  return {
    schemaVersion: 1,
    toolVersion: "0.4.2",
    source: "native-webview-user-action",
    schoolPermission: "not-independently-verified",
    officialLogin: "not-attested-by-app",
    pageRead: true,
    personalCoursesParsed: false,
    thirdPartySyncAuthorized: false,
    automaticSync: false,
    parserCompatibility: "awaiting-local-preview-and-student-check",
    observation,
  } as const;
}
export async function openSchoolWindow(automatic=false): Promise<{
    automatic?:boolean;
  cancelled?: true;
  observation?: SchoolPageObservation;
  kbList?: unknown[];
}> {
  await requireDiagnostic();
  // User may spend minutes solving school's own authentication; no artificial eight-second login timeout.
  const result = await native.openSchoolWindow({automatic});
  if (result.cancelled) return { cancelled: true };
  const observation = validateObservation(result.observation);
  if (
    result.kbList !== undefined &&
    (!Array.isArray(result.kbList) || result.kbList.length > 500)
  )
    throw Error("课程数量异常");
  return {
    automatic:automatic && result.automatic===true,
    observation,
    ...(result.kbList !== undefined ? { kbList: result.kbList } : {}),
  };
}
