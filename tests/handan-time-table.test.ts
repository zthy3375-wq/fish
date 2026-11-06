import {it,expect} from 'vitest';
import {handanTimeTable} from '../src/domain/handan-time-table';
import {validateTimeTable,periodTimes,defaultState,validateState,newArrangement,flatten} from '../src/domain/schedule';
it('matches all thirteen student-provided 40-minute periods including breaks',()=>{
 const t=handanTimeTable();validateTimeTable(t);expect(t.slots).toHaveLength(13);
 for(const slot of t.slots){const n=(s:string)=>Number(s.slice(0,2))*60+Number(s.slice(3));expect(n(slot.end)-n(slot.start)).toBe(40)}
 expect(periodTimes(t,1,2)).toEqual({start:'08:00',end:'09:25'});
 expect(periodTimes(t,3,5)).toEqual({start:'09:45',end:'11:55'});
 expect(periodTimes(t,6,7)).toEqual({start:'14:30',end:'15:55'});
 expect(periodTimes(t,8,10)).toEqual({start:'16:15',end:'18:25'});
 expect(periodTimes(t,11,13)).toEqual({start:'19:00',end:'21:10'});
});
it('recalculates existing period imports while preserving IDs, custom times and other semesters',()=>{
 const state=defaultState(),term=state.semesters[0],a={...newArrangement(18),startPeriod:6,endPeriod:7,timeMode:'period' as const,start:'14:50',end:'16:45'};
 state.courses=[{id:'existing',semesterId:term.id,name:'既有课程',teacher:'老师',notes:'保留备注',color:'blue',arrangements:[a]},
 {id:'custom',semesterId:term.id,name:'自定义时间',teacher:'',notes:'',color:'blue',arrangements:[{...a,id:'custom-a',timeMode:'custom'}]}];
 const table=handanTimeTable();state.timeTables.push(table);term.timeTableId=table.id;
 const clean=validateState(state),courses=flatten(clean.courses,term.id,table);
 expect(courses[0]).toMatchObject({start:'14:30',end:'15:55',courseId:'existing',notes:'保留备注'});
 expect(courses[1]).toMatchObject({start:'14:50',end:'16:45'});
 expect(clean.timeTables[0].id).toBe('standard-45');
});
