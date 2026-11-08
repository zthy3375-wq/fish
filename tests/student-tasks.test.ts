import { describe, it, expect } from 'vitest';
import { createTask, selectTasks, nextOccurrence, setTaskCompleted, replanTask, taskSummary, type TaskFilter } from '../src/domain/tasks';
import { emptyTasks, validateTaskSnapshot, validateTask, taskReminderPlan, buildAgenda } from '../src/domain/agenda';
import { task } from './fixtures/agenda';
const now = new Date('2026-11-06T04:00:00Z'), filter: TaskFilter = { view: 'today', search: '', course: '', sort: 'smart', priority: -1, group: false };
const repeat = (kind: 'daily' | 'weekdays' | 'weekly' | 'days' | 'interval', interval = 1, weekdays = [1, 3]) => ({ kind, interval, weekdays });
describe('student task planning', () => {
    it('quick capture only requires title; no invented deadline or notification', () => { const t = createTask('读一章书', 'a', now); expect(t.deadline).toBeNull(); expect(t.plannedAt).toBeNull(); expect(t.reminders).toEqual([]); expect(selectTasks([t], { ...filter, view: 'inbox' }, now)).toHaveLength(1); });
    it('today includes advance execution, deadlines and unfinished earlier plans', () => { const tasks = [task({ id: 'early', plannedAt: '2026-11-06T15:00', deadline: '2026-11-12T18:00' }), task({ id: 'missed', plannedAt: '2026-11-04T10:00', deadline: null }), task({ id: 'future', plannedAt: '2026-11-08T10:00', deadline: '2026-11-09T12:00' }), task({ id: 'done', completed: true })]; expect(selectTasks(tasks, filter, now).map(t => t.id)).toEqual(['early', 'missed']); expect(taskSummary(tasks, now).today).toHaveLength(2); });
    it('keeps each smart list, search, course filter and completion distinct', () => { const tasks = [createTask('买书', 'inbox', now), task({ id: 'planned', plannedAt: '2026-11-07T13:00', course: '高数', title: '复习高数' }), task({ id: 'complete', completed: true })]; expect(selectTasks(tasks, { ...filter, view: 'completed' }, now).map(t => t.id)).toEqual(['complete']); expect(selectTasks(tasks, { ...filter, view: 'planned', course: '高数', search: '复习' }, now).map(t => t.id)).toEqual(['planned']); expect(selectTasks(tasks, { ...filter, view: 'due' }, now)).toHaveLength(1); });
    it('sorts pinned then priority without treating zero scores as missing', () => { const tasks = [task({ id: 'low', priority: 1, plannedDay:'2026-11-06' }), task({ id: 'high', priority: 3, plannedDay:'2026-11-06' }), task({ id: 'pinned', pinned: true, priority: 0, plannedDay:'2026-11-06' })]; expect(selectTasks(tasks, filter, now).map(t => t.id)).toEqual(['pinned', 'high', 'low']); expect(selectTasks(tasks, { ...filter, priority: 0 }, now).map(t => t.id)).toEqual(['pinned']); });
    it('rescheduling changes execution date and leaves deadline and course untouched', () => { const t = task({ plannedAt: '2026-11-04T14:00' }); const next = replanTask(t, '2026-11-07', now); expect(next.plannedAt).toBe('2026-11-07T14:00'); expect(next.deadline).toBe('2026-11-06T18:00'); expect(next.course).toBe('人工课程'); });
    it('shows plan and submission as two independently dated timeline items', () => { const t = task({ plannedAt: '2026-11-05T10:00', durationMinutes: 90 }); const a = buildAgenda([], [], [t], '2026-11-05', 2, now); expect(a.events.map(e => e.source)).toEqual(['个人计划', '任务截止']); expect(a.events[0].endAt! - a.events[0].startAt!).toBe(90 * 60000); });
    it('legacy v1 migration normalizes metadata without dropping completed/reminder data', () => { const old = { version: 1, tasks: [task({ completed: true })], notificationsEnabled: true, updatedAt: now.toISOString() }; const migrated = validateTaskSnapshot(old); expect(migrated.version).toBe(2); expect(migrated.tasks[0]).toMatchObject({ completed: true, priority: 0, steps: [], reminders: [{ id: 'legacy', anchor: 'deadline', minutes: 30 }] }); expect(migrated.notificationsEnabled).toBe(true); expect(old.version).toBe(1); });
    it.each([{ priority: 4 }, { durationMinutes: 0 }, { plannedAt: '2026-02-30T10:00' }, { steps: [{ id: 's', title: '', completed: false }] }, { repeat: repeat('days', 1, []) }, { reminders: [{ id: 'r', anchor: 'deadline' as const, minutes: -1 }] }])('rejects invalid enriched data %j', fields => { expect(() => validateTask(task(fields))).toThrow(); });
});
describe('repeat rules and completion history', () => {
    it.each([['daily', '2026-11-07T09:00'], ['weekdays', '2026-11-09T09:00'], ['weekly', '2026-11-13T09:00'], ['days', '2026-11-09T09:00'], ['interval', '2026-11-09T09:00']] as const)('%s generates one appropriate next occurrence', (kind, expected) => { const next = nextOccurrence(task({ plannedAt: '2026-11-06T09:00', repeat: repeat(kind, 3) }), now)!; expect(next.plannedAt).toBe(expected); expect(next.completed).toBe(false); });
    it('skips missed occurrences without accumulating a backlog and resets steps', () => { const next = nextOccurrence(task({ plannedAt: '2026-10-01T09:00', deadline: '2026-10-02T18:00', repeat: repeat('interval', 3), steps: [{ id: 's', title: '练习', completed: true }] }), now)!; expect(next.plannedAt).toBe('2026-11-06T09:00'.replace('06', '09')); expect(next.deadline).toBe('2026-11-10T18:00'); expect(next.steps![0].completed).toBe(false); });
    it('completion is idempotent, history preserved, untouched next occurrence undone safely', () => { const s = { ...emptyTasks(), tasks: [validateTask(task({ repeat: repeat('daily') }))] }; setTaskCompleted(s, 'test-task', true, now); setTaskCompleted(s, 'test-task', true, now); expect(s.tasks).toHaveLength(2); expect(s.tasks[0].completedAt).toBe(now.toISOString()); setTaskCompleted(s, 'test-task', false, now); expect(s.tasks).toHaveLength(1); expect(s.tasks[0].completed).toBe(false); });
    it('undo refuses to destroy an already edited future occurrence', () => { const s = { ...emptyTasks(), tasks: [validateTask(task({ repeat: repeat('daily') }))] }; setTaskCompleted(s, 'test-task', true, now); s.tasks[1].updatedAt = '2026-11-06T05:00:00Z'; expect(() => setTaskCompleted(s, 'test-task', false, now)).toThrow('下次重复任务已修改'); expect(s.tasks).toHaveLength(2); expect(s.tasks[0].completed).toBe(true); });
    it('retains interval across year boundaries and does not mutate original task', () => { const original = task({ plannedAt: '2026-12-31T09:00', deadline: '2027-01-02T18:00', repeat: repeat('daily') }); const next = nextOccurrence(original, new Date('2026-12-31T04:00Z'))!; expect(next.plannedAt).toBe('2027-01-01T09:00'); expect(next.deadline).toBe('2027-01-03T18:00'); expect(original.plannedAt).toBe('2026-12-31T09:00'); });
});
describe('multiple reminders', () => {
    it('schedules start, deadline and absolute reminders independently and deduplicates instants', () => { const t = validateTask(task({ plannedAt: '2026-11-06T16:00', reminders: [{ id: 'p', anchor: 'start', minutes: 30 }, { id: 'd', anchor: 'deadline', minutes: 0 }, { id: 'a', anchor: 'absolute', minutes: 0, at: '2026-11-06T15:30' }] })); const plan = taskReminderPlan({ ...emptyTasks(), notificationsEnabled: true, tasks: [t] }, now); expect(plan).toHaveLength(2); expect(plan.map(p => p.schedule.at.toISOString())).toEqual(['2026-11-06T07:30:00.000Z', '2026-11-06T10:00:00.000Z']); expect(plan[0].actionTypeId).toBe('HANDAN_TASK'); expect(plan[0].extra.updatedAt).toBe(t.updatedAt); });
    it('completed tasks and missing anchors never produce reminders; snooze is persisted', () => { const t = validateTask(task({ deadline: null, reminders: [{ id: 'd', anchor: 'deadline', minutes: 0 }], snoozedUntil: '2026-11-06T12:10' })); const s = { ...emptyTasks(), notificationsEnabled: true, tasks: [t] }; expect(taskReminderPlan(s, now)).toHaveLength(1); t.completed = true; expect(taskReminderPlan(s, now)).toHaveLength(0); });
});

it('repeating an imported long task identity remains bounded over multiple cycles',()=>{const original=task({id:'long-'.repeat(20),repeat:repeat('daily')});const next=nextOccurrence(original,now)!;expect(next.id.length).toBeLessThanOrEqual(100);expect(nextOccurrence(next,new Date('2026-11-08T04:00:00Z'))!.id.length).toBeLessThanOrEqual(100)});

// Daily-flow behavior: a date-only plan must not invent a start time or reminder.
it('date-only plans survive backup and produce all-day timeline entries without start reminders',()=>{
 const t=validateTask({...createTask('读书','day-only',now),plannedDay:'2026-11-06',reminders:[{id:'start',anchor:'start',minutes:0}]});
 const copy=validateTaskSnapshot({...emptyTasks(),notificationsEnabled:true,tasks:[t]});
 expect(copy.tasks[0].plannedDay).toBe('2026-11-06');expect(copy.tasks[0].plannedAt).toBeNull();
 expect(taskReminderPlan(copy,now)).toEqual([]);
 expect(buildAgenda([],[],copy.tasks,'2026-11-06',1,now).events[0]).toMatchObject({time:'当天安排',startAt:null,endAt:null});
 expect(selectTasks(copy.tasks,filter,now)).toHaveLength(1);
});
it('deadline alone does not manufacture a today plan and unplanned external work stays in learning',()=>{
 const personal=task({id:'p'}), external={...task({id:'cx'}),source:'chaoxing' as const,platformStatus:'pending',platformStatusText:'未提交'};
 expect(selectTasks([personal,external],filter,now)).toEqual([]);
 expect(selectTasks([personal,external],{...filter,view:'inbox'},now).map(t=>t.id)).toEqual(['p']);
 expect(selectTasks([personal,external],{...filter,view:'due'},now)).toHaveLength(2);
});
it('replanning and repeating a date-only task preserve the absence of a clock time',()=>{
 const t=validateTask({...createTask('阅读','r',now),plannedDay:'2026-11-06',repeat:repeat('daily')});
 const next=nextOccurrence(t,now)!;expect(next.plannedAt).toBeNull();expect(next.plannedDay).toBe('2026-11-07');
 replanTask(t,'2026-11-08',now);expect(t.plannedAt).toBeNull();expect(t.plannedDay).toBe('2026-11-08');
});

it('upcoming deadlines exclude closed or unknown platform history',()=>{
 const records=['pending','closed','unknown'].map(platformStatus=>({...task({id:platformStatus}),source:'chaoxing' as const,platformStatus,platformStatusText:''}));
 expect(selectTasks(records,{...filter,view:'due'},now).map(t=>t.id)).toEqual(['pending']);
});
