import {resolveLearningItems} from './learning-groups';
import { beijingTimestamp, validateTask, type CampusTask } from './agenda';
import type { LearningCourse, LearningItem, LearningNotice, LearningResponse } from '../services/chaoxing-client';
export interface LearningPlan {
    plannedAt: string | null;
    durationMinutes: number;
    priority: number;
    pinned: boolean;
    notes: string;
    steps: NonNullable<CampusTask['steps']>;
    reminders: NonNullable<CampusTask['reminders']>;
    snoozedUntil: string | null;
}
export interface LearningCache {
    version: 1;
    connected: boolean;
    accountKey: string;
    session: LearningResponse['session'];
    courses: LearningCourse[];
    items: LearningItem[];
    notices: LearningNotice[];
    plans: Record<string, LearningPlan>;
    lastAttempt: string | null;
    updatedAt: string | null;
    remaining: number;
    resumeCursor?: number;
    issues: Record<string, string>;
    examUpdatedAt: string | null;
    noticeUpdatedAt: string | null;
    diagnostics: Record<string, string | number | string[]>;
}
export const emptyLearning = (): LearningCache => ({ version: 1, connected: false, accountKey: '', session: 'disconnected', courses: [], items: [], notices: [], plans: {}, lastAttempt: null, updatedAt: null, remaining: 0, issues: {}, examUpdatedAt: null, noticeUpdatedAt: null, diagnostics: {} });
export function learningTaskId(account: string, id: string) { return `cx:${account}:${id}`; }
const text = (v: unknown, max: number) => { if (typeof v !== 'string' || v.length > max)
    throw Error('学习数据字段无法识别'); return v; };
const date = (v: unknown) => { if (v === null)
    return null; text(v, 30); beijingTimestamp(v as string); return v as string; };
export function validateLearningItem(raw: unknown): LearningItem { const r = raw as LearningItem; if (!r || !['homework', 'exam'].includes(r.kind) || !['pending', 'submitted', 'closed', 'unknown'].includes(r.status))
    throw Error('学习任务格式需要适配'); for (const k of ['courseId', 'classId', 'workId'] as const)
    if (!/^\d{1,24}$/.test(r[k]))
        throw Error('平台任务编号无效'); if (r.id !== `${r.courseId}/${r.classId}/${r.kind}/${r.workId}`)
    throw Error('平台任务关联不一致'); return { id: r.id, courseId: r.courseId, classId: r.classId, workId: r.workId, kind: r.kind, title: text(r.title, 200), course: text(r.course, 200), status: r.status, statusText: text(r.statusText, 100), deadline: date(r.deadline), startAt: date(r.startAt), timeText: text(r.timeText, 1000), description: text(r.description, 4000), hasLink: r.hasLink === true, ...(typeof r.updatedAt === 'string' ? { updatedAt: r.updatedAt } : {}), ...(typeof r.firstSeenAt === 'string' ? { firstSeenAt: r.firstSeenAt } : {}), ...(typeof r.seenAt === 'string' ? { seenAt: r.seenAt } : {}), stale: r.stale === true }; }
export function validateLearningCourses(raw: unknown): LearningCourse[] { if (!Array.isArray(raw) || raw.length > 200)
    throw Error('课程列表格式需要适配'); return raw.map(r => { if (!r || !/^\d{1,24}$/.test(r.courseId) || !/^\d{1,24}$/.test(r.classId))
    throw Error('课程编号无效'); return { courseId: r.courseId, classId: r.classId, name: text(r.name, 200), teacher: text(r.teacher, 150) }; }); }
export function projectLearning(cache: LearningCache): CampusTask[] { if (!cache.connected || !cache.accountKey)
    return []; return resolveLearningItems(cache.items,cache.courses).map(item => { const plan = cache.plans[item.id]; return { id: learningTaskId(cache.accountKey, item.id), title: item.title, course: item.course || '课程名称待更新', deadline: item.deadline, plannedAt: plan?.plannedAt ?? null, durationMinutes: plan?.durationMinutes ?? 30, priority: plan?.priority ?? 0, pinned: plan?.pinned ?? false, notes: plan?.notes ?? '', steps: plan?.steps ?? [], reminders: plan?.reminders ?? [], snoozedUntil: plan?.snoozedUntil ?? null, repeat: null, completed: item.status === 'submitted', completedAt: null, remindMinutes: null, createdAt: item.firstSeenAt ?? item.updatedAt ?? cache.updatedAt ?? '1970-01-01T00:00:00Z', updatedAt: item.updatedAt ?? cache.updatedAt ?? '2026-01-01T00:00:00Z', source: 'chaoxing', externalId: item.id, platformStatus: item.status, platformStatusText: item.statusText, platformStale: item.stale || cache.session !== 'valid', platformDescription: item.description, platformKind: item.kind, platformStartAt: item.startAt, timeText: item.timeText }; }); }
export function learningPlan(task: CampusTask): LearningPlan { const clean = validateTask({ ...task, id: 'planning', course: '', title: '任务规划', deadline: null, remindMinutes: null, repeat: null }); return { plannedAt: clean.plannedAt ?? null, durationMinutes: clean.durationMinutes ?? 30, priority: clean.priority ?? 0, pinned: clean.pinned ?? false, notes: clean.notes, steps: clean.steps ?? [], reminders: clean.reminders ?? [], snoozedUntil: clean.snoozedUntil ?? null }; }
export function applyLearningResponse(current: LearningCache, response: LearningResponse, now = new Date()): LearningCache {
    if (!['valid', 'expired', 'unknown', 'disconnected'].includes(response.session))
        throw Error('学习通状态无法识别');
    const next = JSON.parse(JSON.stringify(current)) as LearningCache;
    next.lastAttempt = now.toISOString();
    if (response.diagnostics) {
        const safe: Record<string, string | number | string[]> = {};
        for (const key of ['host', 'path', 'httpStatus', 'courseKeys', 'courseChannels', 'workRows', 'workLinks', 'workRejected','workEncInputs','stage','workHost','workPath','workContainers','workFrames','workTaskHandlers']) {
            const value = response.diagnostics[key];
            if (typeof value === 'number' && Number.isFinite(value))
                safe[key] = value;
            else if (typeof value === 'string' && value.length <= 150 && !value.includes('?'))
                safe[key] = value;
            else if (key === 'courseKeys' && Array.isArray(value) && value.every(v => typeof v === 'string' && /^[a-zA-Z_][a-zA-Z_]{0,39}$/.test(v)))
                safe[key] = value.slice(0, 20);
        }
        next.diagnostics = safe;
    }
    if (response.session !== 'valid') {
        if(current.accountKey&&response.accountKey&&/^[a-f0-9]{24}$/.test(response.accountKey)&&current.accountKey!==response.accountKey){const cleared=emptyLearning();cleared.session=response.session;cleared.lastAttempt=now.toISOString();cleared.issues.connection=response.code||'ACCOUNT_CHANGED';cleared.diagnostics=next.diagnostics;return cleared;}
        if(response.code==='CANCELLED')return current;
        next.session = response.session;
        next.issues.connection = response.code || 'NETWORK';
        return next;
    }
    if (!/^[a-f0-9]{24}$/.test(response.accountKey ?? ''))
        throw Error('学习通账号标识无法识别');
    const cache = current.accountKey && current.accountKey !== response.accountKey ? emptyLearning() : next;
    cache.diagnostics=next.diagnostics;
    cache.accountKey = response.accountKey!;
    cache.connected = true;
    cache.session = 'valid';
    cache.lastAttempt = now.toISOString();
    delete cache.issues.connection;
    if(response.code)cache.issues.connection=response.code;
    if(Number.isInteger(response.resumeCursor)&&response.resumeCursor!>=0&&response.resumeCursor!<=200)cache.resumeCursor=response.resumeCursor;
    else if(!response.code)delete cache.resumeCursor;
    if (response.courses !== undefined) {
        const courses = validateLearningCourses(response.courses);
        if (response.coursesComplete === false) {
            cache.courses = [...new Map([...cache.courses, ...courses].map(c => [c.courseId + '/' + c.classId, c])).values()];
            cache.issues.courses = 'COURSES_PARTIAL';
        }
        else {
            cache.courses = courses;
            delete cache.issues.courses;
        }
    }
    const stamp = now.toISOString(), incoming = (response.items ?? []).map(validateLearningItem);
    if (incoming.length > 1000)
        throw Error('学习任务超过本次可处理范围');
    const exams = response.exams?.items?.map(validateLearningItem) ?? [];
    const all = [...incoming, ...exams];
    const map = new Map(cache.items.map(i => [i.id, i]));
    if (response.allWork === 'complete') {
        const found = new Set(incoming.map(i => i.id));
        for (const item of map.values())
            if (item.kind === 'homework' && !found.has(item.id))
                item.stale = true;
    }
    for (const result of response.courseResults ?? []) {
        if (!/^\d{1,24}\/\d{1,24}$/.test(result.key))
            throw Error('课程同步关联无效');
        if (result.status === 'ok' && result.complete === true) {
            delete cache.issues[result.key];
            const found = new Set(all.map(i => i.id));
            for (const item of map.values())
                if (`${item.courseId}/${item.classId}` === result.key && item.kind === 'homework' && !found.has(item.id))
                    item.stale = true;
        }
        else
            cache.issues[result.key] = result.code || 'PARTIAL';
    }
    for (const item of all) {
        const old = map.get(item.id);
        const data = { ...item, course: item.course || old?.course || '' };
        const fields = ['course', 'title', 'status', 'statusText', 'deadline', 'startAt', 'timeText', 'description', 'hasLink'] as const;
        const changed = !old || fields.some(key => data[key] !== old[key]);
        map.set(item.id, { ...data, updatedAt: changed ? stamp : old?.updatedAt ?? stamp, firstSeenAt: old?.firstSeenAt ?? old?.updatedAt ?? stamp, seenAt: stamp, stale: false });
    }
    // No empty response wipes an old course or quietly marks a disappeared task submitted.
    cache.items = [...map.values()];
    if (cache.items.length > 2000)
        throw Error('学习任务缓存已达上限，旧数据保留');
    cache.remaining = Number.isInteger(response.remainingCount) ? Math.max(0, response.remainingCount!) : 0;
    if (response.exams) {
        if (response.exams.status === 'ok') {
            cache.examUpdatedAt = stamp;
            delete cache.issues.exams;
        }
        else
            cache.issues.exams = response.exams.code || 'EXAMS_PARTIAL';
    }
    if (response.notices) {
        if (response.notices.status === 'ok' && Array.isArray(response.notices.data)) {
            const notices = response.notices.data.map(n => ({ id: text(n.id, 100), title: text(n.title, 200), content: text(n.content, 6000), sender: text(n.sender, 100), publishedText: text(n.publishedText, 100) }));
            if (notices.length > 100)
                throw Error('通知列表过长');
            if (notices.length || !cache.notices.length) {
                cache.notices = notices;
                cache.noticeUpdatedAt = stamp;
                delete cache.issues.notices;
            }
            else
                cache.issues.notices = 'EMPTY_RETAINED';
        }
        else
            cache.issues.notices = response.notices.code || 'NOTICES_SCHEMA';
    }
    if (all.length || (response.courseResults ?? []).some(r => r.status === 'ok') || response.allWork === 'complete')
        cache.updatedAt = stamp;
    return cache;
}
export function validateLearningCache(raw: unknown): LearningCache { const r = raw as LearningCache; if (!r || r.version !== 1 || typeof r.connected !== 'boolean' || !Array.isArray(r.items) || r.items.length > 2000 || !Array.isArray(r.notices) || typeof r.plans !== 'object' || !r.plans || !r.issues || typeof r.issues !== 'object')
    throw Error('学习缓存损坏，原数据保留'); const cache = { ...emptyLearning(), ...r, courses: validateLearningCourses(r.courses), items: r.items.map(validateLearningItem) }; if (cache.connected && !/^[a-f0-9]{24}$/.test(cache.accountKey))
    throw Error('学习账号缓存无效'); const clean: Record<string, LearningPlan> = {}; for (const [id, plan] of Object.entries(cache.plans)) {
    if (!cache.items.some(i => i.id === id))
        continue;
    const base = { id: 'planning', title: '任务规划', course: '', deadline: null, completed: false, remindMinutes: null, createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z', ...plan };
    clean[id] = learningPlan(base);
} cache.plans = clean; return cache; }
