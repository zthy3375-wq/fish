import { computed, ref } from 'vue';
import { chaoxingClient, chaoxingSupported } from '../services/chaoxing-client';
import { LearningSyncEngine } from '../services/learning-sync-engine';
import { learningStore } from '../services/learning-store';
import { applyLearningResponse, emptyLearning, projectLearning, learningPlan, type LearningCache } from '../domain/learning';
import type { CampusTask } from '../domain/agenda';
export const learningCache = ref(emptyLearning()), learningReady = ref(false), learningBusy = ref(false), learningError = ref('');
export const learningOpening=ref(false);
export const learningTasks = computed(() => projectLearning(learningCache.value));
let initJob: Promise<void> | null = null, operations = 0;
const publish = (cache: LearningCache) => { learningCache.value = cache; };
const engine = new LearningSyncEngine(chaoxingClient, learningStore, publish);
export function initLearning() { if (learningReady.value)
    return Promise.resolve(); if (initJob)
    return initJob; initJob = (async () => { try {
    publish(await learningStore.load());
    learningReady.value = true;
    learningError.value = '';
}
catch {
    learningError.value = '学习通缓存读取失败，原数据保留';
    throw Error(learningError.value);
}
finally {
    initJob = null;
} })(); return initJob; }
export async function syncLearning(options: {
    login?: boolean;
    force?: boolean;
    courseKeys?: string[];
} = {}) { if (!chaoxingSupported()||learningOpening.value&&!options.login)
    return; await initLearning(); learningBusy.value = ++operations > 0; learningError.value = ''; try {
    await engine.sync(options);
}
catch {
    learningError.value = '学习通暂未更新，已保留本机任务';
}
finally {
    learningBusy.value = --operations > 0;
} }
export async function disconnectLearning() { learningBusy.value = ++operations > 0; try {
    await engine.logout();
    learningError.value = '';
}
catch {
    learningError.value = '退出未完成，请重试；本机连接仍保留';
}
finally {
    learningBusy.value = --operations > 0;
} }
export async function saveLearningPlan(task: CampusTask) { const account = learningCache.value.accountKey, id = task.externalId; if (!id || task.id !== `cx:${account}:${id}`)
    throw Error('学习通账号已变化，请重新打开任务'); const plan = learningPlan(task); const cache = await learningStore.change(current => { if (current.accountKey !== account || !current.connected || !current.items.some(i => i.id === id))
    throw Error('学习任务已变化，请重新打开'); return { ...current, plans: { ...current.plans, [id]: plan } }; }); publish(cache); }
export async function openLearningItem(task: CampusTask) { if (!task.externalId)
    throw Error('缺少原始作业关联'); if (learningBusy.value)
    throw Error('学习通正在分批同步，请稍后打开'); learningOpening.value=true;try{await chaoxingClient.openItem({ id: task.externalId });}finally{learningOpening.value=false;} await syncLearning({ force: true,courseKeys:[task.externalId.split('/').slice(0,2).join('/')] }); }
export async function openLearningPortal() { if (learningBusy.value)
    return; try {
    learningOpening.value=true;try{await chaoxingClient.openPortal();}finally{learningOpening.value=false;}
    await syncLearning({ force: true });
}
catch {
    learningError.value = '官方页面未打开，请稍后重试';
} }
export async function openLearningCourse(key: string) {
    if (learningBusy.value || learningOpening.value) return;
    const account = learningCache.value.accountKey;
    if (!learningCache.value.courses.some(c => `${c.courseId}/${c.classId}` === key)) return;
    try {
        learningOpening.value = true;
        const result = await chaoxingClient.openCourse({ key });
        if ('session' in result) {
            const cache = await learningStore.change(current => current.accountKey === account ? applyLearningResponse(current, result) : current);
            publish(cache);
            learningError.value = result.code === 'COURSE_MISSING' ? '官方列表中未找到这门课程，请更新课程列表后重试' : '官方课程尚未打开，请检查连接状态后重试';
            return;
        }
        if (!result.closed || learningCache.value.accountKey !== account) return;
    } catch {
        learningError.value = '官方课程未打开，已有作业保留，请稍后重试';
        return;
    } finally {
        learningOpening.value = false;
    }
    await syncLearning({ force: true, courseKeys: [key] });
}
export function learningIssue() { const issues = learningCache.value.issues; return learningError.value || (learningCache.value.session === 'expired' ? '学习通登录已过期，请重新连接' : issues.connection === 'COURSE_SELECTION' ? '请选择需要同步的课程' : issues.connection === 'RATE_LIMIT' ? '学习通请求较频繁，稍后再刷新' : issues.connection === 'VERIFY' ? '扫描已暂停，请完成官方验证码后继续；已读取作业保留'  : issues.connection ? `学习通尚未更新（${issues.connection}），保留已有任务` : Object.keys(issues).length ? '部分课程或模块尚未更新，保留已有数据' : ''); }

export function pauseLearning(){engine.pauseSync()}
export async function selectLearningCourses(keys:string[]){
 if(learningBusy.value)throw Error('请等待本轮读取结束');
 const cache=await learningStore.change(c=>({...c,selectedCourses:keys.filter(k=>c.courses.some(v=>v.courseId+'/'+v.classId===k)),resumeCursor:undefined,activeCourses:undefined,remaining:0,plannedCount:0,completedCount:0}));publish(cache);
}
