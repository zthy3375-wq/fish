import { describe,it,expect } from 'vitest';
import { coursesForDay,nextCourse,weightedAverage,teachingWeek,weekDate } from '../src/domain/academic';
import {mockAcademicProvider} from './fixtures/academic/mock-provider';
import {loadPreferences,savePreferences,defaults} from '../src/services/preferences';
describe('教学数据与时间边界',()=>{
 it('模拟课表按时间排序且周末为空',async()=>{const d=await mockAcademicProvider.load();const list=coursesForDay(d.courses,4,9);expect(list.map(c=>c.start)).toEqual(['08:00','10:00','14:00']);expect(coursesForDay(d.courses,7,9)).toHaveLength(0)});
 it('单双周实验只出现在指定周',async()=>{const d=await mockAcademicProvider.load();expect(coursesForDay(d.courses,5,9)).toHaveLength(1);expect(coursesForDay(d.courses,5,10)).toHaveLength(2)});
 it('下节课排除已结束的课，支持全部结束',async()=>{const d=await mockAcademicProvider.load();const list=coursesForDay(d.courses,4,9);expect(nextCourse(list,'09:40')?.id).toBe('8');expect(nextCourse(list,'15:35')).toBeUndefined()});
 it('平均分按学分加权，空成绩不产生 NaN',()=>{expect(weightedAverage([{name:'A',score:90,credit:3,kind:'必修',term:'x'},{name:'B',score:60,credit:1,kind:'必修',term:'x'}])).toBe(82.5);expect(weightedAverage([])).toBe(0)});
 it('学期首周与周边界正确',()=>{expect(teachingWeek(new Date(2026,8,7),new Date(2026,8,7))).toBe(1);expect(teachingWeek(new Date(2026,8,13),new Date(2026,8,7))).toBe(1);expect(teachingWeek(new Date(2026,10,5),new Date(2026,8,7))).toBe(9);expect(weekDate(9,4)).toBe('11/5')});
 it('数据隔离避免调用者污染演示源',async()=>{const a=await mockAcademicProvider.load();a.courses.length=0;expect((await mockAcademicProvider.load()).courses.length).toBeGreaterThan(0)});
});
describe('存储异常降级',()=>{
 it('没有可用存储时恢复默认且报告保存失败',()=>{expect(loadPreferences()).toEqual(defaults);expect(savePreferences(defaults)).toBe(false)});
 it('损坏的偏好可降级',()=>{Object.defineProperty(globalThis,'localStorage',{configurable:true,value:{getItem:()=>'{broken'}});expect(loadPreferences()).toEqual(defaults)});
 it('校验存储字段',()=>{Object.defineProperty(globalThis,'localStorage',{configurable:true,value:{getItem:()=>JSON.stringify({theme:'invalid',name:42,notifications:'yes'})}});expect(loadPreferences()).toEqual(defaults);Reflect.deleteProperty(globalThis,'localStorage')});
});
