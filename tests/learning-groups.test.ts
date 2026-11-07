import { expect, it } from 'vitest';
import { groupLearningItems, resolveLearningItems } from '../src/domain/learning-groups';
import { emptyLearning, projectLearning } from '../src/domain/learning';
import type { LearningItem } from '../src/services/chaoxing-client';
const now = new Date('2026-11-07T08:00:00Z');
const item = (courseId: string, workId: string, status: LearningItem['status'] = 'pending'): LearningItem => ({ id: `${courseId}/34/homework/${workId}`, courseId, classId: '34', workId, kind: 'homework', title: `任务${workId}`, course: '', status, statusText: '', deadline: null, startAt: null, timeText: '', description: '', hasLink: false });
it('backfills previously unnamed feed tasks by course and class without changing their identities or cache', () => {
 const original = item('12','1');
 const courses = [{courseId:'12',classId:'34',name:'大学英语',teacher:''}];
 const resolved = resolveLearningItems([original],courses);
 expect(resolved[0].course).toBe('大学英语');
 expect(resolved[0].id).toBe(original.id);
 expect(original.course).toBe('');
 const cache = {...emptyLearning(),connected:true,accountKey:'a'.repeat(24),items:[original],courses};
 expect(projectLearning(cache)[0].course).toBe('大学英语');
});
it('keeps interleaved work in course folders and submitted work after actionable work', () => {
 const groups = groupLearningItems(resolveLearningItems([item('12','1','submitted'),item('56','2'),item('12','3')],[]),now);
 const group = groups.find(g=>g.key==='12/34')!;
 expect(groups).toHaveLength(2);
 expect(group.items.map(i=>i.workId)).toEqual(['3','1']);
 expect(group.pending).toBe(1);expect(group.submitted).toBe(1);
});
it('does not merge same-named courses across different classes and preserves unknown submission', () => {
 const a = {...item('12','1','unknown'),course:'实验课',deadline:'2026-11-01T12:00'};
 const b = {...item('12','2'),classId:'90',id:'12/90/homework/2',course:'实验课'};
 const groups = groupLearningItems([a,b],now);
 expect(groups).toHaveLength(2);
 expect(groups.find(g=>g.key==='12/34')?.unknown).toBe(1);
 expect(groups.find(g=>g.key==='12/34')?.closed).toBe(0);
});
it('never borrows a name from another class and uses course identity as a readable fallback', () => {
 expect(resolveLearningItems([item('12','1')],[{courseId:'12',classId:'90',name:'其他班级',teacher:''}])[0].course).toBe('课程 12');
});
