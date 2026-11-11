// @vitest-environment jsdom
import {createApp,nextTick,type App} from 'vue';
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
const driver=vi.hoisted(()=>({scan:vi.fn(),act:vi.fn(),clear:vi.fn(),supported:true}));
vi.mock('../src/services/bike-scan',async importOriginal=>({...await importOriginal<any>(),scanBike:driver.scan,actOnBike:driver.act,clearBike:driver.clear,bikeSupported:()=>driver.supported}));
import BikeScan from '../src/components/BikeScan.vue';
const bike={provider:'hello',number:'9150978196',ticket:'11111111-1111-4111-8111-111111111111'};
let app:App|undefined,root:HTMLElement;
async function settle(){await Promise.resolve();await nextTick();await Promise.resolve();await nextTick()}
function mount(){root=document.createElement('div');document.body.append(root);app=createApp(BikeScan);app.mount(root)}
function button(label:string){const b=[...root.querySelectorAll('button')].find(b=>b.textContent?.includes(label));if(!b)throw Error(label);return b}
beforeEach(()=>{driver.supported=true;driver.scan.mockReset().mockResolvedValue(bike);driver.act.mockReset().mockResolvedValue('alipay_requested');driver.clear.mockReset().mockResolvedValue(undefined)});
afterEach(()=>{app?.unmount();app=undefined;root?.remove()});
it('opening starts one scan but a recognized vehicle never launches itself',async()=>{
 mount();await settle();expect(driver.scan).toHaveBeenCalledTimes(1);expect(root.textContent).toContain('9150978196');expect(driver.act).not.toHaveBeenCalled();
 button('前往用车').click();await settle();expect(driver.act).toHaveBeenCalledExactlyOnceWith(bike,'use');expect(root.textContent).toContain('请核对车辆');expect(root.textContent).not.toContain('开锁成功');
});
it('unknown QR and camera denial are recoverable without a launch',async()=>{
 driver.scan.mockRejectedValueOnce({code:'QR',message:'PRIVATE'});mount();await settle();expect(root.textContent).toContain('暂不支持这个二维码');expect(root.textContent).not.toContain('PRIVATE');expect(root.textContent).not.toContain('前往用车');
 driver.scan.mockRejectedValueOnce({code:'PERMISSION'});button('扫描车身二维码').click();await settle();expect(root.textContent).toContain('相机权限');expect(driver.act).not.toHaveBeenCalled();
});
it('repeat taps coalesce and explicit fallback tells the user to scan again',async()=>{
 mount();await settle();let finish!:(v:string)=>void;driver.act.mockImplementationOnce(()=>new Promise(r=>finish=r));button('前往用车').click();button('前往用车').click();await settle();expect(driver.act).toHaveBeenCalledTimes(1);
 finish('unavailable');await settle();expect(root.textContent).toContain('可能未安装');driver.act.mockResolvedValue('scanner_requested');button('尝试打开官方扫码').click();await settle();expect(root.textContent).toContain('再次扫描');
});
it('rescanning drops the former vehicle and failure does not leave a stale action',async()=>{
 mount();await settle();driver.scan.mockRejectedValueOnce({code:'CANCELLED'});button('重新扫码').click();await settle();expect(root.textContent).not.toContain('9150978196');expect(root.textContent).not.toContain('前往用车');expect(root.textContent).toContain('已取消扫码');
});
it('closing clears the native ticket and ignores a late scan result',async()=>{
 let finish!:(v:unknown)=>void;driver.scan.mockImplementationOnce(()=>new Promise(r=>finish=r));mount();app!.unmount();app=undefined;finish(bike);await settle();expect(driver.clear).toHaveBeenCalledTimes(1);expect(driver.act).not.toHaveBeenCalled();
});
it('web preview does not attempt camera access',async()=>{
 driver.supported=false;mount();await settle();expect(driver.scan).not.toHaveBeenCalled();expect(root.textContent).toContain('Android');
});
