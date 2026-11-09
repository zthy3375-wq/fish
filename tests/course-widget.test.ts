import {describe,it,expect} from 'vitest';
import {widgetSnapshot} from '../src/services/course-widget';
import {defaultState} from '../src/domain/schedule';
import type {Course} from '../src/domain/academic';
describe('desktop course snapshot',()=>{
 it('only mirrors display data and exact effective weeks, without account details',()=>{
  const course={id:'private-id',notes:'private notes',name:'数学',day:2,weeks:[1,3,5],room:'D101',teacher:'教师',start:'08:00',end:'09:25',color:'blue',period:'1-2'} as Course;
  const value=JSON.parse(widgetSnapshot(defaultState().semesters[0],[course]));
  expect(value.courses[0].weeks).toEqual([1,3,5]);expect(value.courses[0].notes).toBeUndefined();expect(value.courses[0].id).toBeUndefined();
 });
 it('distinguishes a never-configured timetable from a valid empty semester',()=>{
  expect(JSON.parse(widgetSnapshot(defaultState().semesters[0],[],false)).ready).toBe(false);
  expect(JSON.parse(widgetSnapshot(defaultState().semesters[0],[])).ready).toBe(true);
 });
});
