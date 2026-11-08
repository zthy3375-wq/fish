// @vitest-environment jsdom
import {beforeEach,afterEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
const mocks=vi.hoisted(()=>({getState:vi.fn(),check:vi.fn(),download:vi.fn(),install:vi.fn()}));
vi.mock('@capacitor/core',()=>({Capacitor:{isNativePlatform:()=>true,isPluginAvailable:()=>true},registerPlugin:()=>mocks}));
vi.mock('@capacitor/app',()=>({App:{exitApp:vi.fn()}}));
import {updateState,updateRequested,updateDeferred,updatesOpen,checkUpdates,dismissUpdate,installUpdate} from '../src/composables/updates';
import AppUpdateDialog from '../src/components/AppUpdateDialog.vue';
const release={versionCode:102,versionName:'1.0.2',minSupportedVersionCode:102,minSdk:23,apkUrl:'https://example.test/update.apk',sha256:'a'.repeat(64),sizeBytes:12000000,notes:['修复课表问题']};
let app:ReturnType<typeof createApp>,root:HTMLElement;
beforeEach(()=>{vi.useFakeTimers();vi.clearAllMocks();updateState.value={currentVersion:'1.0.1',currentCode:101,stage:'idle',progress:0,error:'',available:true,mandatory:true,release,checkedAt:0};updateRequested.value=false;updateDeferred.value=false;root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(AppUpdateDialog)});app.mount(root)});
afterEach(()=>{app.unmount();root.remove();vi.useRealTimers()});
it('mandatory update cannot be dismissed and has an exit route',async()=>{dismissUpdate();await nextTick();expect(updatesOpen.value).toBe(true);expect(document.body.textContent).toContain('退出应用');expect(document.body.textContent).not.toContain('稍后再说')});
it('optional update may be dismissed',async()=>{updateState.value.mandatory=false;updateRequested.value=true;await nextTick();expect(document.body.textContent).toContain('稍后再说');dismissUpdate();expect(updatesOpen.value).toBe(false)});
it('network failure preserves a known required version',async()=>{mocks.check.mockRejectedValue(Error('offline'));await checkUpdates(true);expect(updateState.value.mandatory).toBe(true);expect(updatesOpen.value).toBe(true);expect(updateState.value.error).toContain('重试')});
it('a fresh withdrawn requirement clears the old block',async()=>{mocks.check.mockResolvedValue({...updateState.value,mandatory:false,available:false,release:undefined});await checkUpdates(true);expect(updateState.value.mandatory).toBe(false);dismissUpdate();expect(updatesOpen.value).toBe(false)});
it('defers the blocking overlay during water or editing flows',async()=>{updateDeferred.value=true;await nextTick();expect(updatesOpen.value).toBe(false);await installUpdate();expect(mocks.install).not.toHaveBeenCalled();updateDeferred.value=false;await nextTick();expect(updatesOpen.value).toBe(true)});
it('install permission is a separate explicit step, not install success',async()=>{mocks.install.mockResolvedValue({status:'permission'});await installUpdate();await nextTick();expect(document.body.textContent).toContain('允许来自此来源');expect(mocks.install).toHaveBeenCalledTimes(1)});
it('download progress disables duplicate requests',async()=>{updateState.value.stage='downloading';updateState.value.progress=54;await nextTick();expect(document.querySelector('progress')?.value).toBe(54);expect([...document.querySelectorAll('button')].find(b=>b.textContent==='正在下载…')?.disabled).toBe(true)});
