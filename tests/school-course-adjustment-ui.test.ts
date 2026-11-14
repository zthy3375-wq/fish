// @vitest-environment jsdom
import {afterEach,describe,expect,it,vi} from 'vitest';
import {createApp,h,nextTick,reactive,type App} from 'vue';
import SchoolCourseAdjustment from '../src/components/SchoolCourseAdjustment.vue';
import type {Course} from '../src/domain/academic';
import {handanTimeTable} from '../src/domain/handan-time-table';

let app:App|undefined;
afterEach(()=>{app?.unmount();app=undefined;document.body.replaceChildren()});
function mount(){
 const source:Course={id:'synthetic',name:'合成课程',teacher:'教师',room:'原教室',day:1,start:'08:00',end:'09:25',startPeriod:1,endPeriod:2,period:'1-2',weeks:[1,3,5,7,9],color:'blue'};
 const props=reactive({source,current:source,table:handanTimeTable(),week:5,saving:false,saveError:''});
 const save=vi.fn(),cancel=vi.fn(),host=document.createElement('div');document.body.append(host);
 app=createApp({render:()=>h(SchoolCourseAdjustment,{...props,onSave:save,onCancel:cancel})});app.mount(host);
 function field(name:string){const label=[...host.querySelectorAll('label')].find(l=>l.firstChild?.textContent?.trim()===name);const field=label?.querySelector('input,select');if(!field)throw Error('Missing field '+name);return field as HTMLInputElement|HTMLSelectElement}
 async function set(name:string,value:string){const el=field(name);el.value=value;el.dispatchEvent(new Event(el.tagName==='SELECT'?'change':'input',{bubbles:true}));await nextTick()}
 async function click(text:string){const button=[...host.querySelectorAll('button')].find(b=>b.textContent?.trim()===text||b.getAttribute('aria-label')===text);if(!button)throw Error('Missing button '+text);button.click();await nextTick()}
 async function submit(){host.querySelector('form')!.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));await nextTick()}
 return {props,save,cancel,host,field,set,click,submit};
}
describe('调课编辑器 DOM 交互（不替代浏览器布局验证）',()=>{
 it('opens at the selected week and emits normalized period times and room',async()=>{
  const ui=mount();expect(ui.field('生效周').value).toBe('5');
  await ui.set('星期','4');await ui.set('开始节次','6');await ui.set('结束节次','7');await ui.set('上课教室',' 新教室 ');await ui.submit();
  expect(ui.save).toHaveBeenCalledWith([5],expect.objectContaining({day:4,start:'14:30',end:'15:55',room:'新教室',startPeriod:6,endPeriod:7}),false);
 });
 it('future and custom ranges retain only actual teaching weeks',async()=>{
  const ui=mount();await ui.set('调整范围','future');await ui.set('起始周','5');await ui.submit();expect(ui.save.mock.lastCall?.[0]).toEqual([5,7,9]);
  await ui.set('调整范围','custom');await ui.click('5');await ui.submit();expect(ui.save).toHaveBeenCalledTimes(1);expect(ui.host.querySelector('[role=alert]')?.textContent).toContain('至少');
  await ui.click('3');await ui.click('9');await ui.submit();expect(ui.save.mock.lastCall?.[0]).toEqual([3,9]);
 });
 it('rejects reversed custom time without emitting a save',async()=>{
  const ui=mount();await ui.set('时间方式','custom');await ui.set('开始时间','12:00');await ui.set('结束时间','11:00');await ui.submit();
  expect(ui.save).not.toHaveBeenCalled();expect(ui.host.querySelector('[role=alert]')?.textContent).toContain('晚于');
 });
 it('asks before discarding changed fields or an edited week range',async()=>{
  const ui=mount();await ui.set('调整范围','future');await ui.click('取消调课');
  expect(ui.cancel).not.toHaveBeenCalled();expect(ui.host.textContent).toContain('放弃尚未保存');
  await ui.click('继续编辑');expect(ui.host.textContent).not.toContain('放弃尚未保存');
  await ui.click('取消调课');await ui.click('放弃修改');expect(ui.cancel).toHaveBeenCalledTimes(1);
 });
 it('conflict confirmation is explicit and resets when the target changes',async()=>{
  const ui=mount();ui.props.saveError='时间与另一门课重叠，请核对后确认保留';await nextTick();
  const checkbox=ui.host.querySelector<HTMLInputElement>('input[type=checkbox]')!;checkbox.click();await nextTick();await ui.submit();expect(ui.save.mock.lastCall?.[2]).toBe(true);
  await ui.set('星期','4');await ui.submit();expect(ui.save.mock.lastCall?.[2]).toBe(false);
 });
 it('saving disables controls and prevents cancellation during the storage transaction',async()=>{
  const ui=mount();ui.props.saving=true;await nextTick();await ui.click('取消调课');
  expect(ui.cancel).not.toHaveBeenCalled();expect(ui.host.querySelector('fieldset')?.disabled).toBe(true);expect(ui.host.querySelector<HTMLButtonElement>('button.primary')?.disabled).toBe(true);
 });
});
