import {describe,it,expect} from 'vitest';
import {dateSelection,dateForWeek,currentRoomPeriod,freeRuns,roomQueryKey,isRoomDate} from '../src/domain/classrooms';
import {roomOptions,roomQuery} from './fixtures/classrooms/data';
describe('classroom date and availability semantics',()=>{
 it('uses the school September 14 calendar instead of personal September 7',()=>{expect(dateSelection('2026-11-06',roomOptions)).toEqual({week:8,weekday:5});expect(dateForWeek(8,5,roomOptions)).toBe('2026-11-06')});
 it('rejects impossible dates, unopened weeks and semester boundaries',()=>{expect(isRoomDate('2026-02-30')).toBe(false);expect(()=>dateSelection('2026-09-13',roomOptions)).toThrow();expect(()=>dateSelection('2027-01-25',roomOptions)).toThrow()});
 it('now means an actual Beijing-time teaching period; breaks are not called current classes',()=>{expect(currentRoomPeriod(roomOptions.periods,new Date('2026-11-06T00:00:00Z'))).toBe(1);expect(currentRoomPeriod(roomOptions.periods,new Date('2026-11-06T01:25:00Z'))).toBeNull()});
 it('only joins adjacent confirmed-free periods; occupied and unknown split runs',()=>{const slots=['free','free','unknown','free','occupied','free'].map((state,i)=>({number:i+1,start:'08:00',end:'08:40',state:state as 'free'|'unknown'|'occupied'}));expect(freeRuns(slots).map(r=>[r.start,r.end,r.count])).toEqual([[1,2,2],[4,4,1],[6,6,1]])});
 it('different date, building and periods never share a cache key',()=>{const key=roomQueryKey(roomQuery);for(const change of [{date:'2026-11-07'},{buildingId:'b2'},{endPeriod:3}])expect(roomQueryKey({...roomQuery,...change})).not.toBe(key)});
});
