import { beijingTimestamp, type CampusTask } from './agenda';
import type { LearningItem } from '../services/chaoxing-client';
export type LearningFilter = 'all' | 'pending' | 'submitted' | 'closed' | 'unknown';
/** Submission and deadline are independent: passing the deadline never manufactures submission. */
export function learningState(item: Pick<LearningItem,'status'|'statusText'|'deadline'>, now = new Date()) {
 const past = !!item.deadline && beijingTimestamp(item.deadline) < +now;
 if(item.status==='submitted')return {key:'submitted' as const,label:/已完成|已批阅/.test(item.statusText)?'已完成':/待批阅/.test(item.statusText)?'已提交 · 待批阅':'已提交'};
 if(item.status==='closed')return {key:'closed' as const,label:'已截止 · '+(/未交|未提交/.test(item.statusText)?'未提交':'提交状态待核对')};
 if(item.status==='pending')return {key:past?'closed' as const:'pending' as const,label:past?'未提交 · 已逾期':/未开始/.test(item.statusText)?'未开始':'未提交'};
 return {key:'unknown' as const,label:past?'已截止 · 提交状态未知':'提交状态未知'};
}
export function learningTaskState(task:CampusTask,now=new Date()){return learningState({status:(['pending','submitted','closed','unknown'].includes(task.platformStatus??'')?task.platformStatus:'unknown') as LearningItem['status'],statusText:task.platformStatusText??'',deadline:task.deadline},now)}
