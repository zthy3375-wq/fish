// @vitest-environment jsdom
import {beforeEach,expect,it,vi} from 'vitest';
import {createApp,nextTick} from 'vue';
const bridge=vi.hoisted(()=>({getState:vi.fn(),deleteData:vi.fn()}));
vi.mock('@capacitor/core',()=>({Capacitor:{isPluginAvailable:()=>true},registerPlugin:()=>bridge}));
import {legacy,retryLegacyDeletion} from '../src/composables/analytics';
import Settings from '../src/components/AnalyticsSettings.vue';
beforeEach(()=>{vi.clearAllMocks();legacy.value={hasHistory:false,deletePending:false}});
it('fresh and previously enrolled installations issue no usage requests on resume',async()=>{
 for(const hasHistory of [false,true]){
  bridge.getState.mockResolvedValue({hasHistory,deletePending:false});
  await retryLegacyDeletion();expect(bridge.deleteData).not.toHaveBeenCalled();
  const root=document.createElement('div'),app=createApp(Settings);app.mount(root);await nextTick();
  expect(root.querySelector('input')).toBeNull();expect(root.textContent?.includes('删除旧版')).toBe(hasHistory);app.unmount();
 }
});
it('only retries a deletion the user already requested',async()=>{
 bridge.getState.mockResolvedValue({hasHistory:true,deletePending:true});
 bridge.deleteData.mockResolvedValue({hasHistory:false,deletePending:false});
 await retryLegacyDeletion();expect(bridge.deleteData).toHaveBeenCalledOnce();expect(legacy.value.hasHistory).toBe(false);
});
