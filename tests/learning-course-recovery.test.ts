import { beforeEach, expect, it, vi } from 'vitest';
import fixture from './fixtures/learning/synthetic.json';
import { applyLearningResponse, emptyLearning, type LearningCache } from '../src/domain/learning';

const driver = vi.hoisted(() => ({ cache: null as unknown as LearningCache,
    open: vi.fn(), sync: vi.fn() }));
vi.mock('../src/services/chaoxing-client', () => ({
    chaoxingSupported: () => true,
    chaoxingClient: { openCourse: driver.open, syncAll: driver.sync }
}));
vi.mock('../src/services/learning-store', () => ({ learningStore: {
    load: async () => driver.cache,
    change: async (change: (cache: LearningCache) => LearningCache) => {
        driver.cache = change(driver.cache); return driver.cache;
    }
} }));

beforeEach(() => {
    vi.resetModules(); driver.open.mockReset(); driver.sync.mockReset();
    driver.cache = applyLearningResponse(emptyLearning(), structuredClone(fixture) as any);
    driver.cache.selectedCourses = ['12/34', '56/78'];
    driver.open.mockResolvedValue({ closed: true });
    driver.sync.mockResolvedValue({ ...structuredClone(fixture), nextCursor: null });
});

async function ui() {
    const learning = await import('../src/composables/learning');
    learning.learningCache.value = driver.cache;
    learning.learningReady.value = true;
    return learning;
}

it('official course recovery retries only that course and preserves the followed selection', async () => {
    const learning = await ui();
    await learning.openLearningCourse('12/34');
    expect(driver.open).toHaveBeenCalledExactlyOnceWith({ key: '12/34' });
    expect(driver.sync).toHaveBeenCalledExactlyOnceWith({ courseKeys: ['12/34'], cursor: 0, force: true });
    expect(driver.cache.selectedCourses).toEqual(['12/34', '56/78']);
});

it('a failed official page open neither starts a scan nor removes previous tasks', async () => {
    const learning = await ui(), before = structuredClone(driver.cache.items);
    driver.open.mockRejectedValueOnce(Error('private transport message'));
    await learning.openLearningCourse('12/34');
    expect(driver.sync).not.toHaveBeenCalled();
    expect(driver.cache.items).toEqual(before);
    expect(learning.learningError.value).toContain('已有作业保留');
    expect(learning.learningError.value).not.toContain('private');
});

it('expired account responses retain old tasks and offer reconnection without rereading', async () => {
    const learning = await ui(), before = structuredClone(driver.cache.items);
    driver.open.mockResolvedValueOnce({ session: 'expired', code: 'AUTH' });
    await learning.openLearningCourse('12/34');
    expect(driver.cache.session).toBe('expired');
    expect(driver.cache.items).toEqual(before);
    expect(driver.sync).not.toHaveBeenCalled();
});

it('a page closed after an account switch cannot trigger a scan for the former account', async () => {
    const learning = await ui();
    let close!: (value: unknown) => void;
    driver.open.mockImplementationOnce(() => new Promise(resolve => { close = resolve; }));
    const pending = learning.openLearningCourse('12/34');
    learning.learningCache.value = { ...driver.cache, accountKey: 'bbbbbbbbbbbbbbbbbbbbbbbb' };
    close({ closed: true }); await pending;
    expect(driver.sync).not.toHaveBeenCalled();
});

it('repeated taps and unknown course keys cannot open extra pages', async () => {
    const learning = await ui();
    let close!: (value: unknown) => void;
    driver.open.mockImplementationOnce(() => new Promise(resolve => { close = resolve; }));
    await learning.openLearningCourse('999/999');
    const pending = learning.openLearningCourse('12/34');
    await learning.openLearningCourse('12/34');
    expect(driver.open).toHaveBeenCalledTimes(1);
    close({ closed: true }); await pending;
    expect(learning.learningOpening.value).toBe(false);
});
