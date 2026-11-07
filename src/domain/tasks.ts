import { beijingDay, beijingTimestamp, shiftDay, validateTask, type CampusTask, type TaskSnapshot } from './agenda';
export type SmartList = 'today' | 'inbox' | 'planned' | 'due' | 'completed';
export interface TaskFilter {
    source?: 'all' | 'personal' | 'chaoxing';
    view: SmartList;
    search: string;
    course: string;
    sort: 'smart' | 'deadline' | 'priority' | 'title';
    priority: number;
    group: boolean;
}
export const TASK_TEMPLATES = [
    { name: '作业', title: '完成课程作业', duration: 60, steps: ['梳理要求', '完成题目', '检查并提交'] },
    { name: '实验报告', title: '提交实验报告', duration: 90, steps: ['整理实验数据', '分析与结论', '检查格式并提交'] },
    { name: '考试复习', title: '考试复习计划', duration: 60, steps: ['整理考试范围', '复习知识点', '练习与错题回顾'] },
    { name: '论文', title: '论文阶段任务', duration: 90, steps: ['确定提纲', '查阅文献', '完成草稿', '修改与提交'] },
    { name: '报名', title: '完成报名', duration: 15, steps: ['核对条件和截止时间', '准备材料', '提交并确认结果'] },
    { name: '个人事务', title: '个人事务', duration: 30, steps: [] },
];
export function createTask(title: string, id: string, now = new Date()): CampusTask { return validateTask({ id, title, course: '', deadline: null, notes: '', completed: false, remindMinutes: null, createdAt: now.toISOString(), updatedAt: now.toISOString() }); }
export function taskOverdue(t: CampusTask, now = new Date()) { return !t.completed && !!t.deadline && beijingTimestamp(t.deadline) < +now; }
export function selectTasks(tasks: CampusTask[], filter: TaskFilter, now = new Date()) {
    const today = beijingDay(now), soon = shiftDay(today, 7);
    return tasks.filter(t => {
        const plan = t.plannedAt?.slice(0, 10), due = t.deadline?.slice(0, 10);
        const match = filter.view === 'completed' ? t.completed : !t.completed && (filter.view === 'inbox' ? !plan && !due : filter.view === 'today' ? !!plan && plan <= today || !!due && due <= today : filter.view === 'planned' ? !!plan || !!due : !!due && due <= soon);
        return match && (!filter.source || filter.source==='all' || (t.source==='chaoxing'?'chaoxing':'personal')===filter.source) && (!filter.course || t.course === filter.course) && (filter.priority < 0 || (t.priority ?? 0) === filter.priority) && (!filter.search || `${t.title} ${t.course} ${t.notes}`.toLocaleLowerCase().includes(filter.search.trim().toLocaleLowerCase()));
    }).sort((a, b) => {
        if (filter.group && a.course !== b.course)
            return a.course.localeCompare(b.course, 'zh-CN');
        if (!!a.pinned !== !!b.pinned)
            return Number(!!b.pinned) - Number(!!a.pinned);
        const priority = (b.priority ?? 0) - (a.priority ?? 0), deadline = (a.deadline ? beijingTimestamp(a.deadline) : Infinity) - (b.deadline ? beijingTimestamp(b.deadline) : Infinity);
        if (filter.sort === 'title')
            return a.title.localeCompare(b.title, 'zh-CN');
        if (filter.sort === 'priority' && priority)
            return priority;
        if (filter.sort === 'deadline' && deadline)
            return deadline;
        if (filter.sort === 'smart') {
            const overdue = Number(taskOverdue(b, now)) - Number(taskOverdue(a, now));
            if (overdue)
                return overdue;
            if (priority)
                return priority;
            if (deadline)
                return deadline;
        }
        return a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id);
    });
}
function occurrenceId(root: string, day: string) {
    let a = 2166136261, b = 5381;
    for (let i = 0; i < root.length; i++) { const code = root.charCodeAt(i); a = Math.imul(a ^ code, 16777619); b = Math.imul(b, 33) ^ code; }
    return `r-${(a >>> 0).toString(36)}${(b >>> 0).toString(36)}-${day}`;
}
/** A completion creates one future occurrence, preserving the plan/deadline gap. No backlog explosion. */
export function nextOccurrence(task: CampusTask, now = new Date()): CampusTask | null {
    if (!task.repeat)
        return null;
    const base = task.plannedAt || task.deadline;
    if (!base)
        return null;
    const day = base.slice(0, 10), today = beijingDay(now), rule = task.repeat;
    for (let offset = 1; offset <= 36600; offset++) {
        const next = shiftDay(day, offset);
        if (next < today || beijingTimestamp(next + 'T' + base.slice(11)) <= +now)
            continue;
        const weekday = new Date(next + 'T12:00:00Z').getUTCDay() || 7;
        if (rule.kind === 'weekdays' && weekday > 5 || rule.kind === 'weekly' && offset % 7 !== 0 || rule.kind === 'interval' && offset % rule.interval !== 0 || rule.kind === 'days' && !rule.weekdays.includes(weekday))
            continue;
        const move = (v: string | null | undefined) => v ? shiftDay(v.slice(0, 10), offset) + v.slice(10) : null;
        const stamp = now.toISOString();
        return validateTask({ ...task, id: occurrenceId(task.seriesId || task.id, next), seriesId: task.seriesId || task.id, generatedFrom: task.id, plannedAt: move(task.plannedAt), deadline: move(task.deadline), snoozedUntil: null, completed: false, completedAt: null, createdAt: stamp, updatedAt: stamp, steps: task.steps?.map(s => ({ ...s, completed: false })), reminders: task.reminders?.map(m => m.anchor === 'absolute' ? { ...m, at: move(m.at)! } : m) });
    }
    throw Error('未找到有效的下次重复日期，请检查规则');
}
export function setTaskCompleted(s: TaskSnapshot, id: string, completed: boolean, now = new Date()) {
    const task = s.tasks.find(t => t.id === id);
    if (!task)
        throw Error('任务已不存在，请重新读取');
    if (task.completed === completed)
        return;
    if (completed) {
        const next = nextOccurrence(task, now);
        if (next && !s.tasks.some(t => t.id === next.id))
            s.tasks.push(next);
        task.completed = true;
        task.completedAt = now.toISOString();
        task.snoozedUntil = null;
    }
    else {
        const next = s.tasks.find(t => t.generatedFrom === id);
        if (next) {
            if (next.completed || next.updatedAt !== next.createdAt)
                throw Error('下次重复任务已修改，请先处理下次任务再撤销');
            s.tasks = s.tasks.filter(t => t.id !== next.id);
        }
        task.completed = false;
        task.completedAt = null;
    }
    task.updatedAt = now.toISOString();
}
export function replanTask(task: CampusTask, day: string, now = new Date()) { task.plannedAt = day + 'T' + (task.plannedAt?.slice(11) || '09:00'); task.snoozedUntil = null; task.updatedAt = now.toISOString(); return task; }
export function taskSummary(tasks: CampusTask[], now = new Date()) {
    const f: TaskFilter = { view: 'today', search: '', course: '', sort: 'smart', priority: -1, group: false };
    const today = selectTasks(tasks, f, now), due = selectTasks(tasks, { ...f, view: 'due' }, now);
    const ids = new Set(today.map(t => t.id));
    return { today, due, overdue: tasks.filter(t => taskOverdue(t, now)), important: [...today, ...due.filter(t => !ids.has(t.id))].slice(0, 2) };
}
