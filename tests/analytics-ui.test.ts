// @vitest-environment jsdom
import {beforeEach,afterEach,it,expect,vi} from 'vitest';
import {createApp,h,nextTick} from 'vue';
const native=vi.hoisted(()=>({getState:vi.fn(),setEnabled:vi.fn(),record:vi.fn(),flush:vi.fn(),deleteData:vi.fn()}));
vi.mock('@capacitor/core',()=>({Capacitor:{isNativePlatform:()=>true,isPluginAvailable:()=>true},registerPlugin:()=>native}));
import {analytics,analyticsReady,recordFeature,chooseAnalytics,deleteAnalytics} from '../src/composables/analytics';
import AnalyticsSettings from '../src/components/AnalyticsSettings.vue';
let app:ReturnType<typeof createApp>,root:HTMLElement;
beforeEach(()=>{vi.useFakeTimers();vi.clearAllMocks();analytics.value={choice:'unset',deletePending:false,lastSent:0};analyticsReady.value=true;root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(AnalyticsSettings)});app.mount(root)});
afterEach(()=>{app.unmount();root.remove();vi.useRealTimers()});
it('never records before consent or after opting out',async()=>{await recordFeature('water');analytics.value.choice='off';await recordFeature('water');expect(native.record).not.toHaveBeenCalled()});
it('offers an explicit choice without blocking campus actions',()=>{expect(root.textContent).toContain('允许匿名统计');expect(root.textContent).toContain('暂不参与');expect(root.querySelector('[role=dialog]')).toBeNull()});
it('enabling persists native consent and allows only a feature code',async()=>{native.setEnabled.mockResolvedValue({choice:'on',deletePending:false,lastSent:0});native.flush.mockResolvedValue({choice:'on',deletePending:false,lastSent:0});await chooseAnalytics(true);await recordFeature('schedule');expect(native.record).toHaveBeenCalledWith({feature:'schedule'})});
it('network reporting failure does not throw into the app',async()=>{analytics.value.choice='on';native.record.mockRejectedValue(Error('offline'));await expect(recordFeature('tasks')).resolves.toBeUndefined()});
it('delete disables tracking and explains deferred retry',async()=>{native.deleteData.mockResolvedValue({choice:'off',deletePending:true,lastSent:0});await deleteAnalytics();await nextTick();expect(root.textContent).toContain('正在请求删除');expect(root.querySelector<HTMLInputElement>('input')?.disabled).toBe(true);await recordFeature('water');expect(native.record).not.toHaveBeenCalled()});
