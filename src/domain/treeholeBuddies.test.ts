import {describe,it,expect} from 'vitest';
import {buddyLocalTime,buddyISOTime,buddyDraftValid} from './treeholeBuddies';
describe('campus buddy times',()=>{
 it('keeps Shanghai dates across the UTC day boundary and round trips minutes',()=>{expect(buddyLocalTime('2026-11-16T17:30:00Z')).toBe('2026-11-17T01:30');expect(buddyISOTime('2026-11-17T01:30')).toBe('2026-11-16T17:30:00.000Z');});
 it('rejects impossible or incomplete calendar input without inventing a time',()=>{for(const time of ['2026-02-30T14:00','2026-11-16','2026-13-03T00:00',''])expect(buddyISOTime(time)).toBe('');expect(buddyLocalTime('invalid')).toBe('');});
 it('requires a future date within 90 days and one to twenty additional seats',()=>{const now=Date.parse('2026-11-16T00:00:00Z'),draft={startsAt:'2026-11-16T12:00:00Z',capacity:1,location:'操场'};expect(buddyDraftValid(draft,now)).toBe(true);for(const capacity of [0,21,1.5])expect(buddyDraftValid({...draft,capacity},now)).toBe(false);expect(buddyDraftValid({...draft,location:' '},now)).toBe(false);expect(buddyDraftValid({...draft,startsAt:new Date(now).toISOString()},now)).toBe(false);expect(buddyDraftValid({...draft,startsAt:new Date(now+91*86400_000).toISOString()},now)).toBe(false);});
});
