import {describe,it,expect} from 'vitest';
import type {Course} from '../src/domain/academic';
import {coursesForDay} from '../src/domain/academic';
import {nextOccurrence,courseState} from '../src/domain/presentation';
const course=(id:string,start:string,end:string,name='课程 '+id,weeks=[9]):Course=>({id,name,start,end,day:4,teacher:'教师',room:'实验楼 305',period:'1–2节',weeks,color:'blue'});
const six=[course('6','16:00','17:35'),course('2','09:00','09:50'),course('4','11:00','11:50'),course('1','08:00','08:50'),course('5','14:00','15:35'),course('3','10:00','10:50')];
describe('任意数量课程与连续课边界',()=>{
 it('六节课程全部按时间排序，不依赖三节演示数据',()=>{expect(coursesForDay(six,4,9).map(c=>c.id)).toEqual(['1','2','3','4','5','6']);expect(six[0].id).toBe('6')});
 it('零节课程无当前课与后续课程',()=>{expect(coursesForDay([],4,9)).toEqual([]);expect(nextOccurrence([],new Date(2026,10,5,10))).toBeUndefined()});
 it('单节课程结束后不重复为下一节',()=>{const c=course('1','08:00','08:50');expect(nextOccurrence([c],new Date(2026,10,5,7,59))?.minutes).toBe(1);expect(nextOccurrence([c],new Date(2026,10,5,8,50))).toBeUndefined()});
 it('连续课程交接时上一节已结束，下一节正在进行',()=>{const a=course('a','08:00','09:00'),b=course('b','09:00','10:00'),c=course('c','10:00','11:00');const now=new Date(2026,10,5,9,0);expect(courseState(a,now)).toBe('ended');expect(courseState(b,now)).toBe('current');expect(nextOccurrence([b,c,a],now)?.course.id).toBe('c')});
 it('长课程名称完整保留在数据与详情来源中',()=>{const name='智能制造装备与系统集成课程设计及应用实践 AdvancedManufacturingSystemsIntegrationSuperLongCourseName';const c=course('long','14:00','15:35',name);expect(coursesForDay([c],4,9)[0].name).toBe(name);expect(nextOccurrence([c],new Date(2026,10,5,10,15))?.course.name).toBe(name)});
 it('跨周查找遵循单双周，到学期末停止',()=>{const c=course('even','14:00','15:35','双周课程',[10]);expect(nextOccurrence([c],new Date(2026,10,5,17))?.week).toBe(10);expect(nextOccurrence([c],new Date(2027,0,15))).toBeUndefined()});
});
