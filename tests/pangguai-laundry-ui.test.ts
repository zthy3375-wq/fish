// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import PangguaiLaundry from '../src/components/PangguaiLaundry.vue';
import {pangguai,quoteLaundry,startLaundry,pollLaundry,cancelLaundry} from '../src/composables/pangguai';
import {laundryRemaining} from '../src/services/pangguai-client';
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async()=>({remove:vi.fn()}))}}));
vi.mock('../src/composables/pangguai',async()=>{const {ref}=await import('vue');return {pangguai:ref({}),pgBusy:ref(false),quoteLaundry:vi.fn(),startLaundry:vi.fn(),pollLaundry:vi.fn(),cancelLaundry:vi.fn()}});
const device={id:'test-device',name:'测试洗衣机',category:'00',operator:'测试商户',payment:'before',issue:'',skus:[{id:'test-sku',name:'标准洗',price:'3.50',feature:'测试说明',available:true}]};
const q={id:'quote-test',expiresAt:Date.now()+60000,deviceName:'测试洗衣机',program:'标准洗',amount:'3.5',channels:[{id:'2',name:'余额支付',available:true,reason:''}]};
let app:ReturnType<typeof createApp>,root:HTMLElement;
async function settle(){for(let i=0;i<10;i++)await Promise.resolve();await nextTick()}
function button(text:string){return [...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===text)!}
async function preview(){const radio=root.querySelector('input[type=radio]') as HTMLInputElement;radio.click();await settle();button('查看费用').click();await settle()}
beforeEach(async()=>{vi.useFakeTimers();vi.clearAllMocks();pangguai.value={connected:true,expired:false,phone:'138****0000'};vi.mocked(quoteLaundry).mockResolvedValue({...q,expiresAt:Date.now()+60000});root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(PangguaiLaundry,{device})});app.mount(root);await settle()});
afterEach(()=>{app.unmount();root.remove();vi.useRealTimers()});
it('scan and program selection never pay',async()=>{await preview();expect(quoteLaundry).toHaveBeenCalledExactlyOnceWith('test-sku');expect(startLaundry).not.toHaveBeenCalled();expect(root.textContent).toContain('确认洗衣费用')});
it('cancel confirmation never submits',async()=>{await preview();button('取消').click();await settle();expect(startLaundry).not.toHaveBeenCalled();expect(root.querySelector('.wash-confirm')).toBeNull()});
it('confirmation consumes quote and does not pass a client chosen amount',async()=>{await preview();button('确认支付 ¥3.50 并洗衣').click();await settle();expect(startLaundry).toHaveBeenCalledExactlyOnceWith('quote-test','2');expect(root.querySelector('.wash-confirm')).toBeNull()});
it('expired quote disables payment',async()=>{await preview();await vi.advanceTimersByTimeAsync(61000);expect(button('确认支付 ¥3.50 并洗衣').disabled).toBe(true)});
it('unknown channel availability disables payment',async()=>{vi.mocked(quoteLaundry).mockResolvedValue({...q,channels:[{id:'2',name:'余额',available:false,reason:'余额不足'}]});await preview();expect(button('确认支付 ¥3.50 并洗衣').disabled).toBe(true);expect(root.textContent).toContain('余额不足')});
it('paid is separate from running and cannot start another order',async()=>{pangguai.value.laundry={id:'s',deviceId:'d',deviceName:'测试机',program:'标准洗',amount:'3.5',phase:'paid',updatedAt:Date.now(),paySent:true};await settle();expect(root.textContent).toContain('已付款，等待启动确认');expect(button('请先处理当前订单').disabled).toBe(true);expect(root.querySelector('.wash-progress h3')?.textContent).not.toBe('洗衣中')});
it('timer expiry never claims completion',()=>{expect(laundryRemaining(Date.now()-1000,Date.now())).toBe('预计时间已到，正在等待设备确认')});
it('does not resume mutations on mount',()=>{expect(startLaundry).not.toHaveBeenCalled();expect(cancelLaundry).not.toHaveBeenCalled();expect(pollLaundry).not.toHaveBeenCalled()});
it('keeps creating outcome uncertain and blocks new order',async()=>{pangguai.value.laundry={id:'s',deviceId:'d',deviceName:'测试机',program:'标准洗',amount:'3.5',phase:'creating',updatedAt:Date.now(),paySent:false};await settle();expect(root.textContent).toContain('下单结果待核对');expect(button('请先处理当前订单').disabled).toBe(true)});
