// @vitest-environment jsdom
import {afterEach,beforeEach,it,expect,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import QuzhiWallet from '../src/components/QuzhiWallet.vue';
import {quzhiBusy,refreshQuzhi,rechargeQuzhi} from '../src/composables/quzhi';

const native=vi.hoisted(()=>({resume:undefined as undefined|((value:{isActive:boolean})=>void),remove:vi.fn()}));
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async(_event:string,callback:typeof native.resume)=>{native.resume=callback;return {remove:native.remove}})}}));
vi.mock('../src/services/quzhi-client',async original=>({...await original<typeof import('../src/services/quzhi-client')>(),quzhiSupported:()=>true}));
vi.mock('../src/composables/quzhi',async()=>{
  const {ref}=await import('vue');
  return {quzhi:ref({connected:true,expired:false,phone:'138****0000',school:'人工测试学校',wallet:{total:'12.34',cash:'10',gift:'2.34'}}),quzhiBusy:ref(false),quzhiReady:ref(true),quzhiError:ref(''),initQuzhi:vi.fn(async()=>{}),refreshQuzhi:vi.fn(async()=>true),connectQuzhi:vi.fn(),disconnectQuzhi:vi.fn(),rechargeQuzhi:vi.fn()};
});
let app:ReturnType<typeof createApp>|undefined,root:HTMLElement;
async function settle(){await Promise.resolve();await Promise.resolve();await nextTick()}
function button(name:string){const element=[...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===name);expect(element).toBeTruthy();return element!}
beforeEach(async()=>{vi.useFakeTimers();vi.clearAllMocks();quzhiBusy.value=false;root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(QuzhiWallet)});app.mount(root);await settle();vi.mocked(refreshQuzhi).mockClear()});
afterEach(()=>{app?.unmount();app=undefined;root.remove();vi.useRealTimers()});
it('refreshes after a quick return even when the recharge bridge has not resolved yet',async()=>{
  let finish!:()=>void;
  vi.mocked(rechargeQuzhi).mockImplementation(()=>{quzhiBusy.value=true;return new Promise(resolve=>{finish=()=>{quzhiBusy.value=false;resolve(true)}})});
  button('充值 · 支付宝').click();await nextTick();button('打开充值页').click();await settle();
  native.resume!({isActive:true});expect(refreshQuzhi).not.toHaveBeenCalled();
  finish();await settle();await vi.advanceTimersByTimeAsync(250);
  expect(refreshQuzhi).toHaveBeenCalledTimes(1);expect(root.textContent).toContain('已从充值页面返回');
  expect(root.textContent).not.toContain('充值成功');
});
it('removes the listener and pending refresh when the wallet closes',async()=>{
  vi.mocked(rechargeQuzhi).mockImplementation(async()=>{quzhiBusy.value=true;return true});
  button('充值 · 支付宝').click();await nextTick();button('打开充值页').click();await settle();
  native.resume!({isActive:true});app!.unmount();app=undefined;quzhiBusy.value=false;
  await vi.advanceTimersByTimeAsync(250);
  expect(native.remove).toHaveBeenCalledTimes(1);expect(refreshQuzhi).not.toHaveBeenCalled();
});
