// @vitest-environment jsdom
import {afterEach,expect,it,vi} from 'vitest';
import {createApp,nextTick} from 'vue';
import Cabinet from '../src/components/honors/HonorHall.vue';
import type {TreeholeResult} from '../src/services/treehole';
import type {HonorHall} from '../src/domain/communityHonors';

const own:HonorHall={id:'mine',nickname:'同学甲',badges:{},honors:[],awards:{arrival:'2026-11-18T09:00:00Z'},showcase:[],total:1,progress:{registered:1}};
let app:ReturnType<typeof createApp>|undefined;
function render(request:()=>Promise<TreeholeResult>,viewer='mine',member=viewer,enabled=true){
 const root=document.createElement('div');document.body.append(root);app=createApp(Cabinet,{viewer,member,enabled,request});app.mount(root);return root;
}
afterEach(()=>{app?.unmount();app=undefined;document.body.replaceChildren();sessionStorage.clear();});
it('loads once and retries an empty failed response, without assuming awards',async()=>{
 let resolve!:(value:TreeholeResult)=>void;
 const request=vi.fn<()=>Promise<TreeholeResult>>().mockImplementationOnce(()=>new Promise(r=>{resolve=r;})).mockResolvedValue({hall:own});
 const root=render(request);await nextTick();expect(root.textContent).toContain('正在读取');expect(request).toHaveBeenCalledTimes(1);
 resolve({});await vi.waitFor(()=>expect(root.querySelector('[role=alert]')).toBeTruthy());
 expect(root.querySelector('.hon-action')).toBeNull();root.querySelector<HTMLButtonElement>('[role=alert] button')!.click();
 await vi.waitFor(()=>expect(root.textContent).toContain('1/8'));expect(request).toHaveBeenCalledTimes(2);
});
it('uses only the signed-in viewer’s cache for offline reading and disables changes',async()=>{
 sessionStorage.setItem('hyt-hall-v1:mine',JSON.stringify(own));const root=render(async()=>{throw Error('network_unavailable');});
 await vi.waitFor(()=>expect(root.textContent).toContain('本次登录最近保存'));expect(root.querySelector<HTMLButtonElement>('.hon-action')?.disabled).toBe(true);
});
it('never falls back to another account after an account switch or failed public request',async()=>{
 sessionStorage.setItem('hyt-hall-v1:mine',JSON.stringify(own));const root=render(async()=>{throw Error('network_unavailable');},'second','mine');
 await vi.waitFor(()=>expect(root.querySelector('[role=alert]')).toBeTruthy());expect(root.textContent).not.toContain('同学甲');expect(root.textContent).not.toContain('1/8');
});
it('an expired session cannot reopen a cached private cabinet',async()=>{
 sessionStorage.setItem('hyt-hall-v1:mine',JSON.stringify(own));const root=render(async()=>{throw Error('session_expired');});
 await vi.waitFor(()=>expect(root.querySelector('[role=alert]')).toBeTruthy());expect(root.querySelector('.hon-action')).toBeNull();expect(root.textContent).not.toContain('1/8');
});
it('shows the catalog without invented progress on a legacy server',async()=>{
 const request=vi.fn();const root=render(request,'mine','mine',false);await nextTick();expect(request).not.toHaveBeenCalled();
 expect(root.querySelectorAll('.hon-grid button')).toHaveLength(8);expect(root.querySelectorAll('.hon-grid .earned')).toHaveLength(0);
});
