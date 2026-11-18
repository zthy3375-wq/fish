// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import PangguaiWater from '../src/components/PangguaiWater.vue';
import {pangguai,prepareWater,startWater,pollWater,endWater,confirmPhysicalWaterEnd,archiveUnverifiedWater,openWaterPaymentSetup} from '../src/composables/pangguai';
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async()=>({remove:vi.fn()}))}}));
vi.mock('../src/composables/pangguai',async()=>{const {ref}=await import('vue');return {pangguai:ref({}),pgBusy:ref(false),pgError:ref(''),prepareWater:vi.fn(),startWater:vi.fn(),pollWater:vi.fn(),endWater:vi.fn(),confirmPhysicalWaterEnd:vi.fn(),archiveUnverifiedWater:vi.fn(),openWaterPaymentSetup:vi.fn()}});
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

it('physical confirmation with absent device session does not claim device idle or paid',async()=>{
 pangguai.value.water={id:'old',deviceId:device.id,deviceName:device.name,outlet:'常温水',feature:'',paymentName:'支付宝免密',phase:'closed_unknown',orderNo:'old-order',remoteEnd:false,updatedAt:Date.now(),endBasis:'physical_confirmed',error:'WATER_BILL_UNKNOWN'};
 await settle();expect(button('接水').disabled).toBe(false);expect(root.textContent).toContain('平台未返回设备会话');expect(root.textContent).not.toContain('设备已空闲');expect(root.textContent).not.toContain('本次实付');
});

const oldWater = {id:'stuck',deviceId:'old-hot',deviceName:'旧饮水机',outlet:'热水',feature:'',paymentName:'支付宝免密',phase:'using',orderNo:'old-order',remoteEnd:true,updatedAt:1};
it.each(['WATER_OWNERSHIP','WATER_WAIT','NETWORK','WATER_STILL_ACTIVE'])('releases a stopped session with %s without another device lookup',async error=>{
 pangguai.value.water={...oldWater,error};await settle();
 button('已在机身结算，恢复扫码').click();await settle();
 expect(archiveUnverifiedWater).not.toHaveBeenCalled();
 button('取消').click();await settle();
 expect(archiveUnverifiedWater).not.toHaveBeenCalled();
 button('已在机身结算，恢复扫码').click();await settle();
 await vi.advanceTimersByTimeAsync(5000);
 vi.mocked(archiveUnverifiedWater).mockImplementationOnce(async()=>{pangguai.value.water={...oldWater,phase:'archived_unverified'};return pangguai.value});
 const confirm=button('机身已停止，恢复扫码');confirm.click();confirm.click();await settle();
 expect(archiveUnverifiedWater).toHaveBeenCalledExactlyOnceWith('stuck');
 expect(confirmPhysicalWaterEnd).not.toHaveBeenCalled();expect(pollWater).not.toHaveBeenCalled();expect(endWater).not.toHaveBeenCalled();expect(startWater).not.toHaveBeenCalled();
 expect(root.querySelector('.water-progress')).toBeNull();expect(button('接水').disabled).toBe(false);expect(root.textContent).not.toContain('待核实');
});
it('keeps the confirmation available when the local save fails',async()=>{
 pangguai.value.water={...oldWater,error:'WATER_WAIT'};await settle();
 button('已在机身结算，恢复扫码').click();await settle();
 vi.mocked(archiveUnverifiedWater).mockResolvedValueOnce(undefined);
 button('机身已停止，恢复扫码').click();await settle();
 expect(root.querySelector('.water-progress')).not.toBeNull();expect(button('机身已停止，恢复扫码').disabled).toBe(false);
 expect(root.textContent).toContain('未能保存');
});
it('can release a local record with an expired login, while starting remains disabled',async()=>{
 pangguai.value.expired=true;pangguai.value.water={...oldWater,error:'WATER_OWNERSHIP'};await settle();
 expect(button('查询状态').disabled).toBe(true);button('已在机身结算，恢复扫码').click();await settle();
 expect(button('机身已停止，恢复扫码').disabled).toBe(false);
});
it('keeps a settling transaction out of local recovery',async()=>{
 pangguai.value.water={...oldWater,phase:'settling',error:'NETWORK'};await settle();expect(button('已在机身结算，恢复扫码')).toBeUndefined();
});
