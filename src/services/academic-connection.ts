import type { AcademicData, Course, Exam, Grade } from "../domain/academic";
import {
  validateSemester,
  validateTimeTable,
  parseDate,
  colors,
  type Semester,
  type TimeTable,
} from "../domain/schedule";
/** Implement only reviewed, school-approved, student-scoped adapters.
 * Passwords, cookies and tokens must stay inside the school's authorization implementation.
 */
export interface AuthorizedAcademicConnector {
  readonly id: string;
  readonly displayName: string;
  beginOfficialAuthorization(): Promise<void>;
  getSessionStatus(): Promise<"connected" | "expired" | "disconnected">;
  fetchMyAcademicData(): Promise<unknown>;
  disconnect(): Promise<void>;
}
export type ConnectionPhase =
  | "disconnected"
  | "authorizing"
  | "ready"
  | "syncing"
  | "expired"
  | "error";
export interface AcademicConnectionState {
  phase: ConnectionPhase;
  providerId: string;
  syncedAt: string | null;
  error: string | null;
}
export interface AcademicSyncSnapshot {
  semester: Semester;
  courses: Course[];
  grades: Grade[];
  exams: Exam[];
  timeTable?: TimeTable;
  fetchedAt: string;
  providerId: string;
}
const object = (x: unknown): x is Record<string, unknown> =>
  !!x && typeof x === "object" && !Array.isArray(x);
const numeric = (x: unknown, min: number, max: number): x is number =>
  typeof x === "number" && Number.isFinite(x) && x >= min && x <= max;
const clock = (x: unknown): x is string =>
  typeof x === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(x);
const text = (x: unknown, max: number, label: string, required = false) => {
  if (typeof x !== "string" || x.length > max || (required && !x.trim()))
    throw Error("无效的" + label);
  return x.trim();
};
export const validProviderId = (id: unknown): id is string =>
  typeof id === "string" && /^[A-Za-z0-9._-]{1,80}$/.test(id);
/** Bounded whitelisting cannot prove ownership; that is enforced by the adapter and school's API. */
export function normalizeAuthorizedAcademicData(
  raw: unknown,
  providerId: string,
  now = new Date(),
): AcademicSyncSnapshot {
  if (!validProviderId(providerId)) throw Error("无效的连接器编号");
  if (
    !object(raw) ||
    !Array.isArray(raw.courses) ||
    !Array.isArray(raw.grades) ||
    !Array.isArray(raw.exams)
  )
    throw Error("学校返回的数据格式不符合预期");
  if (
    raw.courses.length > 2000 ||
    raw.grades.length > 500 ||
    raw.exams.length > 500
  )
    throw Error("教务记录数量超出合理范围");
  if (!object(raw.semester))
    throw Error("缺少学校学期信息，无法正确计算教学周");
  const term = raw.semester as unknown as Semester;
  validateSemester(term);
  const semester: Semester = {
    id: term.id,
    academicYear: term.academicYear,
    season: term.season,
    startDate: term.startDate,
    weekStartDate: term.weekStartDate,
    weekCount: term.weekCount,
  };
  const ids = new Set<string>();
  const courses: Course[] = raw.courses.map((x, index) => {
    if (
      !object(x) ||
      !Number.isInteger(x.day) ||
      !numeric(x.day, 1, 7) ||
      !clock(x.start) ||
      !clock(x.end) ||
      x.start >= x.end ||
      !Array.isArray(x.weeks)
    )
      throw Error(`第 ${index + 1} 门课程时间格式无效`);
    if (
      !x.weeks.length ||
      x.weeks.length > 40 ||
      x.weeks.some(
        (w) => !Number.isInteger(w) || !numeric(w, 1, semester.weekCount),
      )
    )
      throw Error(`第 ${index + 1} 门课程教学周无效`);
    const id = text(x.id, 120, "课程编号", true);
    if (ids.has(id)) throw Error("课程编号重复");
    ids.add(id);
    return {
      id,
      name: text(x.name, 150, "课程名称", true),
      teacher: text(x.teacher, 100, "教师姓名"),
      room: text(x.room, 150, "教室"),
      day: x.day,
      start: x.start,
      end: x.end,
      period: text(x.period, 50, "节次"),
      weeks: [...new Set(x.weeks as number[])].sort((a, b) => a - b),
      color:
        typeof x.color === "string" && colors.includes(x.color)
          ? x.color
          : "blue",
    };
  });
  const grades: Grade[] = raw.grades.map((x) => {
    if (!object(x) || !numeric(x.credit, 0, 100) || !numeric(x.score, 0, 100))
      throw Error("成绩或学分数据格式无效");
    return {
      name: text(x.name, 150, "成绩课程", true),
      credit: x.credit,
      score: x.score,
      term: text(x.term, 80, "成绩学期", true),
      kind: text(x.kind, 60, "课程性质"),
    };
  });
  const exams: Exam[] = raw.exams.map((x) => {
    if (!object(x)) throw Error("考试数据格式无效");
    const date = text(x.date, 10, "考试日期", true);
    parseDate(date);
    return {
      name: text(x.name, 150, "考试名称", true),
      date,
      time: text(x.time, 80, "考试时间"),
      room: text(x.room, 150, "考场"),
      seat: text(x.seat, 80, "座位"),
    };
  });
  let timeTable: TimeTable | undefined;
  if (raw.timeTable !== undefined) {
    if (
      !object(raw.timeTable) ||
      !Array.isArray(raw.timeTable.slots) ||
      raw.timeTable.slots.length > 24
    )
      throw Error("授权作息数据无效");
    const t = raw.timeTable;
    timeTable = {
      id: text(t.id, 100, "作息编号", true),
      name: text(t.name, 60, "作息名称", true),
      slots: (t.slots as unknown[]).map((x) => {
        if (!object(x)) throw Error("授权作息节次无效");
        return {
          number: x.number as number,
          start: x.start as string,
          end: x.end as string,
        };
      }),
    };
    validateTimeTable(timeTable);
  }
  if (!Number.isFinite(now.getTime())) throw Error("同步时间无效");
  return {
    semester,
    courses,
    grades,
    exams,
    ...(timeTable ? { timeTable } : {}),
    fetchedAt: now.toISOString(),
    providerId,
  };
}
export function academicSnapshotToData(
  snapshot: AcademicSyncSnapshot,
): AcademicData {
  return {
    courses: snapshot.courses,
    grades: snapshot.grades,
    exams: snapshot.exams,
    source: "official",
  };
}
export function selectAcademicData(
  local: AcademicData,
  snapshot: AcademicSyncSnapshot | null,
  showOfficial: boolean,
) {
  return showOfficial && snapshot ? academicSnapshotToData(snapshot) : local;
}
type Listener = (
  snapshot: AcademicSyncSnapshot | null,
  state: Readonly<AcademicConnectionState>,
) => void;
/** Session-only state; generations invalidate late callbacks after logout/cancel. */
export class AcademicConnectionController {
  private status: AcademicConnectionState;
  private current: AcademicSyncSnapshot | null = null;
  private generation = 0;
  private inFlight: Promise<AcademicSyncSnapshot | null> | null = null;
  private disconnecting: Promise<boolean> | null = null;
  private listeners = new Set<Listener>();
  constructor(private readonly connector: AuthorizedAcademicConnector) {
    if (!validProviderId(connector.id)) throw Error("无效的连接器编号");
    this.status = {
      phase: "disconnected",
      providerId: connector.id,
      syncedAt: null,
      error: null,
    };
  }
  get state(): Readonly<AcademicConnectionState> {
    return { ...this.status };
  }
  get snapshot(): AcademicSyncSnapshot | null {
    return this.current ? structuredClone(this.current) : null;
  }
  subscribe(listener: Listener) {
    this.listeners.add(listener);
    try {
      listener(this.snapshot, this.state);
    } catch {
      /* Observers cannot block cleanup. */
    }
    return () => {
      this.listeners.delete(listener);
    };
  }
  private publish() {
    for (const listener of this.listeners)
      try {
        listener(this.snapshot, this.state);
      } catch {
        /* One broken observer cannot prevent other screens clearing private data. */
      }
  }
  private clear(phase: ConnectionPhase, error: string | null = null) {
    this.current = null;
    this.status = { ...this.status, phase, error, syncedAt: null };
    this.publish();
  }
  async connect(): Promise<boolean> {
    if (this.disconnecting) await this.disconnecting;
    const generation = ++this.generation;
    this.inFlight = null;
    this.clear("authorizing");
    try {
      await this.connector.beginOfficialAuthorization();
      if (generation !== this.generation) return false;
      const status = await this.connector.getSessionStatus();
      if (generation !== this.generation) return false;
      this.clear(
        status === "connected"
          ? "ready"
          : status === "expired"
            ? "expired"
            : "disconnected",
      );
      return status === "connected";
    } catch {
      if (generation === this.generation)
        this.clear("error", "学校授权未完成，请通过学校官方页面重试");
      return false;
    }
  }
  refresh(): Promise<AcademicSyncSnapshot | null> {
    if (this.status.phase === "authorizing") return Promise.resolve(null);
    if (this.inFlight) return this.inFlight;
    const job = this.performRefresh(this.generation);
    this.inFlight = job;
    void job.finally(() => {
      if (this.inFlight === job) this.inFlight = null;
    });
    return job;
  }
  private async performRefresh(
    generation: number,
  ): Promise<AcademicSyncSnapshot | null> {
    try {
      const status = await this.connector.getSessionStatus();
      if (generation !== this.generation) return null;
      if (status !== "connected") {
        this.clear(status === "expired" ? "expired" : "disconnected");
        return null;
      }
      this.status = { ...this.status, phase: "syncing", error: null };
      this.publish();
      const raw = await this.connector.fetchMyAcademicData();
      if (generation !== this.generation) return null;
      const statusAfterFetch = await this.connector.getSessionStatus();
      if (generation !== this.generation) return null;
      if (statusAfterFetch !== "connected") {
        this.clear(statusAfterFetch === "expired" ? "expired" : "disconnected");
        return null;
      }
      const result = normalizeAuthorizedAcademicData(
        raw,
        this.status.providerId,
      );
      this.current = result;
      this.status = {
        ...this.status,
        phase: "ready",
        syncedAt: result.fetchedAt,
        error: null,
      };
      this.publish();
      return this.snapshot;
    } catch {
      if (generation === this.generation)
        this.clear(
          "error",
          "同步失败或学校数据格式不受支持，请稍后重试或重新授权",
        );
      return null;
    }
  }
  disconnect(): Promise<boolean> {
    if (this.disconnecting) return this.disconnecting;
    const generation = ++this.generation;
    this.inFlight = null;
    this.clear("disconnected");
    const job = this.performDisconnect(generation);
    this.disconnecting = job;
    void job.finally(() => {
      if (this.disconnecting === job) this.disconnecting = null;
    });
    return job;
  }
  private async performDisconnect(generation: number): Promise<boolean> {
    try {
      await this.connector.disconnect();
      return true;
    } catch {
      if (generation === this.generation)
        this.clear(
          "error",
          "本机教务数据已清除，但学校授权撤销失败，请在学校端检查授权",
        );
      return false;
    }
  }
}
