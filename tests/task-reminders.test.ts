import { it, expect, vi, beforeEach } from 'vitest';
import { task } from './fixtures/agenda';
const storage = vi.hoisted(() => new Map<string, string>());
const notifications = vi.hoisted(() => ({ checkPermissions: vi.fn(), requestPermissions: vi.fn(), getPending: vi.fn(), cancel: vi.fn(), schedule: vi.fn(), registerActionTypes: vi.fn(), addListener: vi.fn() }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => true,getPlatform:()=> 'android' },registerPlugin:()=>({}) }));
vi.mock('@capacitor/local-notifications', () => ({ LocalNotifications: notifications }));
vi.mock('@capacitor/preferences', () => ({ Preferences: { get: async ({ key }: {
            key: string;
        }) => ({ value: storage.get(key) ?? null }), set: async ({ key, value }: {
            key: string;
            value: string;
        }) => { storage.set(key, value); } } }));
beforeEach(() => { vi.resetModules(); vi.clearAllMocks(); storage.clear(); notifications.checkPermissions.mockResolvedValue({ display: 'granted' }); notifications.getPending.mockResolvedValue({ notifications: [{ id: 300001, extra: { owner: 'handan-course' } }, { id: 410001, extra: { owner: 'handan-task' } }] }); notifications.cancel.mockResolvedValue({}); notifications.schedule.mockResolvedValue({}); notifications.registerActionTypes.mockResolvedValue({}); notifications.addListener.mockResolvedValue({ remove: vi.fn() }); });
it('only cancels task-owned notifications, preserving course reminders and avoiding unsolicited permission prompts', async () => { const m = await import('../src/composables/tasks'); m.taskSnapshot.value.tasks = [task({ deadline: '2099-11-06T18:00' })]; m.taskSnapshot.value.notificationsEnabled = true; await m.reconcileTaskReminders(); expect(notifications.cancel).toHaveBeenCalledWith({ notifications: [{ id: 410001 }] }); expect(notifications.requestPermissions).not.toHaveBeenCalled(); expect(notifications.schedule.mock.calls[0][0].notifications[0].extra.owner).toBe('handan-task'); });
it('denied permissions keep tasks and explain that reminders are unavailable', async () => { notifications.checkPermissions.mockResolvedValue({ display: 'denied' }); const m = await import('../src/composables/tasks'); m.taskSnapshot.value.tasks = [task()]; m.taskSnapshot.value.notificationsEnabled = true; await m.reconcileTaskReminders(); expect(m.taskSnapshot.value.tasks).toHaveLength(1); expect(m.taskReminderStatus.value).toContain('未允许'); expect(notifications.schedule).not.toHaveBeenCalled(); });
it('a notification API failure does not erase personal tasks or reject their saved state', async () => { notifications.getPending.mockRejectedValue(Error('platform')); const m = await import('../src/composables/tasks'); m.taskSnapshot.value.tasks = [task()]; await m.reconcileTaskReminders(); expect(m.taskSnapshot.value.tasks).toHaveLength(1); expect(m.taskReminderStatus.value).toContain('调度失败'); });
it('notification actions reject stale task revisions and never touch course notifications', async () => { const m = await import('../src/composables/tasks'); await m.initTasks(); const { taskStore } = await import('../src/services/task-store'); await m.changeTasks(() => taskStore.upsert(task())); await m.handleTaskNotification({ actionId: 'complete', notification: { id: 300001, title: 'course', body: 'test', extra: { owner: 'handan-course' } } }); expect(m.taskSnapshot.value.tasks[0].completed).toBe(false); await m.handleTaskNotification({ actionId: 'complete', notification: { id: 410001, title: 'task', body: 'test', extra: { owner: 'handan-task', taskId: 'test-task', updatedAt: 'stale' } } }); expect(m.taskSnapshot.value.tasks[0].completed).toBe(false); });
it('notification completion persists and snooze reschedules without requesting permission', async () => { const m = await import('../src/composables/tasks'); const { taskStore } = await import('../src/services/task-store'); await m.initTasks(); await m.changeTasks(() => taskStore.upsert(task())); const event = { actionId: 'snooze', notification: { id: 410000, title: 'task', body: 'test', extra: { owner: 'handan-task', taskId: 'test-task', updatedAt: m.taskSnapshot.value.tasks[0].updatedAt } } }; await m.handleTaskNotification(event); expect(m.taskSnapshot.value.tasks[0].snoozedUntil).toBeTruthy(); expect(notifications.requestPermissions).not.toHaveBeenCalled(); await m.handleTaskNotification({ ...event, actionId: 'complete', notification: { ...event.notification, extra: { ...event.notification.extra, updatedAt: m.taskSnapshot.value.tasks[0].updatedAt } } }); expect(m.taskSnapshot.value.tasks[0].completed).toBe(true); expect((await taskStore.load()).tasks[0].completed).toBe(true); });

it('learning notification actions cannot manufacture submission or mutate personal task completion',async()=>{const m=await import('../src/composables/tasks');await m.initTasks();const learning=await import('../src/composables/learning');const domain=await import('../src/domain/learning');const fixture=(await import('./fixtures/learning/synthetic.json')).default;learning.learningCache.value=domain.applyLearningResponse(domain.emptyLearning(),fixture as import('../src/services/chaoxing-client').LearningResponse);learning.learningReady.value=true;const task=learning.learningTasks.value[0];await m.handleTaskNotification({actionId:'complete',notification:{id:410000,title:'platform',body:'test',extra:{owner:'handan-task',source:'chaoxing',taskId:task.id,updatedAt:task.updatedAt}}});expect(learning.learningTasks.value[0].completed).toBe(false);expect(learning.learningCache.value.items[0].status).toBe('pending');expect(m.taskSnapshot.value.tasks).toHaveLength(0)});
it('cancels a learning schedule persistently, preserves work and notes, and removes only its plan reminder', async()=>{
 const m=await import('../src/composables/tasks'),learning=await import('../src/composables/learning'),domain=await import('../src/domain/learning');
 const fixture=(await import('./fixtures/learning/synthetic.json')).default;
 const cache=domain.applyLearningResponse(domain.emptyLearning(),fixture as import('../src/services/chaoxing-client').LearningResponse);
 const work=domain.projectLearning(cache)[0];
 cache.plans[work.externalId!]=domain.learningPlan({...work,plannedAt:'2099-11-06T12:00',notes:'保留我的笔记',prepared:true,snoozedUntil:'2099-11-06T11:30',reminders:[{id:'start',anchor:'start',minutes:5}]});
 storage.set('handan.learning.chaoxing.v1',JSON.stringify(cache));learning.learningCache.value=cache;learning.learningReady.value=true;
 m.taskSnapshot.value.notificationsEnabled=true;
 await m.cancelLearningSchedule(learning.learningTasks.value[0]);
 const saved=JSON.parse(storage.get('handan.learning.chaoxing.v1')!);
 expect(saved.items).toEqual(cache.items);expect(saved.plans[work.externalId!]).toMatchObject({plannedAt:null,plannedDay:null,snoozedUntil:null,notes:'保留我的笔记',prepared:true});
 expect(learning.learningTasks.value[0].deadline).toBe(work.deadline);expect(learning.learningTasks.value[0].completed).toBe(work.completed);
 expect(notifications.cancel).toHaveBeenCalled();expect(notifications.schedule).not.toHaveBeenCalled();expect(m.tasksBusy.value).toBe(false);
 const {selectTasks}=await import('../src/domain/tasks');expect(selectTasks(learning.learningTasks.value,m.taskView)).toEqual([]);
});
it('failed learning cancellation leaves the old plan visible and resets busy state', async()=>{
 const m=await import('../src/composables/tasks'),learning=await import('../src/composables/learning'),domain=await import('../src/domain/learning');
 const fixture=(await import('./fixtures/learning/synthetic.json')).default;
 const cache=domain.applyLearningResponse(domain.emptyLearning(),fixture as import('../src/services/chaoxing-client').LearningResponse);
 const work=domain.projectLearning(cache)[0];cache.plans[work.externalId!]=domain.learningPlan({...work,plannedDay:'2099-11-06'});learning.learningCache.value=cache;
 const {learningStore}=await import('../src/services/learning-store');const change=vi.spyOn(learningStore,'change').mockRejectedValueOnce(Error('保存失败'));
 await expect(m.cancelLearningSchedule(learning.learningTasks.value[0])).rejects.toThrow('保存失败');expect(learning.learningTasks.value[0].plannedDay).toBe('2099-11-06');expect(m.tasksBusy.value).toBe(false);change.mockRestore();
});
