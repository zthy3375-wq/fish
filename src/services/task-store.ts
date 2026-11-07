import { setTaskCompleted } from '../domain/tasks';
import { Preferences } from '@capacitor/preferences';
import { emptyTasks, validateTaskSnapshot, mergeTaskBackup, type TaskSnapshot, type CampusTask } from '../domain/agenda';
export const LEGACY_TASK_KEY = 'handan.personal.tasks.v1';
export const TASK_KEY = 'handan.personal.tasks.v2';
export class TaskStore {
    private queue: Promise<unknown> = Promise.resolve();
    constructor(private read: () => Promise<string | null>, private write: (value: string) => Promise<void>, private readLegacy?: () => Promise<string | null>) { }
    private async readSnapshot() { const value = await this.read(); if (value !== null)
        return validateTaskSnapshot(JSON.parse(value)); const legacy = await this.readLegacy?.(); if (legacy === null || legacy === undefined)
        return emptyTasks(); const migrated = validateTaskSnapshot(JSON.parse(legacy)); await this.write(JSON.stringify(migrated)); return migrated; }
    async load() { if (typeof navigator !== 'undefined' && navigator.locks)
        return navigator.locks.request('handan-task-write', () => this.readSnapshot()); return this.readSnapshot(); }
    async reload() { await this.queue.catch(() => { }); return this.load(); }
    change(mutate: (draft: TaskSnapshot) => void) { const commit = async () => { const next = await this.readSnapshot(); mutate(next); next.updatedAt = new Date().toISOString(); const clean = validateTaskSnapshot(next); await this.write(JSON.stringify(clean)); return clean; }; const job = this.queue.catch(() => { }).then(async () => { let value: TaskSnapshot | undefined; if (typeof navigator !== 'undefined' && navigator.locks)
        await navigator.locks.request('handan-task-write', async () => { value = await commit(); });
    else
        value = await commit(); return value!; }); this.queue = job; return job; }
    upsert(task: CampusTask, expectedUpdatedAt?: string) { return this.change(s => { const index = s.tasks.findIndex(t => t.id === task.id); if (expectedUpdatedAt !== undefined && (index < 0 || s.tasks[index].updatedAt !== expectedUpdatedAt))
        throw Error('任务已在其他操作中更新，请关闭详情后重试'); if (index < 0)
        s.tasks.push(task);
    else
        s.tasks[index] = task; }); }
    complete(id: string, completed: boolean) { return this.change(s => { setTaskCompleted(s, id, completed); }); }
    remove(id: string) { return this.change(s => { s.tasks = s.tasks.filter(t => t.id !== id); }); }
    restore(backup: unknown) { return this.change(s => { s.tasks = mergeTaskBackup(s, backup).tasks; }); }
}
export const taskStore = new TaskStore(async () => { const { value } = await Preferences.get({ key: TASK_KEY }); return value; }, async (value) => { await Preferences.set({ key: TASK_KEY, value }); }, async () => { const { value } = await Preferences.get({ key: LEGACY_TASK_KEY }); return value; });
