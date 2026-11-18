// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
import PangguaiWallet from '../src/components/PangguaiWallet.vue';
import {pangguai,pgBusy,refreshPangguai,connectPangguai,disconnectPangguai,scanPangguai,rechargePangguai} from '../src/composables/pangguai';
const lifecycle=vi.hoisted(()=>({callback:undefined as undefined|((v:{isActive:boolean})=>void),remove:vi.fn()}));
vi.mock('@capacitor/app',()=>({App:{addListener:vi.fn(async(_:string,cb:typeof lifecycle.callback)=>{lifecycle.callback=cb;return {remove:lifecycle.remove}})}}));
vi.mock('../src/services/pangguai-client',async original=>({...await original<typeof import('../src/services/pangguai-client')>(),pangguaiSupported:()=>true}));
vi.mock('../src/services/pangguai-official',()=>({openPangguaiOfficial:vi.fn()}));
vi.mock('../src/composables/pangguai',async()=>{const {ref}=await import('vue');return {pangguai:ref({}),pgBusy:ref(false),pgReady:ref(true),pgError:ref(''),initPangguai:vi.fn(),refreshPangguai:vi.fn(),connectPangguai:vi.fn(),disconnectPangguai:vi.fn(),scanPangguai:vi.fn(),rechargePangguai:vi.fn()}});
let app:ReturnType<typeof createApp>,root:HTMLElement;
async function settle(){for(let i=0;i<8;i++)await Promise.resolve();await nextTick()}
function button(name:string){const b=[...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===name);expect(b).toBeTruthy();return b!}
beforeEach(async()=>{vi.useFakeTimers();vi.clearAllMocks();pgBusy.value=false;pangguai.value={connected:true,expired:false,phone:'138****0000',balance:'18.5',walletUpdatedAt:100,tickets:[{id:'synthetic-shop',name:'邯郸学院直饮水机',balance:'257',principal:'257',gift:'0'}],ticketsUpdatedAt:100,orders:[]};root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(PangguaiWallet)});app.mount(root);await settle();vi.mocked(refreshPangguai).mockClear()});
afterEach(()=>{app.unmount();root.remove();vi.useRealTimers()});
it('shows verified drinking-water yuan balance once and hides the general wallet',()=>{expect(root.querySelector('.pg-balance')!.textContent).toContain('2.57');expect(root.textContent).not.toContain('18.50');expect(root.textContent).not.toContain('普通账户余额');expect(root.textContent).not.toContain('257.00');expect(root.querySelector('.pg-water-recharge')!.textContent).not.toContain('2.57')});
it('never uses the first unrelated merchant as drinking water',async()=>{pangguai.value.tickets=[{id:'other',name:'洗衣商户',balance:'900',principal:'900',gift:'0'},...pangguai.value.tickets!];await nextTick();expect(root.querySelector('.pg-balance')!.textContent).toContain('2.57');button('充值').click();await nextTick();button('前往付款').click();await settle();expect(rechargePangguai).toHaveBeenCalledWith('synthetic-shop')});
it('keeps a real zero distinct from an unavailable balance',async()=>{pangguai.value.tickets![0]!.balance='0';await nextTick();expect(root.querySelector('.pg-balance')!.textContent).toContain('0.00');pangguai.value.tickets=[];await nextTick();expect(root.querySelector('.pg-balance')!.textContent).toContain('暂未获取');expect(root.querySelector('.pg-balance')!.textContent).not.toContain('0.00')});
it('does not select an ambiguous drinking-water merchant',async()=>{pangguai.value.tickets!.push({...pangguai.value.tickets![0]!,id:'second'});await nextTick();expect(root.querySelector('.pg-balance')!.textContent).toContain('暂未获取')});
it('keeps cached water balance with a stale notice on failed refresh',async()=>{pangguai.value.issues={tickets:'NETWORK'};await nextTick();expect(root.querySelector('.pg-balance')!.textContent).toContain('2.57');expect(root.textContent).toContain('保留上次结果')});
it('does not launch recharge on cancel',async()=>{button('充值').click();await nextTick();button('取消').click();await settle();expect(rechargePangguai).not.toHaveBeenCalled()});
it('passes only the selected merchant after confirmation',async()=>{vi.mocked(rechargePangguai).mockResolvedValue({opened:true});button('充值').click();await nextTick();button('前往付款').click();await settle();expect(rechargePangguai).toHaveBeenCalledExactlyOnceWith('synthetic-shop');expect(root.textContent).not.toContain('充值成功')});
it('disables recharge and scan when session expires',async()=>{pangguai.value.expired=true;await nextTick();expect(button('充值').disabled).toBe(true);expect(button('扫码识别设备').disabled).toBe(true);button('重新连接').click();expect(connectPangguai).toHaveBeenCalledTimes(1)});
it('clears account display after logout',async()=>{vi.mocked(disconnectPangguai).mockImplementation(async()=>{pangguai.value={connected:false,expired:false,phone:''}});button('退出胖乖账户').click();await nextTick();button('确认退出').click();await settle();expect(root.querySelector('.pg-balance')).toBeNull();expect(root.textContent).not.toContain('邯郸学院直饮水机')});
it('shows unknown amounts as unknown rather than zero',async()=>{pangguai.value.tickets![0]!.balance=null;await nextTick();expect(root.querySelector('.pg-balance')!.textContent).toContain('暂未获取')});
it('does not perform scan automatically',()=>{expect(scanPangguai).not.toHaveBeenCalled()});
it('waits for pending bridge work before refreshing a recharge return',async()=>{let finish!:(v:{opened:boolean})=>void;vi.mocked(rechargePangguai).mockImplementation(()=>{pgBusy.value=true;return new Promise(resolve=>{finish=resolve})});button('充值').click();await nextTick();button('前往付款').click();await settle();lifecycle.callback!({isActive:true});expect(refreshPangguai).not.toHaveBeenCalled();pgBusy.value=false;finish({opened:true});await settle();await vi.advanceTimersByTimeAsync(250);expect(refreshPangguai).toHaveBeenCalledTimes(1)});

it('moves the three legacy archived rows off the scan screen across reopen, with original order numbers in recent activity',async()=>{
 const old={id:'old',deviceId:'water',deviceName:'旧饮水机',outlet:'饮水',feature:'',paymentName:'',phase:'archived_unverified',remoteEnd:false,updatedAt:1};
 pangguai.value.waterHistory=[1,2,3].map(i=>({...old,id:String(i),orderNo:'legacy-order-'+i}));pangguai.value.water=pangguai.value.waterHistory[2];await settle();
 for(let i=0;i<2;i++){
   expect(root.textContent).not.toContain('待核实');expect(root.textContent).not.toContain('legacy-order-');expect(button('扫码识别设备').disabled).toBe(false);
   button('最近消费').click();await settle();
   const details=root.querySelector<HTMLDetailsElement>('details.pg-archived-water');
   expect(details).not.toBeNull();expect(details!.open).toBe(false);details!.querySelector('summary')!.click();await settle();
   expect(details!.querySelectorAll('li')).toHaveLength(3);expect(details!.textContent).toContain('legacy-order-3');
   app.unmount();app=createApp({render:()=>h(PangguaiWallet)});app.mount(root);await settle();
 }
});
