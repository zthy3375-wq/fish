import 'fake-indexeddb/auto';
import {describe,it,expect,vi} from 'vitest';
import {readSchedule,writeSchedule} from '../src/services/schedule-storage';
import {defaultState} from '../src/domain/schedule';
import {schedule,initSchedule,changeSchedule} from '../src/composables/schedule';
describe('durable schedule store',()=>{
it('persists a snapshot and reads after closing database',async()=>{const s=defaultState();s.mode='personal';await writeSchedule(s);expect(await readSchedule()).toEqual(s)});
it('initializes from saved state and serializes concurrent edits',async()=>{await initSchedule();await Promise.all([changeSchedule(s=>s.reminders.minutes=5),changeSchedule(s=>s.mode='personal')]);const saved=await readSchedule();expect(saved?.reminders.minutes).toBe(5);expect(saved?.mode).toBe('personal')});
it('does not update UI or erase data when persistence fails',async()=>{await initSchedule();const before=JSON.parse(JSON.stringify(schedule.value));const spy=vi.spyOn(indexedDB,'open').mockImplementation(()=>{throw Error('Quota exceeded')});await expect(changeSchedule(s=>s.reminders.minutes=30)).rejects.toThrow('Quota');expect(schedule.value).toEqual(before);spy.mockRestore();expect(await readSchedule()).toEqual(before)});
});
