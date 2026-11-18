// @vitest-environment jsdom
import {afterEach,beforeEach,it,expect,vi} from 'vitest';
import {createApp,nextTick} from 'vue';
import Treehole from '../src/components/Treehole.vue';
const storage=vi.hoisted(()=>({write:vi.fn(),read:vi.fn(),remove:vi.fn()}));
vi.mock('../src/services/treeholeDrafts',async original=>({...await original<object>(),readTreeholeDraft:storage.read,writeTreeholeDraft:storage.write,deleteTreeholeDraft:storage.remove}));
vi.mock('../src/services/treehole',async original=>({...await original<object>(),treeholeRequest:vi.fn(async(action:string)=>action==='config'?{registrationEnabled:true}:action==='me'?{user:{id:'synthetic-draft-user',username:'draft_user',nickname:'草稿测试',role:'member',bannedUntil:null}}:{posts:[],next:null})}));
let app:ReturnType<typeof createApp>|undefined,root:HTMLElement;
const wait=(check:()=>unknown)=>expect.poll(check,{timeout:3000}).toBeTruthy();
beforeEach(()=>{storage.read.mockReset().mockResolvedValue(undefined);storage.write.mockReset().mockResolvedValue(undefined);storage.remove.mockReset().mockResolvedValue(undefined);window.scrollTo=vi.fn();HTMLElement.prototype.scrollIntoView=vi.fn();window.matchMedia=vi.fn().mockReturnValue({matches:true,addEventListener:vi.fn(),removeEventListener:vi.fn()});root=document.createElement('div');document.body.append(root);});
afterEach(()=>{app?.unmount();app=undefined;root.remove();});
async function compose(){app=createApp(Treehole);app.mount(root);await wait(()=>root.querySelector('.th-fab'));root.querySelector<HTMLButtonElement>('.th-fab')!.click();await nextTick();}
async function type(value:string){const input=root.querySelector<HTMLTextAreaElement>('.th-compose-writing textarea')!;input.value=value;input.dispatchEvent(new Event('input',{bubbles:true}));await nextTick();}
it('does not confirm a newer draft when an older queued write finishes',async()=>{
 let first!:(value?:unknown)=>void,second!:(value?:unknown)=>void;
 storage.write.mockImplementationOnce(()=>new Promise(r=>first=r)).mockImplementationOnce(()=>new Promise(r=>second=r));
 await compose();await type('第一版');await wait(()=>storage.write.mock.calls.length===1);
 await type('第二版仍未写入');await new Promise(r=>setTimeout(r,210));first();
 await wait(()=>storage.write.mock.calls.length===2);expect(root.querySelector('.th-draft-status')?.textContent).toContain('保存中');
 second();await wait(()=>root.querySelector('.th-draft-status')?.textContent?.includes('草稿已保存'));
 expect(storage.write.mock.calls[1][1].body).toBe('第二版仍未写入');
});
it('offers an explicit save retry without losing the current text',async()=>{
 storage.write.mockRejectedValueOnce(Error('synthetic_storage_failure')).mockResolvedValue(undefined);
 await compose();await type('这段文字需要保留');await wait(()=>root.querySelector('.th-draft-retry'));
 root.querySelector<HTMLButtonElement>('.th-draft-retry')!.click();await wait(()=>root.querySelector('.th-draft-status')?.textContent?.includes('草稿已保存'));
 expect(root.querySelector<HTMLTextAreaElement>('textarea')?.value).toBe('这段文字需要保留');expect(storage.write).toHaveBeenCalledTimes(2);
});
