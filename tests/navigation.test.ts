// @vitest-environment jsdom
import {beforeEach,afterEach,describe,it,expect,vi} from 'vitest';
import {createApp,defineComponent,nextTick} from 'vue';
import {NavigationStack,parseRoute} from '../src/domain/navigation';
import {useNavigation} from '../src/composables/navigation';

describe('导航返回路径',()=>{
 it('四个 Tab 连续切换不会留下返回堆栈',()=>{
  const n=new NavigationStack(parseRoute('#/home'));
  for(let i=0;i<20;i++){n.move('schedule');n.move('profile');n.move('academic');n.move('home')}
  expect(n.parents).toEqual([]);expect(n.canBack()).toBe(false);
 });
 it.each(['home','academic','profile'] as const)('二级页返回原入口 %s',page=>{
  const n=new NavigationStack(parseRoute(`#/${page}`));n.move('academic','grades');n.back();expect(n.route).toEqual(parseRoute(`#/${page}`));
 });
 it('弹窗先关闭，再返回二级页的原入口；重复跳转不重复入栈',()=>{
  const n=new NavigationStack(parseRoute('#/home'));n.move('academic','grades');n.move('academic','grades');n.overlay='notifications';n.back();expect(n.route.section).toBe('grades');expect(n.overlay).toBe('');expect(n.parents).toHaveLength(1);n.back();expect(n.route.page).toBe('home');
 });
 it('点击一级 Tab 丢弃上个二级页返回路径',()=>{
  const n=new NavigationStack(parseRoute('#/home'));n.move('academic','grades');n.move('profile');n.back();expect(n.route.page).toBe('home');
 });
 it('深链接返回教务根页，旧课表地址归一到课表 Tab',()=>{
  const n=new NavigationStack(parseRoute('#/academic/exams'));n.back();expect(n.route).toEqual({page:'academic',section:'overview'});expect(parseRoute('#/academic/schedule')).toEqual({page:'schedule',section:'schedule'});
 });
});
describe('浏览器与 Android 共用导航适配',()=>{
 let app:ReturnType<typeof createApp>,nav:ReturnType<typeof useNavigation>;
 beforeEach(()=>{history.replaceState(null,'','#/home');app=createApp(defineComponent({setup(){nav=useNavigation();return()=>null}}));app.mount(document.createElement('div'))});
 afterEach(()=>{app.unmount();vi.restoreAllMocks()});
 it('Tab 和弹窗操作同步完成，不依赖异步 history.back，地址不增加历史',()=>{
  const length=history.length;navigateMany();nav.open('notifications');nav.close();expect(nav.overlay.value).toBe('');expect(history.length).toBe(length);expect(location.hash).toBe('#/schedule');
 });
 function navigateMany(){nav.move('profile');nav.move('academic');nav.move('schedule')}
 it('浏览器返回连续处理弹窗和原入口，边界标记始终保留',async()=>{
  nav.move('academic','grades');nav.open('notifications');
  history.back();await new Promise(r=>setTimeout(r,25));await nextTick();expect(nav.overlay.value).toBe('');expect(nav.section.value).toBe('grades');
  history.back();await new Promise(r=>setTimeout(r,25));expect(nav.page.value).toBe('home');
 });
 it('未保存编辑阻止系统返回，确认取消后正常关闭',()=>{
  nav.move('schedule');nav.open('course-editor');const guard=vi.fn(()=>false);nav.setOverlayCloseGuard(guard);nav.back();expect(guard).toHaveBeenCalledOnce();expect(nav.overlay.value).toBe('course-editor');nav.close();nav.back();expect(nav.page.value).toBe('home');
 });
});
