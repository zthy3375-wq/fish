// @vitest-environment jsdom
import {createApp,nextTick,type App} from 'vue';
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
const driver=vi.hoisted(()=>({scan:vi.fn(),act:vi.fn(),clear:vi.fn(),shortcut:vi.fn(),supported:true}));
vi.mock('../src/services/bike-scan',async importOriginal=>({...await importOriginal<any>(),scanBike:driver.scan,actOnBike:driver.act,clearBike:driver.clear,bikeShortcut:driver.shortcut,bikeSupported:()=>driver.supported}));
import BikeScan from '../src/components/BikeScan.vue';
import {loadRecentBike,recentBikeLifetime} from '../src/services/bike-scan';
const bike={provider:'hello',number:'9150978196',ticket:'11111111-1111-4111-8111-111111111111'};
let app:App|undefined,root:HTMLElement;
async function settle(){for(let i=0;i<6;i++){await Promise.resolve();await nextTick()}}
function mount(){root=document.createElement('div');document.body.append(root);app=createApp(BikeScan);app.mount(root)}
function button(label:string){const b=[...root.querySelectorAll('button')].find(b=>b.textContent?.includes(label));if(!b)throw Error(label);return b}
async function scan(){button('哈啰扫码用车').click();await settle()}
beforeEach(()=>{localStorage.clear();driver.supported=true;driver.scan.mockReset().mockResolvedValue(bike);driver.act.mockReset().mockResolvedValue('alipay_requested');driver.clear.mockReset().mockResolvedValue(undefined);driver.shortcut.mockReset().mockResolvedValue('scanner_requested')});
afterEach(()=>{app?.unmount();app=undefined;root?.remove();vi.useRealTimers()});
it('opening is passive and Hello requires explicit confirmation after recognizing a vehicle',async()=>{
 mount();await settle();expect(driver.scan).not.toHaveBeenCalled();expect(driver.shortcut).not.toHaveBeenCalled();await scan();expect(driver.scan).toHaveBeenCalledTimes(1);expect(driver.act).not.toHaveBeenCalled();
 button('前往用车').click();await settle();expect(driver.act).toHaveBeenCalledExactlyOnceWith(bike,'use');expect(loadRecentBike()).toMatchObject({provider:'hello',target:'alipay',number:bike.number});expect(root.textContent).not.toContain('开锁成功');
});
it('Meituan opens the official scanner once without starting local camera and remembers choice',async()=>{
 mount();button('美团官方扫码').click();button('美团官方扫码').click();await settle();expect(driver.scan).not.toHaveBeenCalled();expect(driver.shortcut).toHaveBeenCalledExactlyOnceWith('meituan','scanner','app');expect(loadRecentBike()).toMatchObject({provider:'meituan',target:'app'});
 app!.unmount();root.remove();mount();await settle();expect(button('美团官方扫码').getAttribute('aria-pressed')).toBe('true');expect(driver.shortcut).toHaveBeenCalledTimes(1);
});
it('return after remount never sends QR or calls the use action',async()=>{
 mount();await scan();button('前往用车').click();await settle();app!.unmount();root.remove();mount();await settle();driver.act.mockClear();driver.shortcut.mockResolvedValue('home_requested');button('返回官方用车').click();await settle();expect(driver.shortcut).toHaveBeenCalledExactlyOnceWith('hello','home','alipay');expect(driver.act).not.toHaveBeenCalled();expect(root.textContent).toContain('不会重新传入车码');
});
it('missing scanner and network-like failure preserve previous recent entry without inventing state',async()=>{
 mount();await scan();button('前往用车').click();await settle();const old=loadRecentBike();driver.shortcut.mockResolvedValue('unavailable');button('美团官方扫码').click();await settle();expect(loadRecentBike()).toEqual(old);expect(root.textContent).toContain('可能未安装');expect(root.textContent).not.toContain('已还车');
});
it('unknown QR and camera denial remain retryable and never launch',async()=>{
 driver.scan.mockRejectedValueOnce({code:'QR',message:'PRIVATE'});mount();await scan();expect(root.textContent).toContain('暂不支持这个二维码');expect(root.textContent).not.toContain('PRIVATE');
 driver.scan.mockRejectedValueOnce({code:'PERMISSION'});await scan();expect(root.textContent).toContain('相机权限');expect(driver.act).not.toHaveBeenCalled();
});
it('repeat use taps coalesce; rescan cancellation drops stale vehicle actions',async()=>{
 mount();await scan();let finish!:(v:string)=>void;driver.act.mockImplementationOnce(()=>new Promise(r=>finish=r));button('前往用车').click();button('前往用车').click();await settle();expect(driver.act).toHaveBeenCalledTimes(1);finish('unavailable');await settle();driver.scan.mockRejectedValueOnce({code:'CANCELLED'});button('重新扫码').click();await settle();expect(root.textContent).not.toContain(bike.number);expect(root.textContent).not.toContain('前往用车');
});
it('clearing removes local recent and number but does not claim ride completion',async()=>{
 mount();await scan();button('前往用车').click();await settle();driver.shortcut.mockClear();button('清除入口记录').click();await settle();expect(loadRecentBike()).toBeUndefined();expect(root.textContent).not.toContain(bike.number);expect(root.textContent).toContain('官方订单不受影响');expect(driver.shortcut).not.toHaveBeenCalled();
});
it('expired entry is removed on foreground without launching or retrying any operation',async()=>{
 vi.useFakeTimers({toFake:['Date']});mount();await scan();button('前往用车').click();await settle();driver.shortcut.mockClear();vi.setSystemTime(Date.now()+recentBikeLifetime);window.dispatchEvent(new Event('focus'));await settle();expect(loadRecentBike()).toBeUndefined();expect(root.textContent).not.toContain('最近打开的入口');expect(driver.shortcut).not.toHaveBeenCalled();
});
it('closing ignores late scanner result and clears temporary native ticket',async()=>{
 let finish!:(v:unknown)=>void;driver.scan.mockImplementationOnce(()=>new Promise(r=>finish=r));mount();button('哈啰扫码用车').click();await settle();app!.unmount();app=undefined;finish(bike);await settle();expect(driver.clear).toHaveBeenCalled();expect(driver.act).not.toHaveBeenCalled();expect(loadRecentBike()).toBeUndefined();
});
it('web preview does not attempt camera or app access',async()=>{
 driver.supported=false;mount();await settle();expect(driver.scan).not.toHaveBeenCalled();expect(root.textContent).toContain('Android');
});
