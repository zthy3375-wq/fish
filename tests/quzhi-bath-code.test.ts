// @vitest-environment jsdom
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick,ref} from 'vue';
import QuzhiBathCode from '../src/components/QuzhiBathCode.vue';
import {quzhi,quzhiBusy,loadQuzhiBathCode} from '../src/composables/quzhi';
import type {QuzhiBathCode as Code} from '../src/services/quzhi-client';
vi.mock('../src/composables/quzhi',async()=>{const {ref}=await import('vue');return {quzhi:ref({}),quzhiBusy:ref(false),quzhiReady:ref(true),loadQuzhiBathCode:vi.fn()}});
let app:ReturnType<typeof createApp>,root:HTMLElement;
const active=ref(true),sample:Code={code:'00123456',enabled:true,phone:'138****0000',queriedAt:1794272400000};
function button(name:string){return [...root.querySelectorAll('button')].find(b=>b.textContent?.trim()===name)!}
async function settle(){for(let i=0;i<8;i++)await Promise.resolve();await nextTick()}
async function reveal(){button('查看洗澡码').click();await settle()}
beforeEach(async()=>{vi.clearAllMocks();active.value=true;quzhiBusy.value=false;quzhi.value={connected:true,expired:false,phone:sample.phone};vi.spyOn(document,'visibilityState','get').mockReturnValue('visible');vi.mocked(loadQuzhiBathCode).mockResolvedValue({...sample});root=document.createElement('div');document.body.append(root);app=createApp({render:()=>h(QuzhiBathCode,{active:active.value})});app.mount(root);await settle()});
afterEach(()=>{app.unmount();root.remove();vi.restoreAllMocks()});
it('queries only on explicit reveal and leaves generic wallet snapshot untouched',async()=>{const prior=JSON.stringify(quzhi.value);expect(loadQuzhiBathCode).not.toHaveBeenCalled();await reveal();expect(root.querySelector('.bath-digits')?.textContent).toBe('00123456');expect(JSON.stringify(quzhi.value)).toBe(prior);button('收起').click();await settle();expect(root.textContent).not.toContain(sample.code)});
it('does not claim a disabled code can be used',async()=>{vi.mocked(loadQuzhiBathCode).mockResolvedValue({...sample,enabled:false});await reveal();expect(root.querySelector('.bath-digits')).toBeNull();expect(root.textContent).toContain('尚未开启')});
it('clears displayed code when refresh fails',async()=>{await reveal();vi.mocked(loadQuzhiBathCode).mockRejectedValue(Error('查询失败'));button('刷新洗澡码').click();await settle();expect(root.textContent).not.toContain(sample.code);expect(root.getElementsByClassName('bath-error')[0].textContent).toContain('查询失败')});
it.each([{...sample,code:'456'},{...sample,phone:'139****0000'},{...sample,enabled:true,code:null}])('rejects incomplete or mismatched code result',async result=>{vi.mocked(loadQuzhiBathCode).mockResolvedValue(result);await reveal();expect(root.querySelector('.bath-digits')).toBeNull();expect(root.textContent).toContain('信息不完整')});
it('hides code on native background and does not automatically reveal on return',async()=>{await reveal();active.value=false;await settle();expect(root.querySelector('.bath-digits')).toBeNull();active.value=true;await settle();expect(loadQuzhiBathCode).toHaveBeenCalledTimes(1);expect(root.querySelector('.bath-digits')).toBeNull()});
it('ignores a late response after hiding the page',async()=>{let finish!:(code:Code)=>void;vi.mocked(loadQuzhiBathCode).mockReturnValue(new Promise(resolve=>finish=resolve));await reveal();document.dispatchEvent(new Event('visibilitychange'));active.value=false;await settle();finish(sample);await settle();expect(root.querySelector('.bath-digits')).toBeNull()});
it('hides immediately on web visibility change',async()=>{await reveal();vi.spyOn(document,'visibilityState','get').mockReturnValue('hidden');document.dispatchEvent(new Event('visibilitychange'));await settle();expect(root.querySelector('.bath-digits')).toBeNull()});
it('hides when session expires or identity changes',async()=>{await reveal();quzhi.value={...quzhi.value,expired:true};await settle();expect(root.querySelector('.bath-digits')).toBeNull();expect(button('查看洗澡码').disabled).toBe(true);quzhi.value={connected:true,expired:false,phone:sample.phone};await settle();await reveal();quzhi.value={...quzhi.value,phone:'139****0000'};await settle();expect(root.querySelector('.bath-digits')).toBeNull()});
