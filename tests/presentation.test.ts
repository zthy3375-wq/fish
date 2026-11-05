import {describe,it,expect} from 'vitest';
import {nextOccurrence,courseState,untilLabel,upcomingExams} from '../src/domain/presentation';
import {mockAcademicProvider} from '../src/services/academic';
import {parseRoute} from '../src/composables/navigation';
describe('课程呈现与跨日边界',()=>{
 it('当前课与结束课按时间边界区分',async()=>{const c=(await mockAcademicProvider.load()).courses[0];expect(courseState(c,new Date(2026,10,2,7,59))).toBe('scheduled');expect(courseState(c,new Date(2026,10,2,8))).toBe('current');expect(courseState(c,new Date(2026,10,2,9,35))).toBe('ended');expect(courseState(c,new Date(2026,10,2,8),false)).toBe('scheduled')});
 it('正在上的课不冒充下一节，计算真实剩余分钟',async()=>{const d=await mockAcademicProvider.load();const n=nextOccurrence(d.courses,new Date(2026,10,5,8,30));expect(n?.course.name).toBe('程序设计基础');expect(n?.minutes).toBe(90)});
 it('今日全部结束后寻找明日课程',async()=>{const n=nextOccurrence((await mockAcademicProvider.load()).courses,new Date(2026,10,5,20));expect(n?.course.day).toBe(5);expect(n?.date.getDate()).toBe(6)});
 it('周五结束后跳过周末，教学周随日期推进',async()=>{const n=nextOccurrence((await mockAcademicProvider.load()).courses,new Date(2026,10,6,20));expect(n?.date.getDate()).toBe(9);expect(n?.week).toBe(10)});
 it('双周实验规则与学期终点不会无限循环',async()=>{const d=await mockAcademicProvider.load();expect(nextOccurrence(d.courses,new Date(2026,10,13,12))?.course.name).toBe('程序设计实验');expect(nextOccurrence(d.courses,new Date(2027,2,1))).toBeUndefined()});
 it('空课表和学期开始前也可处理',async()=>{expect(nextOccurrence([],new Date(2026,10,5))).toBeUndefined();expect(nextOccurrence((await mockAcademicProvider.load()).courses,new Date(2026,8,6,10))?.date.getDate()).toBe(7)});
 it('倒计时文本边界与考试排序正确',()=>{expect(untilLabel(20)).toBe('20 分钟后开始');expect(untilLabel(60)).toBe('1 小时后开始');expect(untilLabel(1440)).toBe('1 天后开始');expect(upcomingExams([{date:'2026-10-01'},{date:'2026-12-01'},{date:'2026-11-05'}],new Date(2026,10,5))).toEqual([{date:'2026-11-05'},{date:'2026-12-01'}])});
});
describe('路由恢复',()=>{it('保留三个模块，兼容无效地址',()=>{expect(parseRoute('#/academic/schedule')).toEqual({page:'academic',section:'schedule'});expect(parseRoute('#/profile')).toEqual({page:'profile',section:'overview'});expect(parseRoute('#/unknown/path')).toEqual({page:'home',section:'overview'});expect(parseRoute('#/academic/missing')).toEqual({page:'academic',section:'overview'})})});
