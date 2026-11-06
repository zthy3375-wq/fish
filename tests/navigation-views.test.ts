// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import AcademicDetail from '../src/components/AcademicDetail.vue';
import SchoolAcademicRecords from '../src/components/SchoolAcademicRecords.vue';
import {defaultState} from '../src/domain/schedule';
import {scheduleViews,gradeTerm,gradeQuery} from '../src/composables/view-state';
import {academicCache} from '../src/composables/handan-academic';
import {emptyAcademicCache} from '../src/services/academic-sync-engine';
const state=defaultState();
let app:ReturnType<typeof createApp>|undefined,root:HTMLElement;
function mountSchedule(id=state.semesters[0].id){
 root=document.createElement('div');document.body.append(root);
 app=createApp({render:()=>h(AcademicDetail,{semester:{...state.semesters[0],id},table:state.timeTables[0],section:'schedule',mode:'personal',data:{courses:[],grades:[],exams:[],source:'personal'},now:new Date(2026,10,6)})});app.mount(root);
}
function dispose(){app?.unmount();app=undefined;root?.remove()}
beforeEach(()=>{for(const key of Object.keys(scheduleViews))delete scheduleViews[key];gradeTerm.value='all';gradeQuery.value='';academicCache.value=emptyAcademicCache()});
afterEach(dispose);
describe('页面卸载与重建的导航状态',()=>{
 it('首次进入即可切日视图，切换Tab后按学期恢复周次/星期/视图',async()=>{
  mountSchedule();(root.querySelector('.segmented button') as HTMLButtonElement).click();await nextTick();expect(root.querySelector('.week-days')).not.toBeNull();
  const week=root.querySelector('[aria-label="跳转教学周"]') as HTMLSelectElement;week.value='4';week.dispatchEvent(new Event('change'));(root.querySelectorAll('.week-days button')[2] as HTMLButtonElement).click();await nextTick();
  dispose();mountSchedule('another-term');expect((root.querySelectorAll('.segmented button')[1] as HTMLButtonElement).getAttribute('aria-pressed')).toBe('true');
  dispose();mountSchedule();expect((root.querySelector('[aria-label="跳转教学周"]') as HTMLSelectElement).value).toBe('4');expect(root.querySelector('.week-days button:nth-child(3)')?.getAttribute('aria-pressed')).toBe('true');
 });
 it('成绩条件通过真实输入事件保存，页面重建继续筛选',async()=>{
  academicCache.value.grades.data=[{name:'目标课程',term:'2026秋',kind:'必修',credit:1,gpa:4,scoreText:'优秀'},{name:'另一课程',term:'2025秋',kind:'必修',credit:2,gpa:3,scoreText:'80'}];
  function mountRecords(){root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(SchoolAcademicRecords,{section:'grades'})});app.mount(root)}
  mountRecords();const term=root.querySelector('select')!;term.value='2026秋';term.dispatchEvent(new Event('change'));const query=root.querySelector('input')!;query.value='目标';query.dispatchEvent(new Event('input'));await nextTick();dispose();mountRecords();
  expect(root.querySelector('select')?.value).toBe('2026秋');expect(root.querySelector('input')?.value).toBe('目标');expect(root.querySelectorAll('.grade-row')).toHaveLength(1);expect(root.textContent).toContain('目标课程');expect(root.textContent).not.toContain('另一课程');
 });
});
