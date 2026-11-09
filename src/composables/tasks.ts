import { reactive, ref, toRaw, watch, computed } from 'vue';
import { Capacitor } from '@capacitor/core';
import { Preferences } from '@capacitor/preferences';
import { LocalNotifications, type ActionPerformed } from '@capacitor/local-notifications';
import { emptyTasks, taskReminderPlan, beijingDay, type TaskSnapshot, type CampusTask } from '../domain/agenda';
import { type TaskFilter, setTaskCompleted } from '../domain/tasks';
import { taskStore } from '../services/task-store';
import {learningTasks,initLearning,saveLearningPlan,openLearningItem} from './learning';
export const allTasks=computed(()=>[...taskSnapshot.value.tasks,...learningTasks.value]);
export const taskSnapshot = ref(emptyTasks()), tasksReady = ref(false), tasksBusy = ref(false), taskError = ref(''), taskReminderStatus = ref('待办提醒未开启');
export const agendaView = reactive({ date: beijingDay(), range: 7, filter: 'all', showCompleted: false, editor: false, editing: '', draft: { title: '', course: '', deadline: '', notes: '', remindMinutes: 30 } });
export const taskView = reactive({ source:'all', mode: 'list', view: 'today', search: '', course: '', sort: 'smart', priority: -1, group: false, quick: '' } as TaskFilter & {
    mode: string;
    quick: string;
});
let writes = 0, viewLoaded = false, actionsReady = false;
let initJob: Promise<void> | null = null, notificationQueue: Promise<unknown> = Promise.resolve(), viewQueue: Promise<unknown> = Promise.resolve();
const VIEW_KEY = 'handan.tasks.view.v2';
watch([taskView, () => agendaView.date, () => agendaView.range, () => agendaView.filter], () => { if (!viewLoaded)
    return; const value = JSON.stringify({ ...taskView, date: agendaView.date, range: agendaView.range, filter: agendaView.filter, quick: taskView.quick.slice(0, 100) }); viewQueue = viewQueue.catch(() => { }).then(() => Preferences.set({ key: VIEW_KEY, value })).catch(() => { }); });
async function loadView() { try {
    const { value } = await Preferences.get({ key: VIEW_KEY });
    if (value) {
        const v = JSON.parse(value);
        if (v && ['today', 'inbox', 'planned', 'due', 'completed'].includes(v.view))
            taskView.view = v.view;
        if (['list', 'timeline'].includes(v?.mode))
            taskView.mode = v.mode;
        if (['smart', 'priority', 'deadline', 'title'].includes(v?.sort))
            taskView.sort = v.sort;
        for (const k of ['search', 'course', 'quick'] as const)
            if (typeof v?.[k] === 'string' && v[k].length <= 100)
                taskView[k] = v[k];
        if (Number.isInteger(v?.priority) && v.priority >= -1 && v.priority <= 3)
            taskView.priority = v.priority;
        if(['all','personal','chaoxing'].includes(v?.source))taskView.source=v.source;
        if (typeof v?.group === 'boolean')
            taskView.group = v.group;
        if (typeof v?.date === 'string' && /^20\d{2}-\d{2}-\d{2}$/.test(v.date))
            agendaView.date = v.date;
        if ([1, 7].includes(v?.range))
            agendaView.range = v.range;
        if (['all', 'course', 'exam', 'task'].includes(v?.filter))
            agendaView.filter = v.filter;
    }
}
catch { } viewLoaded = true; }
export function initTasks() { if (tasksReady.value)
    return Promise.resolve(); if (initJob)
    return initJob; initJob = (async () => { try {
    taskSnapshot.value = await taskStore.load();
    await loadView();
    tasksReady.value = true;
    taskError.value = '';
    await initTaskActions();
    await reconcileTaskReminders();
}
catch {
    taskError.value = '本机待办读取失败，原数据未覆盖';
    throw Error(taskError.value);
}
finally {
    initJob = null;
} })(); return initJob; }
export async function changeTasks(action: () => Promise<TaskSnapshot>) { if (!tasksReady.value)
    throw Error('待办尚未读取，请先重试'); tasksBusy.value = ++writes > 0; try {
    const next = await action();
    taskSnapshot.value = next;
    taskError.value = '';
    await reconcileTaskReminders();
    return next;
}
catch (e) {
    taskError.value = '保存未完成，已保留上次待办：' + (e as Error).message;
    throw e;
}
finally {
    tasksBusy.value = --writes > 0;
} }
export async function reloadTasks() { try {
    taskSnapshot.value = await taskStore.reload();
    tasksReady.value = true;
    taskError.value = '';
    await reconcileTaskReminders();
}
catch {
    taskError.value = '待办读取失败，当前保留上次记录';
} }
export async function handleTaskNotification(event: ActionPerformed) {
    const extra = event.notification.extra;
    if (extra?.owner !== 'handan-task' || !['complete', 'snooze','open'].includes(event.actionId))
        return;
    try {
        if (!tasksReady.value)
            await initTasks();
        if(extra.source==='chaoxing'){await initLearning();const task=learningTasks.value.find(t=>t.id===extra.taskId);if(!task||task.completed||extra.updatedAt!==task.updatedAt)return;if(event.actionId==='open')await openLearningItem(task);else if(event.actionId==='snooze'){const d=new Date(Date.now()+600000);await saveLearningPlan({...task,snoozedUntil:beijingDay(d)+'T'+new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Shanghai',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(d)});await reconcileTaskReminders()}return;}
        if(event.actionId==='open')return;
        await changeTasks(() => taskStore.change(s => { const task = s.tasks.find(t => t.id === extra.taskId); if (!task || task.completed)
            return; if (extra.updatedAt !== task.updatedAt)
            throw Error('任务已更新，请打开待办查看'); if (event.actionId === 'complete')
            setTaskCompleted(s, task.id, true);
        else {
            const date = new Date(Date.now() + 10 * 60000);
            task.snoozedUntil = beijingDay(date) + 'T' + new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Shanghai', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(date);
            task.updatedAt = new Date().toISOString();
        } }));
    }
    catch {
        taskError.value = '通知操作未完成，请在待办中查看；原任务保留';
    }
}
async function initTaskActions() { if (!Capacitor.isNativePlatform() || actionsReady)
    return; try {
    await LocalNotifications.registerActionTypes({ types: [{ id: 'HANDAN_TASK', actions: [{ id: 'complete', title: '完成', foreground: true }, { id: 'snooze', title: '10分钟后提醒', foreground: true }] },{id:'HANDAN_LEARNING',actions:[{id:'open',title:'打开原作业',foreground:true},{id:'snooze',title:'10分钟后提醒',foreground:true}]}] });
    await LocalNotifications.addListener('localNotificationActionPerformed', event => { void handleTaskNotification(event); });
    actionsReady = true;
}
catch {
    taskReminderStatus.value = '通知快捷操作暂不可用，任务仍可正常保存';
} }
export function reconcileTaskReminders(request = false) {
    const snapshot = JSON.parse(JSON.stringify({...toRaw(taskSnapshot.value),tasks:allTasks.value})) as TaskSnapshot;
    const job = notificationQueue.catch(() => { }).then(async () => {
        if (!Capacitor.isNativePlatform()) {
            taskReminderStatus.value = '浏览器可保存任务，后台提醒请使用 Android 客户端';
            return;
        }
        try {
            let p = await LocalNotifications.checkPermissions();
            if (request && snapshot.notificationsEnabled && p.display !== 'granted')
                p = await LocalNotifications.requestPermissions();
            const pending = await LocalNotifications.getPending();
            const own = pending.notifications.filter(n => n.extra?.owner === 'handan-task' || n.id >= 410000 && n.id < 410030);
            if (own.length)
                await LocalNotifications.cancel({ notifications: own.map(n => ({ id: n.id })) });
            if (!snapshot.notificationsEnabled) {
                taskReminderStatus.value = '待办提醒已关闭';
                return;
            }
            if (p.display !== 'granted') {
                taskReminderStatus.value = '通知权限未允许，待办已保存，可在页面查看';
                return;
            }
            await initTaskActions();
            const plan = taskReminderPlan(snapshot);
            if (plan.length)
                await LocalNotifications.schedule({ notifications: plan });
            taskReminderStatus.value = `已安排 ${plan.length} 条近期提醒（最多30条，打开 App 时续排）；节电可能延迟`;
        }
        catch {
            taskReminderStatus.value = '系统提醒调度失败，待办仍保存在本机';
        }
    });
    notificationQueue = job;
    return job;
}
export async function enableTaskReminders(enabled: boolean) { await changeTasks(() => taskStore.change(s => { s.notificationsEnabled = enabled; })); if (enabled)
    await reconcileTaskReminders(true); }

export async function cancelLearningSchedule(task:CampusTask){
 const current=learningTasks.value.find(t=>t.id===task.id);
 if(!current||current.source!=='chaoxing')throw Error('学习通任务已变化，请重新打开');
 tasksBusy.value=++writes>0;
 try{await saveLearningPlan({...current,plannedAt:null,plannedDay:null,snoozedUntil:null});await reconcileTaskReminders()}
 finally{tasksBusy.value=--writes>0}
}
