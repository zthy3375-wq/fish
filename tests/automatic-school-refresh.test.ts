import {it,expect} from 'vitest';
import {defaultState} from '../src/domain/schedule';
import {handanTimeTable} from '../src/domain/handan-time-table';
import {previewZhengfangTimetable} from '../src/services/academic-adapters/zhengfang-timetable';
import {refreshSchoolPage} from '../src/services/school-page-import';
import {validateObservation} from '../src/services/academic-diagnostics';
function data(){const state=defaultState(),table=handanTimeTable(),semester={...state.semesters[0],timeTableId:table.id};return {state,preview:previewZhengfangTimetable({kbList:[{kcmc:'课甲',xm:'教师',cdmc:'A',xqj:'1',jcs:'1-2',zcd:'1-16周'}]},{semester,timeTable:table,existing:[]})}}
it('repeated refresh updates the same school semester and preserves content IDs',()=>{const {state,preview}=data();const id=refreshSchoolPage(state,preview),courseId=state.courses[0].id;refreshSchoolPage(state,structuredClone(preview));expect(state.semesters).toHaveLength(2);expect(state.activeSemesterId).toBe(id);expect(state.courses).toHaveLength(1);expect(state.courses[0].id).toBe(courseId);expect(state.courses[0].arrangements[0].end).toBe('09:25')});
it('invalid/empty refresh preserves last successful school data',()=>{const {state,preview}=data();refreshSchoolPage(state,preview);const before=structuredClone(state);expect(()=>refreshSchoolPage(state,{...preview,preview:{...preview.preview,courses:[]}})).toThrow();expect(state).toEqual(before)});
it('only accepts bounded school term selector values in reports',()=>{const observation={container:'kbList',fields:{courseName:true,teacher:true,room:true,weekday:true,periods:true,weeks:true},recordCount:1,invalidCount:0,specialArrangements:false,exportControl:false,frameLimit:false,termYear:'2026',termCode:'3'};expect(validateObservation(observation).termYear).toBe('2026');expect(validateObservation({...observation,termYear:'SECRET'}).termYear).toBeUndefined()});
