import { Capacitor, registerPlugin } from '@capacitor/core';
export interface LearningCourse {
    courseId: string;
    classId: string;
    name: string;
    teacher: string;
}
export interface LearningItem {
    id: string;
    courseId: string;
    classId: string;
    workId: string;
    kind: 'homework' | 'exam';
    title: string;
    course: string;
    status: 'pending' | 'submitted' | 'closed' | 'unknown';
    statusText: string;
    deadline: string | null;
    startAt: string | null;
    timeText: string;
    description: string;
    hasLink: boolean;
    updatedAt?: string;
    firstSeenAt?: string;
    seenAt?: string;
    stale?: boolean;
}
export interface LearningNotice {
    id: string;
    title: string;
    content: string;
    sender: string;
    publishedText: string;
}
export interface LearningResponse {
    session: 'valid' | 'expired' | 'unknown' | 'disconnected';
    accountKey?: string;
    code?: string;
    courses?: LearningCourse[];
    coursesComplete?: boolean;
    diagnostics?: Record<string, unknown>;
    items?: LearningItem[];
    courseResults?: {
        key: string;
        status: 'ok' | 'partial' | 'error';
        complete?: boolean;
        count?: number;
        code?: string;
    }[];
    resumeCursor?: number;
    plannedCount?: number;
    completedCount?: number;
    nextCursor?: number | null;
    remainingCount?: number;
    allWork?: string;
    exams?: {
        status: string;
        items?: LearningItem[];
        code?: string;
    };
    notices?: {
        status: string;
        data?: LearningNotice[];
        code?: string;
    };
}
export interface ChaoxingClient {
    login(): Promise<LearningResponse>;
    syncAll(options?: {
        courseKeys?: string[];
        cursor: number;
        force: boolean;
        includeExtras?: boolean;
    }): Promise<LearningResponse>;
    getSessionState(): Promise<LearningResponse>;
    openItem(options: {
        id: string;
    }): Promise<unknown>;
    openPortal(): Promise<unknown>;
    openCourse(options: { key: string }): Promise<LearningResponse | { closed: boolean }>;
    logout(): Promise<LearningResponse>;
}
export const chaoxingClient = registerPlugin<ChaoxingClient>('ChaoxingClient');
export const chaoxingSupported = () => Capacitor.getPlatform() === 'android';
