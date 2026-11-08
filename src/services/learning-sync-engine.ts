import type { ChaoxingClient, LearningResponse } from './chaoxing-client';
import { applyLearningResponse, type LearningCache, emptyLearning } from '../domain/learning';
import { LearningStore } from './learning-store';
export class LearningSyncEngine {
    private flight: Promise<void> | null = null;
    private epoch = 0;
    private paused = false;
    pauseSync(){this.paused=true;}
    constructor(private client: ChaoxingClient, private store: LearningStore, private publish: (cache: LearningCache) => void, private clock: () => Date = () => new Date(), private pause: (ms: number) => Promise<void> = ms => new Promise(r => setTimeout(r, ms))) { }
    sync(options: {
        login?: boolean;
        force?: boolean;
        courseKeys?: string[];
    } = {}) {
        if (this.flight)
            return this.flight;
        this.paused=false;
        const generation = this.epoch;
        const job = (async () => {
            let cache = await this.store.load();
            if (generation !== this.epoch)
                return;
            if (!options.login && !options.force && !cache.connected)
                return;
            const age = cache.lastAttempt ? +this.clock() - Date.parse(cache.lastAttempt) : Infinity;
            if(!options.login&&cache.issues.connection==='VERIFY')return;
            if(cache.issues.connection==='RATE_LIMIT'&&age<300000&&!options.login)return;
            if (!options.login && (cache.session === 'expired' && !options.force || !options.force && age < 300000))
                return;
            const accept = async (response: LearningResponse) => { if (generation !== this.epoch)
                return; const next = await this.store.change(current => generation === this.epoch ? applyLearningResponse(current, response, this.clock()) : current); if (generation === this.epoch) {
                cache = next;
                this.publish(next);
            } };
            try {
                let cursor = options.courseKeys?0:cache.resumeCursor??0;
                if (options.login) {
                    const result = await this.client.login();
                    await accept(result);
                    if (result.session !== 'valid')
                        return;
                    if(Number.isInteger(result.resumeCursor)&&result.resumeCursor!>=0&&result.resumeCursor!<=200)cursor=result.resumeCursor!;
                }
                const scope=options.courseKeys??(cache.resumeCursor!==undefined?cache.activeCourses??cache.selectedCourses:cache.selectedCourses);
                await this.store.change(c=>generation===this.epoch&&c.accountKey===cache.accountKey?{...c,activeCourses:scope}:c);
                const seen = new Set<number>();
                for (let batch = 0; batch < 201; batch++) {
                    if (generation !== this.epoch||this.paused)
                        return;
                    if (seen.has(cursor))
                        throw Error('学习通同步游标重复');
                    seen.add(cursor);
                    const response = await this.client.syncAll({ courseKeys:scope, cursor, force: options.login || !!options.force });
                    if (generation !== this.epoch)
                        return;
                    await accept(response);
                    if (response.session !== 'valid' || response.code)
                        return;
                    if (response.nextCursor === null || response.nextCursor === undefined)
                        return;
                    if (!Number.isInteger(response.nextCursor) || response.nextCursor <= cursor || response.nextCursor > 200)
                        throw Error('学习通同步范围无法识别');
                    cursor = response.nextCursor;
                    await this.pause(4000);
                }
                throw Error('学习通课程数量超过本轮同步范围');
            }
            catch (e) {
                if (generation !== this.epoch)
                    return;
                const code = (e as {
                    code?: string;
                }).code;
                if (code === 'CANCELLED')
                    return;
                await accept({ session: 'unknown', code: code || 'NETWORK' });
                throw e;
            }
        })();
        this.flight = job.finally(() => { if (this.flight === wrapped)
            this.flight = null; });
        const wrapped = this.flight;
        return wrapped;
    }
    async logout() { this.epoch++; this.flight = null; const result = await this.client.logout(); if (result.session !== 'disconnected')
        throw Error('学习通退出未完成'); const next = await this.store.change(() => emptyLearning()); this.publish(next); }
}
