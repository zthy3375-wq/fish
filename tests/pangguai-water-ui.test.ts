// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import PangguaiWater from '../src/components/PangguaiWater.vue';
import {pangguai,prepareWater,startWater,pollWater,endWater,confirmPhysicalWaterEnd,openWaterPaymentSetup} from '../src/composables/pangguai';
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async()=>({remove:vi.fn()}))}}));
vi.mock('../src/composables/pangguai',async()=>{const {ref}=await import('vue');return {pangguai:ref({}),pgBusy:ref(false),prepareWater:vi.fn(),startWater:vi.fn(),pollWater:vi.fn(),endWater:vi.fn(),confirmPhysicalWaterEnd:vi.fn(),openWaterPaymentSetup:vi.fn()}});
const device={id:'water-test',name:'测试饮水机',category:'04',operator:'测试商户',payment:'after',issue:'',skus:[{id:'outlet-test',name:'常温水',price:'1',feature:'实际用量计费',available:true}]};
const q={id:'quote',expiresAt:0,deviceId:'water-test',deviceName:'测试饮水机',outlet:'常温水',feature:'实际用量计费',price:'1',paymentName:'支付宝免密',remoteEnd:true,canStart:true,reason:''};
let app:ReturnType<typeof createApp>,root:HTMLElement;
async function settle(){for(let i=0;i<10;i++)await Promise.resolve();await nextTick()}
function button(name:string){return [...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===name)!}
async function preview(){button('接水').click();await settle()}
beforeEach(async()=>{vi.useFakeTimers();vi.clearAllMocks();pangguai.value={connected:true,expired:false,phone:'138****0000'};vi.mocked(prepareWater).mockResolvedValue({...q,expiresAt:Date.now()+60000});root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(PangguaiWater,{device})});app.mount(root);await settle()});
afterEach(()=>{app.unmount();root.remove();vi.useRealTimers()});
it('only prepares on first action and never starts on scan',async()=>{expect(startWater).not.toHaveBeenCalled();await preview();expect(prepareWater).toHaveBeenCalledExactlyOnceWith('outlet-test');expect(startWater).not.toHaveBeenCalled();expect(root.textContent).toContain('不是本次总价')});
it('cancel leaves device untouched',async()=>{await preview();button('取消').click();await settle();expect(startWater).not.toHaveBeenCalled()});
it('explicit confirmation passes native quote only',async()=>{await preview();button('确认开始接水').click();await settle();expect(startWater).toHaveBeenCalledExactlyOnceWith('quote')});
it('missing payment setup blocks unlock',async()=>{vi.mocked(prepareWater).mockResolvedValue({...q,expiresAt:Date.now()+60000,canStart:false,reason:'需要开通'});await preview();expect(button('确认开始接水').disabled).toBe(true);button('到支付宝胖乖处理').click();await settle();expect(openWaterPaymentSetup).toHaveBeenCalledTimes(1);expect(startWater).not.toHaveBeenCalled()});
it('physical-only device gives physical settlement instruction',async()=>{pangguai.value.water={id:'s',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'using',orderNo:'order-test',remoteEnd:false,updatedAt:Date.now()};await settle();expect(button('结束接水并结算')).toBeUndefined();expect(root.textContent).toContain('接完后请按机身「结算」');expect(endWater).not.toHaveBeenCalled()});
it('ending cannot claim a paid amount',async()=>{pangguai.value.water={id:'s',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'ending',orderNo:'order-test',remoteEnd:true,endSent:true,updatedAt:Date.now()};await settle();expect(root.textContent).toContain('等待设备结束');expect(root.textContent).not.toContain('本次实付')});
it('zero reported device usage is not presented as zero cash paid',async()=>{pangguai.value.water={id:'s',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'ended_zero',remoteEnd:true,updatedAt:Date.now()};await settle();expect(root.textContent).not.toContain('¥0.00');expect(root.textContent).toContain('费用仍以平台消费记录为准')});
it('unknown startup does not automatically clear or end',async()=>{pangguai.value.water={id:'s',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'starting',remoteEnd:true,updatedAt:Date.now()};await settle();await vi.advanceTimersByTimeAsync(5000);expect(confirmPhysicalWaterEnd).not.toHaveBeenCalled();expect(endWater).not.toHaveBeenCalled();expect(startWater).not.toHaveBeenCalled()});

it('legacy ownership error hides remote end and runaway timer while checking',async()=>{
 pangguai.value.water={id:'old',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'using',orderNo:'old-order',remoteEnd:true,startedAt:Date.now()-21_000_000,updatedAt:Date.now(),error:'WATER_OWNERSHIP'};
 await settle();expect(button('结束接水并结算')).toBeUndefined();expect(root.querySelector('.elapsed')).toBeNull();expect(root.textContent).toContain('接水状态待核对');expect(button('已在机身结算，恢复扫码')).toBeDefined();
});
it('recovered replaced record no longer blocks selecting and preparing next water session',async()=>{
 pangguai.value.water={id:'old',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'closed_unknown',orderNo:'old-order',remoteEnd:false,startedAt:Date.now()-21_000_000,endedAt:Date.now(),updatedAt:Date.now(),endBasis:'order_replaced',error:'WATER_BILL_UNKNOWN'};
 await settle();expect(button('接水').disabled).toBe(false);expect(root.querySelector('.water-progress')).toBeNull();await preview();expect(prepareWater).toHaveBeenCalledExactlyOnceWith('outlet-test');expect(startWater).not.toHaveBeenCalled();
});

it('ownership error pauses automatic queries and recovery needs explicit physical confirmation',async()=>{
 pangguai.value.water={id:'old',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'using',orderNo:'old-order',remoteEnd:true,updatedAt:Date.now(),error:'WATER_OWNERSHIP'};
 await settle();await vi.advanceTimersByTimeAsync(30_000);expect(pollWater).not.toHaveBeenCalled();
 button('已在机身结算，恢复扫码').click();await settle();expect(confirmPhysicalWaterEnd).not.toHaveBeenCalled();expect(root.textContent).toContain('确认本次接水已经停止');
 button('取消').click();await settle();expect(confirmPhysicalWaterEnd).not.toHaveBeenCalled();
 button('查询状态').click();await settle();expect(pollWater).toHaveBeenCalledTimes(1);
 button('已在机身结算，恢复扫码').click();await settle();button('确认已停止，核对设备').click();await settle();
 expect(confirmPhysicalWaterEnd).toHaveBeenCalledExactlyOnceWith('old');expect(endWater).not.toHaveBeenCalled();expect(startWater).not.toHaveBeenCalled();
});
it('startup with returned order but no timer offers physical recovery',async()=>{
 pangguai.value.water={id:'pending',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'starting',orderNo:'old-order',remoteEnd:false,updatedAt:Date.now(),error:'WATER_WAIT'};
 await settle();expect(button('已在机身结算，恢复扫码')).toBeDefined();expect(button('接水')).toBeUndefined();
 button('已在机身结算，恢复扫码').click();await settle();await vi.advanceTimersByTimeAsync(5000);expect(pollWater).not.toHaveBeenCalled();
});
it('physical confirmation with absent device session does not claim device idle or paid',async()=>{
 pangguai.value.water={id:'old',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'closed_unknown',orderNo:'old-order',remoteEnd:false,updatedAt:Date.now(),endBasis:'physical_confirmed',error:'WATER_BILL_UNKNOWN'};
 await settle();expect(button('接水').disabled).toBe(false);expect(root.textContent).toContain('平台未返回设备会话');expect(root.textContent).not.toContain('设备已空闲');expect(root.textContent).not.toContain('本次实付');
});
