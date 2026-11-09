// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import CourseWidgetSetup from '../src/components/CourseWidgetSetup.vue';
const bridge=vi.hoisted(()=>({status:vi.fn(),pin:vi.fn(),home:vi.fn()}));
vi.mock('../src/services/course-widget',async original=>({
 ...await original<typeof import('../src/services/course-widget')>(),
 widgetSupported:()=>true,courseWidgetStatus:bridge.status,pinCourseWidget:bridge.pin,openWidgetHome:bridge.home,
}));
let app:ReturnType<typeof createApp>|undefined,root:HTMLElement;
async function settle(){for(let i=0;i<6;i++)await Promise.resolve();await nextTick();}
function mount(){app=createApp({render:()=>h(CourseWidgetSetup)});app.mount(root);}
function button(name:string){return [...root.querySelectorAll('button')].find(b=>b.textContent?.includes(name))!;}
beforeEach(()=>{vi.useFakeTimers();bridge.status.mockReset().mockResolvedValue({supported:true,ids:[]});bridge.pin.mockReset().mockResolvedValue({requested:true,baselineIds:[]});bridge.home.mockReset().mockResolvedValue(undefined);root=document.createElement('div');document.body.append(root);});
afterEach(()=>{app?.unmount();app=undefined;root.remove();vi.useRealTimers();});
it('opens instructions without claiming a system dialog or making an automatic pin request',async()=>{
 mount();await settle();expect(root.textContent).toContain('长按桌面空白处');expect(root.textContent).toContain('邯院通 · 近日课程');
 expect(bridge.pin).not.toHaveBeenCalled();expect(bridge.home).not.toHaveBeenCalled();
});
it('treats an accepted request with no new widget as pending, never as success',async()=>{
 mount();await settle();button('请求系统添加').click();button('请求系统添加').click();await settle();
 expect(bridge.pin).toHaveBeenCalledTimes(1);expect(root.querySelector('[role=status]')?.textContent).toContain('尚未确认添加成功');
 expect(root.textContent).not.toContain('已检测到新添加');expect(button('前往桌面').disabled).toBe(false);
});
it('does not count an existing widget or its removal as a successful new addition',async()=>{
 bridge.status.mockResolvedValue({supported:true,ids:[7]});bridge.pin.mockResolvedValue({requested:true,baselineIds:[7]});
 mount();await settle();button('请求系统添加').click();await settle();
 expect(root.textContent).not.toContain('已检测到新添加');
 bridge.status.mockResolvedValue({supported:true,ids:[]});button('检查添加结果').click();await settle();
 expect(root.textContent).not.toContain('已检测到新添加');
});
it('confirms success only after a new provider ID is observed',async()=>{
 bridge.status.mockResolvedValue({supported:true,ids:[7]});bridge.pin.mockResolvedValue({requested:true,baselineIds:[7]});
 mount();await settle();button('请求系统添加').click();await settle();
 bridge.status.mockResolvedValue({supported:true,ids:[7,8]});button('检查添加结果').click();await settle();
 expect(root.querySelector('[role=status]')?.textContent).toContain('已检测到新添加');expect(vi.getTimerCount()).toBe(0);
});
it('keeps a useful manual path when the launcher rejects in-app pinning',async()=>{
 bridge.status.mockResolvedValue({supported:false,ids:[]});mount();await settle();
 expect(button('请求系统添加').disabled).toBe(true);expect(root.textContent).toContain('手动添加');
 button('前往桌面').click();await settle();expect(bridge.home).toHaveBeenCalledTimes(1);expect(bridge.pin).not.toHaveBeenCalled();
});
it('contains errors and leaves the visible manual instructions available',async()=>{
 bridge.pin.mockRejectedValue(new Error('private native error'));mount();await settle();button('请求系统添加').click();await settle();
 expect(root.textContent).toContain('暂时无法确认添加结果');expect(root.textContent).not.toContain('private native error');expect(button('请求系统添加').disabled).toBe(false);
});
it('stops polling after the wait limit without claiming cancellation or success',async()=>{
 mount();await settle();button('请求系统添加').click();await settle();await vi.advanceTimersByTimeAsync(20000);await settle();
 expect(root.textContent).toContain('暂时无法确认添加结果');expect(button('请求系统添加').disabled).toBe(false);expect(vi.getTimerCount()).toBe(0);
 bridge.status.mockResolvedValue({supported:true,ids:[9]});button('检查添加结果').click();await settle();expect(root.textContent).toContain('已检测到新添加');
});
it('discards late replies after the setup is closed',async()=>{
 let finish!:(value:{requested:boolean;baselineIds:number[]})=>void;
 bridge.pin.mockReturnValue(new Promise(resolve=>{finish=resolve;}));mount();await settle();button('请求系统添加').click();await settle();
 app!.unmount();app=undefined;mount();await settle();finish({requested:true,baselineIds:[]});await settle();
 expect(root.textContent).not.toContain('尚未确认添加成功');expect(vi.getTimerCount()).toBe(0);
});
