// @vitest-environment jsdom
import {afterEach,beforeEach,it,expect} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import AcademicDetail from '../src/components/AcademicDetail.vue';
import {defaultState} from '../src/domain/schedule';
import {scheduleViews} from '../src/composables/view-state';
import {academicCache} from '../src/composables/handan-academic';
import {emptyAcademicCache} from '../src/services/academic-sync-engine';
const state=defaultState();let app:ReturnType<typeof createApp>|undefined,root:HTMLElement;
function mount(id=state.semesters[0].id){root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(AcademicDetail,{semester:{...state.semesters[0],id},table:state.timeTables[0],section:'schedule',mode:'personal',data:{courses:[],grades:[],exams:[],source:'personal'},now:new Date(2026,10,6)})});app.mount(root)}
function dispose(){app?.unmount();app=undefined;root?.remove()}
beforeEach(()=>{for(const key of Object.keys(scheduleViews))delete scheduleViews[key];academicCache.value=emptyAcademicCache()});afterEach(dispose);
it('switching tabs and semester views preserves each timetable week, weekday and day/week mode',async()=>{mount();(root.querySelector('.segmented button') as HTMLButtonElement).click();await nextTick();const week=root.querySelector('[aria-label="跳转教学周"]') as HTMLSelectElement;week.value='4';week.dispatchEvent(new Event('change'));(root.querySelectorAll('.week-days button')[2] as HTMLButtonElement).click();await nextTick();dispose();mount('another-term');expect(root.querySelectorAll('.segmented button')[1].getAttribute('aria-pressed')).toBe('true');dispose();mount();expect((root.querySelector('[aria-label="跳转教学周"]') as HTMLSelectElement).value).toBe('4');expect(root.querySelector('.week-days button:nth-child(3)')?.getAttribute('aria-pressed')).toBe('true')});
