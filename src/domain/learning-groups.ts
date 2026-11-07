import type { LearningCourse, LearningItem } from '../services/chaoxing-client';
import { learningState } from './learning-status';
import { beijingTimestamp } from './agenda';

export const learningCourseKey = (item: Pick<LearningItem, 'courseId' | 'classId'>) => `${item.courseId}/${item.classId}`;

/** Resolve cached feed rows by platform identity, including rows read before the course list. */
export function resolveLearningItems(items: LearningItem[], courses: LearningCourse[]): LearningItem[] {
    const names = new Map(courses.map(c => [learningCourseKey(c), c.name]));
    return items.map(item => ({ ...item, course: names.get(learningCourseKey(item))?.trim() || item.course.trim() || `课程 ${item.courseId}` }));
}

export function groupLearningItems(items: LearningItem[], now = new Date()) {
    const rank = { pending: 0, unknown: 1, closed: 2, submitted: 3 };
    const order = (a: LearningItem, b: LearningItem) => rank[learningState(a, now).key] - rank[learningState(b, now).key]
        || (a.deadline ? beijingTimestamp(a.deadline) : Infinity) - (b.deadline ? beijingTimestamp(b.deadline) : Infinity)
        || a.title.localeCompare(b.title, 'zh-CN') || a.id.localeCompare(b.id);
    const groups = new Map<string, { key: string; name: string; items: LearningItem[]; pending: number; unknown: number; submitted: number; closed: number }>();
    for (const item of items) {
        const key = learningCourseKey(item);
        const group = groups.get(key) ?? { key, name: item.course || `课程 ${item.courseId}`, items: [], pending: 0, unknown: 0, submitted: 0, closed: 0 };
        group.items.push(item);
        group[learningState(item, now).key]++;
        groups.set(key, group);
    }
    for (const group of groups.values()) group.items.sort(order);
    return [...groups.values()].sort((a, b) => order(a.items[0], b.items[0]) || a.name.localeCompare(b.name, 'zh-CN'));
}
