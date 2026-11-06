import type {CampusTask,CourseSeries} from '../../src/domain/agenda';
import {defaultState} from '../../src/domain/schedule';
export const task=(v:Partial<CampusTask>={}):CampusTask=>({id:'test-task',title:'人工待办',course:'人工课程',deadline:'2026-11-06T18:00',notes:'测试备注',completed:false,remindMinutes:30,createdAt:'2026-11-01T00:00:00Z',updatedAt:'2026-11-01T00:00:00Z',...v});
export const series=():CourseSeries=>({semester:{...defaultState().semesters[0],weekStartDate:'2026-09-07'},source:'school',courses:[{id:'c1',name:'人工周五课程',teacher:'',room:'人工教室',day:5,start:'08:00',end:'09:30',period:'1-2',weeks:[9],color:'blue'}]});
