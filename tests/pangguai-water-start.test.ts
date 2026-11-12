// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import PangguaiWater from '../src/components/PangguaiWater.vue';
import {pangguai,pgBusy,pgError} from '../src/composables/pangguai';
import {pangguaiNative,type PangguaiSnapshot} from '../src/services/pangguai-client';

// Exercise the real composable and its native rejection/snapshot path, not a stubbed startWater.
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async()=>({remove:vi.fn()}))}}));
vi.mock('../src/composables/analytics',()=>({recordFeature:vi.fn(async()=>{})}));
vi.mock('../src/services/pangguai-client',async importOriginal=>({
 ...(await importOriginal<typeof import('../src/services/pangguai-client')>()),
 pangguaiSupported:()=>true,
 pangguaiNative:{prepareWater:vi.fn(),startWater:vi.fn(),getSnapshot:vi.fn(),pollWater:vi.fn()}
}));
const device={id:'water-test',name:'测试饮水机',category:'04',operator:'测试商户',payment:'after',issue:'',skus:[{id:'outlet-test',name:'常温水',price:'1',feature:'实际用量计费',available:true}]};
const quote={id:'quote-test',expiresAt:0,deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'实际用量计费',price:'1',paymentName:'支付宝免密',remoteEnd:true,canStart:true,reason:''};
let app:ReturnType<typeof createApp>,root:HTMLElement,snapshot:PangguaiSnapshot;
async function settle(){for(let i=0;i<25;i++)await Promise.resolve();await nextTick()}
function button(name:string){return [...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===name)}
async function preview(){button('接水')!.click();await settle()}
beforeEach(async()=>{
 vi.useFakeTimers();vi.resetAllMocks();pgBusy.value=false;pgError.value='';
 snapshot={connected:true,expired:false,phone:'138****0000'};pangguai.value=snapshot;
 vi.mocked(pangguaiNative.getSnapshot).mockImplementation(async()=>snapshot);
 vi.mocked(pangguaiNative.prepareWater).mockResolvedValue({...quote,expiresAt:Date.now()+60000});
 root=document.createElement('div');document.body.append(root);
 app=createApp({render:()=>h(PangguaiWater,{device})});app.mount(root);await settle();
});
afterEach(()=>{app.unmount();root.remove();vi.useRealTimers()});
it('keeps a pre-start native rejection visible beside the water controls and requires a fresh quote',async()=>{
 vi.mocked(pangguaiNative.startWater).mockRejectedValue({code:'WATER_WAIT'});
 await preview();button('确认开始接水')!.click();await settle();
 expect(root.querySelector('[role="alert"]')?.textContent).toContain('设备尚未返回');
 expect(button('确认开始接水')).toBeUndefined();
 expect(pangguaiNative.startWater).toHaveBeenCalledExactlyOnceWith({quoteId:'quote-test'});
 await vi.advanceTimersByTimeAsync(10_000);
 expect(pangguaiNative.startWater).toHaveBeenCalledTimes(1);
 await preview();expect(pangguaiNative.prepareWater).toHaveBeenCalledTimes(2);
 expect(root.querySelector('[role="alert"]')).toBeNull();
});
it('shows progress while native start is pending and serializes repeated confirmation',async()=>{
 let resolve!:(value:PangguaiSnapshot)=>void;
 vi.mocked(pangguaiNative.startWater).mockImplementation(()=>new Promise(r=>{resolve=r}));
 await preview();button('确认开始接水')!.click();await settle();
 expect(root.querySelector('[role="status"]')?.textContent).toContain('正在请求设备启动');
 expect(button('接水')).toBeUndefined();expect(button('正在启动…')?.disabled).toBe(true);
 expect(pangguaiNative.startWater).toHaveBeenCalledTimes(1);
 snapshot={...snapshot,water:{id:'session-test',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'using',orderNo:'synthetic-order',remoteEnd:false,updatedAt:Date.now()}};
 resolve(snapshot);await settle();expect(root.textContent).toContain('接水中');
});
it('retains an uncertain durable start and never exposes a second unlock after a lost response',async()=>{
 vi.mocked(pangguaiNative.startWater).mockImplementation(async()=>{
  snapshot={...snapshot,water:{id:'uncertain',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'starting',remoteEnd:false,updatedAt:Date.now(),error:'NETWORK'}};
  throw {code:'NETWORK'};
 });
 await preview();button('确认开始接水')!.click();await settle();
 expect(root.querySelector('[role="alert"]')?.textContent).toContain('网络');
 expect(root.textContent).toContain('正在核对本次用水');
 expect(button('接水')).toBeUndefined();expect(button('确认开始接水')).toBeUndefined();
 await vi.advanceTimersByTimeAsync(10_000);expect(pangguaiNative.startWater).toHaveBeenCalledTimes(1);
});
it('shows a preparation failure in the water panel without starting a device',async()=>{
 vi.mocked(pangguaiNative.prepareWater).mockRejectedValue({code:'NETWORK'});
 await preview();expect(root.querySelector('[role="alert"]')?.textContent).toContain('网络');
 expect(pangguaiNative.startWater).not.toHaveBeenCalled();expect(button('接水')?.disabled).toBe(false);
});
