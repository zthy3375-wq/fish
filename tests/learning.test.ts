import { it, expect, vi } from 'vitest';
import fixture from './fixtures/learning/synthetic.json';
import { applyLearningResponse, emptyLearning, projectLearning, learningPlan, validateLearningCache, validateLearningItem } from '../src/domain/learning';
import type { LearningResponse } from '../src/services/chaoxing-client';
import { LearningSyncEngine } from '../src/services/learning-sync-engine';
import { LearningStore } from '../src/services/learning-store';
import { selectTasks, type TaskFilter } from '../src/domain/tasks';
import { task } from './fixtures/agenda';
import { taskReminderPlan, emptyTasks, buildAgenda } from '../src/domain/agenda';
const now = new Date('2026-11-06T04:00:00Z');
const response = () => JSON.parse(JSON.stringify(fixture)) as LearningResponse;
const populated = () => applyLearningResponse(emptyLearning(), response(), now);
it('stable platform identity deduplicates refreshes while preserving user-owned planning', () => { const first = populated(), task = projectLearning(first)[0]; first.plans[task.externalId!] = learningPlan({ ...task, plannedAt: '2026-11-06T15:00', priority: 3, notes: '个人复习备注', reminders: [{ id: 'r', anchor: 'deadline', minutes: 30 }] }); const r = response(); r.items![0].deadline = '2026-11-08T19:00'; const next = applyLearningResponse(first, r, now); expect(next.items).toHaveLength(1); expect(projectLearning(next)[0]).toMatchObject({ deadline: '2026-11-08T19:00', plannedAt: '2026-11-06T15:00', priority: 3, notes: '个人复习备注', completed: false }); expect(projectLearning(next)[0].reminders).toHaveLength(1); });
it('platform submission changes completion and a local checkbox cannot manufacture a submitted record', () => { const r = response(); r.items![0].status = 'submitted'; r.items![0].statusText = '待批阅'; const next = applyLearningResponse(populated(), r, now); expect(projectLearning(next)[0].completed).toBe(true); expect(learningPlan({ ...projectLearning(next)[0], completed: false })).not.toHaveProperty('completed'); });
it('incomplete refresh retains the last known deadline with stale provenance', () => { const r = response(); r.items![0].deadline = null; r.items![0].timeText = '11-07 18:00'; const next = applyLearningResponse(populated(), r, now); expect(projectLearning(next)[0].deadline).toBe(populated().items[0].deadline); expect(next.items[0].stale).toBe(true); expect(next.items[0].timeText).toBe('11-07 18:00'); });
it('empty and partial responses never erase older work or claim disappearance means submission', () => { const r = response(); r.items = []; const next = applyLearningResponse(populated(), r, now); expect(next.items).toHaveLength(1); expect(next.items[0].stale).toBe(true); expect(projectLearning(next)[0].completed).toBe(false); r.courseResults![0].status = 'error'; r.courseResults![0].code = 'WORK_ENC'; const partial = applyLearningResponse(populated(), r, now); expect(partial.items).toHaveLength(1); expect(partial.issues['12/34']).toBe('WORK_ENC'); });
it('expired sessions retain the last data with stale provenance', () => { const before = populated(); const next = applyLearningResponse(before, { session: 'expired', code: 'AUTH' }, now); expect(next.items).toEqual(before.items); expect(projectLearning(next)[0].platformStale).toBe(true); });
it('switching accounts clears all old course data and user plans', () => { const first = populated(); first.plans['12/34/homework/78'] = learningPlan(projectLearning(first)[0]); const r = response(); r.accountKey = 'bbbbbbbbbbbbbbbbbbbbbbbb'; r.items = []; r.courses = []; r.notices = { status: 'ok', data: [] }; const next = applyLearningResponse(first, r, now); expect(next.items).toEqual([]); expect(next.plans).toEqual({}); expect(next.notices).toEqual([]); });
it('rejects malformed IDs, impossible dates and unsupported payloads without mutating cache', () => { const before = populated(), original = JSON.stringify(before); const r = response(); r.items![0].workId = 'wrong'; expect(() => applyLearningResponse(before, r, now)).toThrow(); expect(JSON.stringify(before)).toBe(original); expect(() => validateLearningItem({ ...fixture.items[0], deadline: '2026-02-30T12:00' })).toThrow(); expect(() => validateLearningCache({ version: 9 })).toThrow(); });
it('personal tasks and learning tasks share filters without merging their storage identities', () => { const cx = projectLearning(populated())[0], personal = task(); const filter: TaskFilter = { view: 'due', search: '', course: '', sort: 'smart', priority: -1, group: false, source: 'chaoxing' }; expect(selectTasks([cx, personal], filter, now)).toEqual([cx]); expect(selectTasks([cx, personal], { ...filter, source: 'personal' }, now)).toEqual([personal]); expect(cx.id.startsWith('cx:')).toBe(true); });
it('learning reminders can open or snooze but use no manual-complete action category', () => { const cx = projectLearning(populated())[0]; cx.reminders = [{ id: 'deadline', anchor: 'deadline', minutes: 30 }]; const plan = taskReminderPlan({ ...emptyTasks(), notificationsEnabled: true, tasks: [cx] }, now); expect(plan[0].actionTypeId).toBe('HANDAN_LEARNING'); expect(plan[0].extra.taskId).toBe(cx.id); });
it('platform exams use original start/end timestamps on the shared timeline', () => { const r = response(); r.items![0] = { ...r.items![0], id: '12/34/exam/78', kind: 'exam', startAt: '2026-11-07T09:00', deadline: '2026-11-07T11:00' }; const tasks = projectLearning(applyLearningResponse(emptyLearning(), r, now)); const events = buildAgenda([], [], tasks, '2026-11-07', 1, now).events; expect(events).toHaveLength(1); expect(events[0].kind).toBe('exam'); expect(events[0].endAt! - events[0].startAt!).toBe(7200000); });
function harness() { let value: string | null = null; const store = new LearningStore(async () => value, async (v) => { value = v; }); const client = { login: vi.fn(async () => response()), syncAll: vi.fn(async (_?: unknown) => response()), logout: vi.fn(async () => ({ session: 'disconnected' as const })), getSessionState: vi.fn(), openItem: vi.fn(), openPortal: vi.fn() }; const publish = vi.fn(); const engine = new LearningSyncEngine(client, store, publish, () => now, async () => { }); return { store, client, publish, engine, get value() { return value; } }; }
it('one login automatically reads work, coalesces duplicate syncs and throttles repeated entry refreshes', async () => { const h = harness(); await h.engine.sync({ login: true }); expect(h.client.login).toHaveBeenCalledTimes(1); expect(h.client.syncAll).toHaveBeenCalledTimes(1); await Promise.all([h.engine.sync(), h.engine.sync()]); expect(h.client.syncAll).toHaveBeenCalledTimes(1); expect((await h.store.load()).items).toHaveLength(1); });
it('pagination is sequential and a single course failure preserves all cached successful courses', async () => { const h = harness(); h.client.syncAll.mockResolvedValueOnce({ ...response(), nextCursor: 6, remainingCount: 1 }).mockResolvedValueOnce({ ...response(), items: [], courseResults: [{ key: '12/34', status: 'error', code: 'NETWORK' }], nextCursor: null }); await h.engine.sync({ login: true }); expect(h.client.syncAll.mock.calls.map(args => (args[0] as {
    cursor: number;
}).cursor)).toEqual([0, 6]); expect((await h.store.load()).items).toHaveLength(1); expect((await h.store.load()).issues['12/34']).toBe('NETWORK'); });
it('offline refresh and corrupt storage never become a false successful empty snapshot', async () => { const h = harness(); await h.engine.sync({ login: true }); h.client.syncAll.mockRejectedValueOnce(Error('network')); await expect(h.engine.sync({ force: true })).rejects.toThrow(); expect((await h.store.load()).items).toHaveLength(1); const write = vi.fn(); const broken = new LearningStore(async () => '{broken', write); await expect(broken.change(() => emptyLearning())).rejects.toThrow(); expect(write).not.toHaveBeenCalled(); });
it('logout invalidates an in-flight response so it cannot resurrect another account cache', async () => { const h = harness(); await h.engine.sync({ login: true }); let finish: (v: LearningResponse) => void = () => { }; h.client.syncAll.mockImplementationOnce(() => new Promise(resolve => { finish = resolve; })); const flight = h.engine.sync({ force: true }); await vi.waitFor(() => expect(h.client.syncAll).toHaveBeenCalledTimes(2)); await h.engine.logout(); finish(response()); await flight; expect((await h.store.load()).connected).toBe(false); expect((await h.store.load()).items).toEqual([]); });
it('unchanged refresh preserves change timestamps but records a fresh observation', () => { const before = populated(); const later = new Date(+now + 600000); const next = applyLearningResponse(before, response(), later); expect(next.items[0].updatedAt).toBe(before.items[0].updatedAt); expect(next.items[0].seenAt).toBe(later.toISOString()); expect(next.items[0].firstSeenAt).toBe(now.toISOString()); });
it('a verified empty all-work page marks retained records stale instead of erasing them', () => { const r = response(); r.items = []; r.courseResults = []; r.allWork = 'complete'; const next = applyLearningResponse(populated(), r, now); expect(next.items).toHaveLength(1); expect(next.items[0].stale).toBe(true); });
it('connection feedback only keeps bounded structural fields without credentials or account identifiers', () => { const next = applyLearningResponse(emptyLearning(), { session: 'unknown', code: 'COURSES_SCHEMA', diagnostics: { Cookie: 'SECRET', enc: 'SECRET', accountKey: 'SECRET', httpStatus: 403, courseKeys: ['result', 'channelList', '123456789'], path: '/mycourse/backclazzdata' } }, now); expect(JSON.stringify(next.diagnostics)).not.toContain('SECRET'); expect(next.diagnostics.courseKeys).toBeUndefined(); expect(next.diagnostics.httpStatus).toBe(403); });

it('an observed different account clears old data even when the new course response needs adaptation',()=>{const next=applyLearningResponse(populated(),{session:'unknown',accountKey:'bbbbbbbbbbbbbbbbbbbbbbbb',code:'COURSES_SCHEMA'},now);expect(next.items).toEqual([]);expect(next.plans).toEqual({});expect(next.connected).toBe(false)});

it('verification suspends after publishing partial rows and resumes from the blocked course',async()=>{
 let raw:string|null=null;const store=new LearningStore(async()=>raw,async value=>{raw=value});let cache=emptyLearning();
 const blocked={...response(),code:'VERIFY',resumeCursor:2,nextCursor:null,remainingCount:5};
 const client={login:vi.fn().mockResolvedValue({...response(),items:[],resumeCursor:2}),syncAll:vi.fn().mockResolvedValueOnce(blocked).mockResolvedValueOnce({...response(),items:[],nextCursor:null}),logout:vi.fn()} as any;
 const engine=new LearningSyncEngine(client,store,c=>cache=c,()=>now,async()=>{});
 await engine.sync({force:true});expect(cache.items).toHaveLength(1);expect(cache.issues.connection).toBe('VERIFY');expect(cache.remaining).toBe(5);
 await engine.sync({force:true});expect(client.syncAll).toHaveBeenCalledTimes(1);
 await engine.sync({login:true,force:true});expect(client.syncAll.mock.calls[1][0].cursor).toBe(2);expect(cache.items).toHaveLength(1);expect(cache.issues.connection).toBeUndefined();
});

it('scoped refresh sends only requested courses and leaves the saved selection unchanged',async()=>{
 const h=harness();await h.engine.sync({login:true});await h.store.change(c=>({...c,selectedCourses:['12/34','56/78']}));
 await h.engine.sync({force:true,courseKeys:['12/34']});
 expect(h.client.syncAll.mock.calls.at(-1)?.[0]).toMatchObject({cursor:0,courseKeys:['12/34']});
 expect((await h.store.load()).selectedCourses).toEqual(['12/34','56/78']);
});
it('pausing saves the next course cursor and continues from that cursor',async()=>{
 const h=harness();await h.engine.sync({login:true});
 h.client.syncAll.mockImplementationOnce(async()=>{h.engine.pauseSync();return {...response(),nextCursor:1,remainingCount:2,plannedCount:3,completedCount:1}});
 await h.engine.sync({force:true});expect((await h.store.load()).resumeCursor).toBe(1);
 await h.engine.sync({force:true});expect(h.client.syncAll.mock.calls.at(-1)?.[0]).toMatchObject({cursor:1});
});
it('an unknown submission response retains earlier known status and marks it stale',()=>{
 const old=response();old.items![0].status='submitted';old.items![0].statusText='已提交';const first=applyLearningResponse(emptyLearning(),old,now);
 const incoming=response();incoming.items![0].status='unknown';incoming.items![0].statusText='提交状态未知';
 const next=applyLearningResponse(first,incoming,now);expect(next.items[0]).toMatchObject({status:'submitted',statusText:'已提交',stale:true});
 expect(next.courseSync['12/34'].status).toBe('ok');
});
it('verification after a single-course retry resumes the same scope instead of every saved course',async()=>{
 const h=harness();await h.engine.sync({login:true});await h.store.change(c=>({...c,selectedCourses:['12/34','56/78']}));
 h.client.syncAll.mockResolvedValueOnce({...response(),code:'VERIFY',resumeCursor:0,nextCursor:null,remainingCount:1});
 await h.engine.sync({force:true,courseKeys:['12/34']});h.client.login.mockResolvedValueOnce({...response(),resumeCursor:0,nextCursor:undefined});
 await h.engine.sync({login:true});expect(h.client.syncAll.mock.calls.at(-1)?.[0]).toMatchObject({courseKeys:['12/34'],cursor:0});
});

it('date-only planning and prepared state survive cache migration without claiming platform submission',()=>{
 const cache=populated(),t=projectLearning(cache)[0];
 cache.plans[t.externalId!]=learningPlan({...t,plannedDay:'2026-11-06',prepared:true});
 const restored=validateLearningCache(JSON.parse(JSON.stringify(cache)));
 const projected=projectLearning(applyLearningResponse(restored,response(),now))[0];
 expect(projected).toMatchObject({plannedDay:'2026-11-06',plannedAt:null,prepared:true,completed:false,platformStatus:'pending'});
});
