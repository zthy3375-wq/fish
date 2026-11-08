// @vitest-environment jsdom
import {afterEach,beforeEach,it,expect,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import QuzhiWallet from '../src/components/QuzhiWallet.vue';
import {quzhi,quzhiBusy,quzhiReady,refreshQuzhi,rechargeQuzhi,connectQuzhi,disconnectQuzhi} from '../src/composables/quzhi';

const native=vi.hoisted(()=>({resume:undefined as undefined|((value:{isActive:boolean})=>void),remove:vi.fn()}));
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async(_event:string,callback:typeof native.resume)=>{native.resume=callback;return {remove:native.remove}})}}));
vi.mock('../src/services/quzhi-client',async original=>({...await original<typeof import('../src/services/quzhi-client')>(),quzhiSupported:()=>true}));
vi.mock('../src/composables/quzhi',async()=>{
  const {ref}=await import('vue');
  return {quzhi:ref({connected:false,expired:false,phone:''}),quzhiBusy:ref(false),quzhiReady:ref(true),quzhiError:ref(''),initQuzhi:vi.fn(async()=>{}),refreshQuzhi:vi.fn(),connectQuzhi:vi.fn(),disconnectQuzhi:vi.fn(),rechargeQuzhi:vi.fn()};
});
let app:ReturnType<typeof createApp>|undefined,root:HTMLElement;
let visibility:'visible'|'hidden';
async function settle(){for(let i=0;i<5;i++)await Promise.resolve();await nextTick()}
function button(name:string){const element=[...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===name);expect(element).toBeTruthy();return element!}
function active(){native.resume!({isActive:true})}
function setVisibility(value:typeof visibility){visibility=value;document.dispatchEvent(new Event('visibilitychange'))}
async function openRecharge(){button('充值 · 支付宝').click();await nextTick();button('打开充值页').click();await settle()}
beforeEach(async()=>{
  vi.useFakeTimers();vi.setSystemTime(new Date('2026-11-08T04:00:00Z'));vi.clearAllMocks();
  visibility='visible';vi.spyOn(document,'visibilityState','get').mockImplementation(()=>visibility);
  quzhiBusy.value=false;quzhiReady.value=true;
  quzhi.value={connected:true,expired:false,phone:'138****0000',school:'人工测试学校',wallet:{total:'12.34',cash:null,gift:null},walletUpdatedAt:Date.now()-300_000,bills:[],billsMonth:'2026-11',billsUpdatedAt:Date.now()-300_000};
  vi.mocked(refreshQuzhi).mockReset().mockResolvedValue(true);
  vi.mocked(rechargeQuzhi).mockReset().mockResolvedValue(true);
  vi.mocked(disconnectQuzhi).mockReset().mockImplementation(async()=>{quzhi.value={connected:false,expired:false,phone:''};return true});
  root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(QuzhiWallet)});app.mount(root);await settle();vi.mocked(refreshQuzhi).mockClear();
});
afterEach(()=>{app?.unmount();app=undefined;root.remove();vi.restoreAllMocks();vi.useRealTimers()});

it('refreshes an old wallet on an ordinary app return without opening recharge or logging in',async()=>{
  native.resume!({isActive:false});await vi.advanceTimersByTimeAsync(60_000);active();await settle();
  expect(refreshQuzhi).toHaveBeenCalledExactlyOnceWith('2026-11');
  expect(rechargeQuzhi).not.toHaveBeenCalled();expect(connectQuzhi).not.toHaveBeenCalled();expect(disconnectQuzhi).not.toHaveBeenCalled();
  expect(root.textContent).not.toContain('已从充值页面返回');expect(root.textContent).not.toContain('充值成功');
});

it('does not refresh a recent attempt and permits one at the 60-second boundary',async()=>{
  active();await vi.advanceTimersByTimeAsync(59_999);active();await settle();expect(refreshQuzhi).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(1);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
});

it('also respects a newer successful balance timestamp',async()=>{
  await vi.advanceTimersByTimeAsync(60_000);quzhi.value.walletUpdatedAt=Date.now();active();await settle();expect(refreshQuzhi).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(60_000);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
});

it('includes manual refresh attempts in the foreground cooldown',async()=>{
  await vi.advanceTimersByTimeAsync(55_000);
  root.querySelector<HTMLButtonElement>('[aria-label="刷新趣智余额与账单"]')!.click();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(10_000);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(50_000);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(2);
});

it('refreshes the selected billing month after an ordinary return',async()=>{
  const month=root.querySelector<HTMLInputElement>('input[type="month"]')!;
  month.value='2026-10';month.dispatchEvent(new Event('input',{bubbles:true}));month.dispatchEvent(new Event('change',{bubbles:true}));await settle();
  expect(refreshQuzhi).toHaveBeenCalledExactlyOnceWith('2026-10');
  await vi.advanceTimersByTimeAsync(59_999);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);active();await settle();expect(refreshQuzhi).toHaveBeenNthCalledWith(2,'2026-10');expect(month.value).toBe('2026-10');
});

it('deduplicates repeated active and visibility events even before the bridge reports busy',async()=>{
  let finish!:(value:boolean)=>void;
  vi.mocked(refreshQuzhi).mockImplementationOnce(()=>new Promise(resolve=>{finish=resolve}));
  await vi.advanceTimersByTimeAsync(60_000);active();active();setVisibility('visible');await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(120_000);active();setVisibility('visible');await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);expect(vi.getTimerCount()).toBe(0);
  finish(false);await settle();active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(60_000);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(2);
});

it('does not queue an ordinary return while another wallet operation is busy',async()=>{
  await vi.advanceTimersByTimeAsync(60_000);quzhiBusy.value=true;active();active();await settle();expect(refreshQuzhi).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
  quzhiBusy.value=false;await vi.advanceTimersByTimeAsync(60_000);expect(refreshQuzhi).not.toHaveBeenCalled();
  active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
});

it('throttles failed refresh attempts without changing cached balances or success timestamps',async()=>{
  const snapshot=JSON.stringify(quzhi.value),updated=root.querySelector('.quzhi-updated')!.textContent;
  vi.mocked(refreshQuzhi).mockResolvedValue(false);
  await vi.advanceTimersByTimeAsync(60_000);active();await settle();
  for(let i=0;i<4;i++){active();setVisibility('visible');await settle()}
  await vi.advanceTimersByTimeAsync(59_999);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);expect(vi.getTimerCount()).toBe(0);
  expect(JSON.stringify(quzhi.value)).toBe(snapshot);expect(root.querySelector('.quzhi-updated')!.textContent).toBe(updated);
  await vi.advanceTimersByTimeAsync(1);active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(2);
});

it('waits for both app activity and document visibility before an ordinary refresh',async()=>{
  await vi.advanceTimersByTimeAsync(60_000);setVisibility('hidden');active();await settle();expect(refreshQuzhi).not.toHaveBeenCalled();
  native.resume!({isActive:false});setVisibility('visible');await settle();expect(refreshQuzhi).not.toHaveBeenCalled();
  active();await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(60_000);setVisibility('hidden');active();setVisibility('visible');await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(2);
});

it.each(['expired','disconnected','not ready'] as const)('does not refresh or connect when the wallet is %s',async state=>{
  if(state==='expired')quzhi.value.expired=true;
  else if(state==='disconnected')quzhi.value.connected=false;
  else quzhiReady.value=false;
  await vi.advanceTimersByTimeAsync(120_000);active();setVisibility('visible');await settle();
  expect(refreshQuzhi).not.toHaveBeenCalled();expect(connectQuzhi).not.toHaveBeenCalled();expect(rechargeQuzhi).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
});

it('refreshes after a quick recharge return even when the recharge bridge has not resolved yet',async()=>{
  let finish!:()=>void;
  vi.mocked(rechargeQuzhi).mockImplementation(()=>{quzhiBusy.value=true;return new Promise(resolve=>{finish=()=>{quzhiBusy.value=false;resolve(true)}})});
  await openRecharge();active();active();expect(refreshQuzhi).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(1);
  finish();await settle();await vi.advanceTimersByTimeAsync(250);
  expect(refreshQuzhi).toHaveBeenCalledTimes(1);expect(root.textContent).toContain('已从充值页面返回');expect(root.textContent).toContain('实际到账以平台余额和支付订单为准');
  expect(root.textContent).not.toContain('充值成功');active();setVisibility('visible');await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
});

it('cancels the deferred recharge refresh when opening recharge fails or is cancelled',async()=>{
  let finish!:()=>void;
  vi.mocked(rechargeQuzhi).mockImplementation(()=>{quzhiBusy.value=true;return new Promise(resolve=>{finish=()=>{quzhiBusy.value=false;resolve(false)}})});
  await openRecharge();active();finish();await settle();await vi.advanceTimersByTimeAsync(250);
  expect(refreshQuzhi).not.toHaveBeenCalled();expect(root.textContent).not.toContain('已从充值页面返回');expect(vi.getTimerCount()).toBe(0);
});

it('cancels pending recharge polling while hidden and refreshes once on visible return',async()=>{
  let finish!:()=>void;
  vi.mocked(rechargeQuzhi).mockImplementation(()=>{quzhiBusy.value=true;return new Promise(resolve=>{finish=()=>{quzhiBusy.value=false;resolve(true)}})});
  await openRecharge();active();expect(vi.getTimerCount()).toBe(1);
  setVisibility('hidden');native.resume!({isActive:false});finish();await settle();await vi.advanceTimersByTimeAsync(250);expect(refreshQuzhi).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
  active();await settle();expect(refreshQuzhi).not.toHaveBeenCalled();setVisibility('visible');await settle();expect(refreshQuzhi).toHaveBeenCalledTimes(1);
});

it('clears a pending recharge return when the account expires',async()=>{
  vi.mocked(rechargeQuzhi).mockImplementation(async()=>{quzhiBusy.value=true;return true});
  await openRecharge();active();quzhi.value.expired=true;quzhiBusy.value=false;await vi.advanceTimersByTimeAsync(250);
  expect(refreshQuzhi).not.toHaveBeenCalled();expect(root.textContent).not.toContain('已从充值页面返回');expect(vi.getTimerCount()).toBe(0);
});

it('does not refresh after logout, including a previously pending recharge return',async()=>{
  vi.mocked(rechargeQuzhi).mockImplementation(async()=>{quzhiBusy.value=true;return true});
  await openRecharge();active();quzhiBusy.value=false;await nextTick();
  button('退出趣智账户').click();await nextTick();button('确认退出').click();await settle();
  await vi.advanceTimersByTimeAsync(120_000);active();setVisibility('visible');await settle();
  expect(disconnectQuzhi).toHaveBeenCalledTimes(1);expect(refreshQuzhi).not.toHaveBeenCalled();expect(connectQuzhi).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
});

it('removes listeners and pending recharge refresh when the wallet closes',async()=>{
  vi.mocked(rechargeQuzhi).mockImplementation(async()=>{quzhiBusy.value=true;return true});
  await openRecharge();active();app!.unmount();app=undefined;quzhiBusy.value=false;
  await vi.advanceTimersByTimeAsync(120_000);active();setVisibility('visible');await settle();
  expect(native.remove).toHaveBeenCalledTimes(1);expect(refreshQuzhi).not.toHaveBeenCalled();expect(vi.getTimerCount()).toBe(0);
});

it('does not schedule follow-up work when an ordinary pending refresh completes after unmount',async()=>{
  let finish!:(value:boolean)=>void;
  vi.mocked(refreshQuzhi).mockImplementationOnce(()=>new Promise(resolve=>{finish=resolve}));
  await vi.advanceTimersByTimeAsync(60_000);active();app!.unmount();app=undefined;finish(false);await settle();
  await vi.advanceTimersByTimeAsync(120_000);active();setVisibility('visible');await settle();
  expect(native.remove).toHaveBeenCalledTimes(1);expect(refreshQuzhi).toHaveBeenCalledTimes(1);expect(vi.getTimerCount()).toBe(0);
});

it('hides component balances when their units cannot be verified',()=>{expect(root.querySelector('.quzhi-breakdown')).toBeNull();expect(root.textContent).toContain('12.34')});
