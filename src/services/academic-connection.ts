import type { AcademicData, Course, Exam, Grade } from '../domain/academic';
import {validateSemester, type Semester} from '../domain/schedule';

/**
 * Contract for a school-approved, student-scoped academic connection.
 *
 * A connector MUST perform authentication on the school's own authentication
 * surface. Never accept a username or password from the host application.
 * Implementations must not access another student's records or bypass controls.
 *
 * Deliberately no Handan University adapter is registered here: a public
 * login page is not evidence of a third-party token grant or data API.
 */
export interface AuthorizedAcademicConnector {
  readonly id: string;
  readonly displayName: string;
  beginOfficialAuthorization(): Promise<void>;
  getSessionStatus(): Promise<'connected' | 'expired' | 'disconnected'>;
  fetchMyAcademicData(): Promise<unknown>;
  disconnect(): Promise<void>;
}

export type ConnectionPhase =
  | 'disconnected'
  | 'authorizing'
  | 'ready'
  | 'syncing'
  | 'expired'
  | 'error';

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
  fetchedAt: string;
  providerId: string;
}

type RecordLike = Record<string, unknown>;
const object = (value: unknown): value is RecordLike =>
  !!value && typeof value === 'object' && !Array.isArray(value);
const string = (value: unknown, max: number): value is string =>
  typeof value === 'string' && value.length <= max;
const time = (value: unknown): value is string =>
  typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
const number = (value: unknown, min: number, max: number): value is number =>
  typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
const text = (value: unknown, max: number, label: string): string => {
  if (!string(value, max)) throw new Error('无效的' + label);
  return value;
};

/**
 * Whitelist ONLY academic records the student is meant to see.
 * Unknown keys (including cookies, passwords and tokens) are never returned.
 * This is a data boundary, not a replacement for server-side authorization.
 */
export function normalizeAuthorizedAcademicData(raw: unknown, providerId: string, now = new Date()): AcademicSyncSnapshot {
  if (!object(raw) || !Array.isArray(raw.courses) || !Array.isArray(raw.grades) || !Array.isArray(raw.exams))
    throw new Error('学校返回的数据格式不符合预期');
  if (raw.courses.length > 2000 || raw.grades.length > 500 || raw.exams.length > 500)
    throw new Error('教务记录数量超出合理范围');
  if (!object(raw.semester)) throw new Error('缺少学校学期信息，无法正确计算教学周');
  const semester = raw.semester as unknown as Semester;
  validateSemester(semester);
  const cleanSemester: Semester = {id: semester.id, academicYear: semester.academicYear, season: semester.season, startDate: semester.startDate, weekStartDate: semester.weekStartDate, weekCount: semester.weekCount};
  const courses: Course[] = raw.courses.map((item: unknown, index: number) => {
    if (!object(item) || !Number.isInteger(item.day) || !number(item.day, 1, 7) || !time(item.start) || !time(item.end) || item.start >= item.end || !Array.isArray(item.weeks))
      throw new Error('第 ' + (index + 1) + ' 门课程时间格式无效');
    const weeks = item.weeks;
    if (weeks.length > 40 || weeks.some((w: unknown) => !Number.isInteger(w) || !number(w, 1, 40)))
      throw new Error('第 ' + (index + 1) + ' 门课程教学周无效');
    return {
      id: text(item.id, 120, '课程编号'),
      name: text(item.name, 150, '课程名称'),
      teacher: text(item.teacher, 100, '教师姓名'),
      room: text(item.room, 150, '教室'),
      day: item.day,
      start: item.start,
      end: item.end,
      period: text(item.period, 50, '节次'),
      weeks: [...new Set(weeks as number[])].sort((a, b) => a - b),
      color: string(item.color, 24) ? item.color : 'blue'
    };
  });
  const grades: Grade[] = raw.grades.map((item: unknown) => {
    if (!object(item) || !number(item.credit, 0, 100) || !number(item.score, 0, 100))
      throw new Error('成绩或学分数据格式无效');
    return {
      name: text(item.name, 150, '成绩课程'),
      credit: item.credit,
      score: item.score,
      term: text(item.term, 80, '成绩学期'),
      kind: text(item.kind, 60, '课程性质')
    };
  });
  const exams: Exam[] = raw.exams.map((item: unknown) => {
    if (!object(item)) throw new Error('考试数据格式无效');
    const date = text(item.date, 10, '考试日期');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(date + 'T00:00:00')))
      throw new Error('考试日期无效');
    return {
      name: text(item.name, 150, '考试名称'),
      date,
      time: text(item.time, 80, '考试时间'),
      room: text(item.room, 150, '考场'),
      seat: text(item.seat, 80, '座位')
    };
  });
  return { semester: cleanSemester, courses, grades, exams, fetchedAt: now.toISOString(), providerId };
}

export function academicSnapshotToData(snapshot: AcademicSyncSnapshot): AcademicData {
  return {
    courses: snapshot.courses,
    grades: snapshot.grades,
    exams: snapshot.exams,
    source: 'official'
  };
}

/**
 * Controller holds an in-memory, sanitized snapshot. No credentials, session
 * cookies or tokens are accepted or stored. Sync is initiated only after a
 * school-supported session has been established by the connector.
 */
export class AcademicConnectionController {
  readonly state: AcademicConnectionState;
  private current: AcademicSyncSnapshot | null = null;

  constructor(private readonly connector: AuthorizedAcademicConnector) {
    this.state = { phase: 'disconnected', providerId: connector.id, syncedAt: null, error: null };
  }

  get snapshot(): AcademicSyncSnapshot | null {
    return this.current;
  }

  async connect(): Promise<boolean> {
    this.state.phase = 'authorizing';
    this.state.error = null;
    try {
      await this.connector.beginOfficialAuthorization();
      const status = await this.connector.getSessionStatus();
      this.state.phase = status === 'connected' ? 'ready' : status === 'expired' ? 'expired' : 'disconnected';
      return status === 'connected';
    } catch (error) {
      this.state.phase = 'error';
      this.state.error = String(error);
      return false;
    }
  }

  async refresh(): Promise<AcademicSyncSnapshot | null> {
    this.state.error = null;
    try {
      const status = await this.connector.getSessionStatus();
      if (status !== 'connected') {
        this.state.phase = status === 'expired' ? 'expired' : 'disconnected';
        return null;
      }
      this.state.phase = 'syncing';
      const result = normalizeAuthorizedAcademicData(await this.connector.fetchMyAcademicData(), this.connector.id);
      this.current = result;
      this.state.syncedAt = result.fetchedAt;
      this.state.phase = 'ready';
      return result;
    } catch (error) {
      this.state.phase = 'error';
      this.state.error = String(error);
      return null;
    }
  }

  async disconnect(): Promise<void> {
    await this.connector.disconnect();
    this.current = null;
    this.state.syncedAt = null;
    this.state.error = null;
    this.state.phase = 'disconnected';
  }
}
