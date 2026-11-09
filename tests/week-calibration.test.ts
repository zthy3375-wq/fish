import {describe,it,expect} from 'vitest';
import {firstMondayForWeek,validWeekMonday,calendarKey,correctLegacyCalendar} from '../src/domain/week-calibration';
import {defaultState,semesterWeek} from '../src/domain/schedule';
describe('teaching week calibration',()=>{
 it('maps Nov 9 to week nine without changing course week rules',()=>{const s={...defaultState().semesters[0],startDate:'2026-09-07',weekStartDate:'2026-09-07'};const now=new Date(2026,10,9,12);expect(semesterWeek(now,s)).toBe(10);const d=firstMondayForWeek(now,9);expect(d).toBe('2026-09-14');expect(semesterWeek(now,{...s,weekStartDate:d})).toBe(9);expect(semesterWeek(new Date(2026,10,16),{...s,weekStartDate:d})).toBe(10)});
 it('uses the same Monday throughout the current week',()=>{expect(firstMondayForWeek(new Date(2026,10,15,23),9)).toBe('2026-09-14')});
 it('rejects invalid weeks and calendar dates',()=>{for(const w of [0,41,1.5,NaN])expect(()=>firstMondayForWeek(new Date(),w)).toThrow();expect(validWeekMonday('2026-09-14')).toBe(true);expect(validWeekMonday('2026-09-15')).toBe(false);expect(validWeekMonday('2026-02-30')).toBe(false)});
 it('normalizes school and local academic-year keys',()=>{const s=defaultState().semesters[0];expect(calendarKey({...s,academicYear:'2026–2027'})).toBe(calendarKey({...s,academicYear:'2026-2027'}))});
});

it('migrates only legacy default dates and retains course capacity',()=>{const s={...defaultState().semesters[0],startDate:'2026-09-07',weekStartDate:'2026-09-07',weekCount:21};expect(correctLegacyCalendar(s).weekStartDate).toBe('2026-09-14');expect(correctLegacyCalendar(s).weekCount).toBe(21);expect(correctLegacyCalendar({...s,weekStartDate:'2026-09-21'}).weekStartDate).toBe('2026-09-21');expect(correctLegacyCalendar({...s,academicYear:'2025-2026'}).weekStartDate).toBe('2026-09-07')});
it('uses supplied autumn calendar defaults',()=>{const s=defaultState().semesters[0];expect(s.weekCount).toBe(19);expect(semesterWeek(new Date(2026,10,9),s)).toBe(9);expect(semesterWeek(new Date(2027,0,18),s)).toBe(19)});
