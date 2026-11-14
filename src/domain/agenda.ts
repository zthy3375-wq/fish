import type { Course, Exam } from './academic';
import type { Semester } from './schedule';
export interface TaskStep {
    id: string;
    title: string;
    completed: boolean;
}
export interface TaskReminder {
    id: string;
    anchor: 'start' | 'deadline' | 'absolute';
    minutes: number;
    at?: string;
}
export interface RepeatRule {
    kind: 'daily' | 'weekdays' | 'weekly' | 'days' | 'interval';
    interval: number;
    weekdays: number[];
}
export interface CampusTask {
    source?: 'chaoxing'; externalId?: string; platformStatus?: string; platformStatusText?: string; platformStale?: boolean; platformDescription?:string; platformKind?: string; platformStartAt?:string|null; timeText?: string;
    plannedAt?: string | null;
    plannedDay?: string | null;
    prepared?: boolean;
    durationMinutes?: number;
    priority?: number;
    pinned?: boolean;
    steps?: TaskStep[];
    repeat?: RepeatRule | null;
    reminders?: TaskReminder[];
    completedAt?: string | null;
    generatedFrom?: string;
    seriesId?: string;
    snoozedUntil?: string | null;
    id: string;
    title: string;
    course: string;
    deadline: string | null;
    notes: string;
    completed: boolean;
    remindMinutes: number | null;
    createdAt: string;
    updatedAt: string;
}
export interface TaskSnapshot {
    version: 1 | 2;
    tasks: CampusTask[];
    notificationsEnabled: boolean;
    updatedAt: string;
}
export interface CourseSeries {
    semester: Semester;
    courses: Course[];
    source: 'school' | 'personal';
}
export interface AgendaEvent {
    id: string;
    kind: 'course' | 'exam' | 'task';
    title: string;
    date: string;
    time: string;
    startAt: number | null;
    endAt: number | null;
    location: string;
    source: string;
    completed: boolean;
    taskId?: string;
    course?: Course;
}
export const emptyTasks = (): TaskSnapshot => ({ version: 2, tasks: [], notificationsEnabled: false, updatedAt: new Date().toISOString() });
export function beijingDay(now = new Date()) { const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now).map(p => [p.type, p.value])); return `${parts.year}-${parts.month}-${parts.day}`; }
export function validDay(value: string) { if (!/^20\d{2}-\d{2}-\d{2}$/.test(value))
    return false; const d = new Date(value + 'T00:00:00Z'); return !Number.isNaN(+d) && d.toISOString().slice(0, 10) === value; }
export function beijingTimestamp(value: string) { const [day, time] = value.split('T'); if (!validDay(day) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time || ''))
    throw Error('请填写有效的北京时间'); return +new Date(`${day}T${time}:00+08:00`); }
export function shiftDay(day: string, offset: number) { if (!validDay(day) || !Number.isInteger(offset))
    throw Error('日期无效'); return new Date(+new Date(day + 'T00:00:00Z') + offset * 86400000).toISOString().slice(0, 10); }
const bounded = (v: unknown, max: number) => { if (typeof v !== 'string' || v.length > max)
    throw Error('待办内容或格式无效'); return v.trim(); };
export function validateTask(value: unknown): CampusTask {
    const r = value as CampusTask;
    if (!r || typeof r.completed !== 'boolean')
        throw Error('待办格式无效');
    const id = bounded(r.id, 100), title = bounded(r.title, 100), course = bounded(r.course, 100), notes = bounded(r.notes, 1000);
    if (!id || !title)
        throw Error('请填写待办标题');
    if (r.deadline !== null) {
        if (typeof r.deadline !== 'string')
            throw Error('截止时间无效');
        beijingTimestamp(r.deadline);
    }
    if (r.remindMinutes !== null && ![0, 5, 10, 30, 60, 1440].includes(r.remindMinutes))
        throw Error('提醒时间无效');
    for (const key of ['createdAt', 'updatedAt'] as const)
        if (typeof r[key] !== 'string' || r[key].length > 64 || Number.isNaN(Date.parse(r[key])))
            throw Error('待办时间戳无效');
    const plannedAt = r.plannedAt ?? null;
    if (plannedAt !== null) {
        if (typeof plannedAt !== 'string')
            throw Error('计划时间无效');
        beijingTimestamp(plannedAt);
    }
    const plannedDay = plannedAt ? null : r.plannedDay ?? null;
    if (plannedDay !== null && (typeof plannedDay !== 'string' || !validDay(plannedDay))) throw Error('计划日期无效');
    const durationMinutes = r.durationMinutes ?? 30, priority = r.priority ?? 0;
    if (!Number.isInteger(durationMinutes) || durationMinutes < 5 || durationMinutes > 1440 || !Number.isInteger(priority) || priority < 0 || priority > 3)
        throw Error('时长或优先级无效');
    if (r.pinned !== undefined && typeof r.pinned !== 'boolean')
        throw Error('置顶格式无效');
    const steps = r.steps ?? [];
    if (!Array.isArray(steps) || steps.length > 50)
        throw Error('子任务最多50项');
    const cleanSteps = steps.map(s => { if (!s || typeof s.completed !== 'boolean')
        throw Error('子任务格式无效'); const sid = bounded(s.id, 100), st = bounded(s.title, 100); if (!sid || !st)
        throw Error('子任务内容为空'); return { id: sid, title: st, completed: s.completed }; });
    if (new Set(cleanSteps.map(s => s.id)).size !== cleanSteps.length)
        throw Error('子任务编号重复');
    const repeat = r.repeat ?? null;
    if (repeat && (!['daily', 'weekdays', 'weekly', 'days', 'interval'].includes(repeat.kind) || !Number.isInteger(repeat.interval) || repeat.interval < 1 || repeat.interval > 365 || !Array.isArray(repeat.weekdays) || repeat.weekdays.some(d => !Number.isInteger(d) || d < 1 || d > 7) || (repeat.kind === 'days' && !repeat.weekdays.length)))
        throw Error('重复规则无效');
    if (repeat && !plannedAt && !plannedDay && !r.deadline)
        throw Error('重复任务需设置计划时间或截止时间');
    const reminders = r.reminders ?? (r.deadline && r.remindMinutes !== null ? [{ id: 'legacy', anchor: 'deadline' as const, minutes: r.remindMinutes }] : []);
    if (!Array.isArray(reminders) || reminders.length > 5)
        throw Error('每项最多5次提醒');
    const cleanReminders = reminders.map(m => { if (!m || !['start', 'deadline', 'absolute'].includes(m.anchor) || !Number.isInteger(m.minutes) || m.minutes < 0 || m.minutes > 525600)
        throw Error('提醒格式无效'); if (m.anchor === 'absolute') {
        if (typeof m.at !== 'string')
            throw Error('提醒时间无效');
        beijingTimestamp(m.at);
    } const mid = bounded(m.id, 100); if (!mid)
        throw Error('提醒编号为空'); return { id: mid, anchor: m.anchor, minutes: m.minutes, ...(m.anchor === 'absolute' ? { at: m.at } : {}) }; });
    if (new Set(cleanReminders.map(m => m.id)).size !== cleanReminders.length)
        throw Error('提醒编号重复');
    const completedAt = r.completedAt ?? null;
    if (completedAt !== null && (typeof completedAt !== 'string' || Number.isNaN(Date.parse(completedAt))))
        throw Error('完成时间无效');
    const snoozedUntil = r.snoozedUntil ?? null;
    if (snoozedUntil !== null) {
        if (typeof snoozedUntil !== 'string')
            throw Error('稍后提醒无效');
        beijingTimestamp(snoozedUntil);
    }
    return { id, title, course, notes, deadline: r.deadline, completed: r.completed, remindMinutes: r.deadline ? r.remindMinutes : null, createdAt: r.createdAt, updatedAt: r.updatedAt, plannedAt, plannedDay, durationMinutes, priority, pinned: r.pinned ?? false, steps: cleanSteps, repeat: repeat ? { kind: repeat.kind, interval: repeat.interval, weekdays: [...new Set(repeat.weekdays)] } : null, reminders: cleanReminders, completedAt, snoozedUntil, ...(r.generatedFrom ? { generatedFrom: bounded(r.generatedFrom, 100) } : {}), ...(r.seriesId ? { seriesId: bounded(r.seriesId, 100) } : {}) };
}
export function validateTaskSnapshot(value: unknown): TaskSnapshot {
    const r = value as TaskSnapshot;
    if (!r || (r.version !== 1 && r.version !== 2) || typeof r.notificationsEnabled !== 'boolean' || !Array.isArray(r.tasks) || r.tasks.length > 500 || typeof r.updatedAt !== 'string' || r.updatedAt.length > 64 || Number.isNaN(Date.parse(r.updatedAt)))
        throw Error('待办备份格式无法识别');
    const tasks = r.tasks.map(validateTask);
    if (new Set(tasks.map(t => t.id)).size !== tasks.length)
        throw Error('待办编号重复');
    return { version: 2, tasks, notificationsEnabled: r.notificationsEnabled, updatedAt: r.updatedAt };
}
export function mergeTaskBackup(current: TaskSnapshot, backup: unknown) { const incoming = validateTaskSnapshot(backup), ids = new Set(current.tasks.map(t => t.id)); return validateTaskSnapshot({ ...current, tasks: [...current.tasks, ...incoming.tasks.filter(t => !ids.has(t.id))] }); }
export function taskReminderPlan(snapshot: TaskSnapshot, now = new Date()) {
    if (!snapshot.notificationsEnabled)
        return [];
    const candidates: {
        task: CampusTask;
        at: Date;
        anchor: string;
    }[] = [];
    for (const task of snapshot.tasks) {
        if (task.completed)
            continue;
        const reminders = task.reminders ?? (task.deadline && task.remindMinutes !== null ? [{ anchor: 'deadline', minutes: task.remindMinutes, at: undefined }] : []);
        for (const m of reminders) {
            const base = m.anchor === 'absolute' ? m.at : m.anchor === 'start' ? task.plannedAt : task.deadline;
            if (base) {
                const at = new Date(beijingTimestamp(base) - (m.anchor === 'absolute' ? 0 : m.minutes * 60000));
                if (+at > +now)
                    candidates.push({ task, at, anchor: m.anchor });
            }
        }
        if (task.snoozedUntil) {
            const at = new Date(beijingTimestamp(task.snoozedUntil));
            if (+at > +now)
                candidates.push({ task, at, anchor: 'snooze' });
        }
    }
    const seen = new Set<string>();
    return candidates.sort((a, b) => +a.at - +b.at).filter(p => { const key = p.task.id + '/' + (+p.at); if (seen.has(key))
        return false; seen.add(key); return true; }).slice(0, 30).map((p, i) => ({ id: 410000 + i, title: `待办提醒：${p.task.title}`, body: `${p.anchor === 'deadline' ? '截止' : p.anchor === 'start' ? '计划开始' : '提醒'} · ${p.task.course || '个人任务'}`, schedule: { at: p.at, allowWhileIdle: true }, actionTypeId: p.task.source === 'chaoxing' ? 'HANDAN_LEARNING' : 'HANDAN_TASK', extra: { owner: 'handan-task', taskId: p.task.id, updatedAt: p.task.updatedAt, source:p.task.source||'personal' } }));
}
export function buildAgenda(series: CourseSeries[], exams: Exam[], tasks: CampusTask[], from: string, days = 7, now = new Date()) {
    if (!validDay(from) || !Number.isInteger(days) || days < 1 || days > 31)
        throw Error('日程日期范围无效');
    const to = shiftDay(from, days), events: AgendaEvent[] = [], seen = new Set<string>();
    const add = (e: AgendaEvent) => { if (e.date >= from && e.date < to && !seen.has(e.id)) {
        events.push(e);
        seen.add(e.id);
    } };
    for (const s of series)
        for (const c of s.courses)
            for (const week of c.weeks) {
                if (!Number.isInteger(week) || week < 1 || week > s.semester.weekCount || c.day < 1 || c.day > 7 || !validDay(s.semester.weekStartDate))
                    continue;
                const day = shiftDay(s.semester.weekStartDate, (week - 1) * 7 + c.day - 1);
                let startAt: number, endAt: number;
                try {
                    startAt = beijingTimestamp(day + 'T' + c.start);
                    endAt = beijingTimestamp(day + 'T' + c.end);
                    if (endAt <= startAt)
                        continue;
                }
                catch {
                    continue;
                }
                add({ id: `${s.source}/${s.semester.id}/${c.id}/${day}/${c.start}`, kind: 'course', title: c.name, date: day, time: `${c.start}–${c.end}`, startAt, endAt, location: c.room, source: s.source === 'school' ? '学校课表缓存' : '个人课表', completed: false, course: {...c,occurrenceWeek:week} });
            }
    let unknownExams = 0;
    for (const e of exams) {
        if (typeof e.date !== 'string' || typeof e.time !== 'string') {
            unknownExams++;
            continue;
        }
        const date = e.date.replaceAll('/', '-');
        if (!validDay(date)) {
            unknownExams++;
            continue;
        }
        const match = e.time.trim().match(/^([0-2]\d:[0-5]\d)\s*[-–—~至]\s*([0-2]\d:[0-5]\d)$/);
        let startAt: number | null = null, endAt: number | null = null;
        if (match)
            try {
                startAt = beijingTimestamp(date + 'T' + match[1]);
                endAt = beijingTimestamp(date + 'T' + match[2]);
                if (endAt <= startAt) {
                    startAt = null;
                    endAt = null;
                }
            }
            catch {
                startAt = null;
                endAt = null;
            }
        add({ id: `exam/${e.name}/${date}/${e.time}/${e.room}`, kind: 'exam', title: e.name, date, time: e.time || '时间待学校发布', startAt, endAt, location: e.room, source: '学校考试缓存', completed: false });
    }
    for (const t of tasks) {
        if(t.source==='chaoxing'&&t.platformKind==='exam'&&t.platformStartAt){const start=beijingTimestamp(t.platformStartAt),end=t.deadline?beijingTimestamp(t.deadline):null;add({id:'learning-exam/'+t.id,kind:'exam',title:t.title,date:t.platformStartAt.slice(0,10),time:t.platformStartAt.slice(11)+'–'+(t.deadline?.slice(11)||'结束未知'),startAt:start,endAt:end,location:t.course,source:'学习通考试',completed:t.completed,taskId:t.id})}
        if (t.plannedDay && !t.plannedAt) add({id:'plan/'+t.id,kind:'task',title:t.title,date:t.plannedDay,time:'当天安排',startAt:null,endAt:null,location:t.course,source:'个人计划',completed:t.completed,taskId:t.id});
        if (t.plannedAt) {
            const start = beijingTimestamp(t.plannedAt);
            add({ id: 'plan/' + t.id, kind: 'task', title: t.title, date: t.plannedAt.slice(0, 10), time: t.plannedAt.slice(11) + ' · ' + (t.durationMinutes ?? 30) + '分钟', startAt: start, endAt: start + (t.durationMinutes ?? 30) * 60000, location: t.course, source: '个人计划', completed: t.completed, taskId: t.id });
        }
        if (!t.deadline || t.source==='chaoxing'&&t.platformKind==='exam'&&t.platformStartAt)
            continue;
        const at = beijingTimestamp(t.deadline);
        add({ id: 'deadline/' + t.id, kind: 'task', title: t.title, date: t.deadline.slice(0, 10), time: t.deadline.slice(11) + ' 截止', startAt: at, endAt: at, location: t.course, source: t.source==='chaoxing'?'学习通截止':'任务截止', completed: t.completed, taskId: t.id });
    }
    events.sort((a, b) => a.date.localeCompare(b.date) || (a.startAt ?? Infinity) - (b.startAt ?? Infinity) || a.id.localeCompare(b.id));
    return { events, unknownExams, overdue: tasks.filter(t => !t.completed && t.deadline && t.deadline.slice(0, 10) < from && beijingTimestamp(t.deadline) < +now), undated: tasks.filter(t => !t.deadline) };
}
