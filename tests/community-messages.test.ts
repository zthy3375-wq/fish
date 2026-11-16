// @vitest-environment jsdom
import {afterAll,afterEach,beforeAll,beforeEach,expect,it,vi} from 'vitest';
import {createApp,h,nextTick,reactive} from 'vue';
import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
// @ts-expect-error Server module is tested as the real JavaScript implementation.
import {createCommunity} from '../cloudbase/functions/community/core.mjs';
import Messages from '../src/components/TreeholeMessages.vue';
import type {TreeholeMessageDraft} from '../src/services/treehole';
const bridge=vi.hoisted(()=>({execute:vi.fn()}));
vi.mock('../src/services/treehole',async original=>({...await original<object>(),treeholeRequest:(...args:unknown[])=>bridge.execute(...args)}));
let pg:PGlite,api:any,a:any,b:any,thread:any,app:ReturnType<typeof createApp>|null,root:HTMLElement,drafts:Record<string,TreeholeMessageDraft>,expired:number;
const call=(who:any,action:string,body={})=>api.execute(action,body,who.sessionToken,'dom');
const rows=()=>root.querySelectorAll('.dm-message');
const button=(name:string)=>[...root.querySelectorAll<HTMLButtonElement>('button')].find(x=>x.getAttribute('aria-label')===name||x.textContent?.trim()===name)!;
async function ready(check:()=>void){await expect.poll(check,{timeout:6000}).toBeTruthy();await nextTick();}
async function mount(member=b.user.id){root=document.createElement('div');document.body.append(root);app=createApp(Messages,{initialMember:member,drafts,onExpired:()=>expired++});app.mount(root);await ready(()=>!!root.querySelector('textarea')&&!root.querySelector('.dm-state'));}
async function type(body:string){const input=root.querySelector('textarea')!;input.value=body;input.dispatchEvent(new Event('input',{bubbles:true}));await nextTick();}
async function submit(){root.querySelector('form')!.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));await nextTick();}
beforeAll(async()=>{pg=new PGlite();await pg.exec(await readFile('cloudbase/community-schema.sql','utf8'));api=createCommunity({registrationEnabled:true,db:async(action:string,body:object,hash:string)=>(await pg.query<any>('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result});const reg=(username:string)=>api.execute('register',{username,nickname:username,password:'synthetic-dom-password',agreed:true},'',username);a=await reg('dom_alice');b=await reg('dom_bob');});
beforeEach(async()=>{await pg.exec('DELETE FROM hyt_dm_reads; DELETE FROM hyt_dm_messages; DELETE FROM hyt_dm_threads; DELETE FROM hyt_blocks; DELETE FROM hyt_follows; DELETE FROM hyt_community_rate;');thread=(await call(a,'messages.open',{memberId:b.user.id})).conversation;drafts=reactive({});expired=0;bridge.execute.mockReset().mockImplementation((action,body)=>call(a,action,body));Object.defineProperty(document,'hidden',{value:false,configurable:true});});
afterEach(()=>{app?.unmount();app=null;root?.remove();});afterAll(async()=>pg.close());
it('renders literal private text and retries a committed send with the original idempotency key',async()=>{
 let drop=true;bridge.execute.mockImplementation(async(action,body)=>{const r=await call(a,action,body);if(action==='messages.send'&&drop){drop=false;throw Error('network_unavailable');}return r;});await mount();await type('<script>合成私信</script>');await submit();await ready(()=>!!button('重试发送私信'));expect(root.querySelector('textarea')!.value).toBe('<script>合成私信</script>');await submit();await ready(()=>rows().length===1&&!root.querySelector('textarea')!.value);expect(root.querySelector('.dm-message p')!.textContent).toBe('<script>合成私信</script>');expect(root.querySelector('script')).toBeNull();expect((await call(b,'messages.list',{conversationId:thread.id})).messages).toHaveLength(1);
});
it('keeps a draft across a normal unmount and reopening, with no automatic send',async()=>{
 await mount();await type('还没发完');app!.unmount();app=null;root.remove();await mount();expect(root.querySelector('textarea')!.value).toBe('还没发完');expect(bridge.execute.mock.calls.some(c=>c[0]==='messages.send')).toBe(false);
});
it('starts a new request after editing a failed draft and retains the new text',async()=>{
 bridge.execute.mockImplementation((action,body)=>action==='messages.send'?Promise.reject(Error('network_unavailable')):call(a,action,body));await mount();await type('失败草稿');await submit();await ready(()=>!!button('重试发送私信'));const key=drafts[thread.id].requestId;await type('改过的草稿');expect(drafts[thread.id].requestId).not.toBe(key);expect(drafts[thread.id].body).toBe('改过的草稿');
});
it('loads older history without dropping already rendered pages',async()=>{
 for(let i=0;i<65;i++)await pg.query("INSERT INTO hyt_dm_messages(thread_id,sender_id,body,request_id) VALUES($1,$2,$3,$4)",[thread.id,b.user.id,'历史 '+i,randomUUID()]);await mount();expect(rows()).toHaveLength(30);button('查看更早消息').click();await ready(()=>rows().length===60);button('查看更早消息').click();await ready(()=>rows().length===65);expect(new Set([...rows()].map(x=>x.getAttribute('data-message-id'))).size).toBe(65);
});
it('incremental refresh drains a gap larger than one page without silently skipping messages',async()=>{
 await call(b,'messages.send',{conversationId:thread.id,body:'原有消息',requestId:randomUUID()});await mount();expect(rows()).toHaveLength(1);for(let i=0;i<65;i++)await pg.query("INSERT INTO hyt_dm_messages(thread_id,sender_id,body,request_id) VALUES($1,$2,$3,$4)",[thread.id,b.user.id,'新消息 '+i,randomUUID()]);document.dispatchEvent(new Event('visibilitychange'));await ready(()=>rows().length===66);expect(root.querySelector('.dm-message:last-child p')!.textContent).toBe('新消息 64');
});
it('blocks through the real server, clears the draft and disables both the composer and future sends',async()=>{
 await mount();await type('不发送');button('屏蔽私信对象').click();await nextTick();button('确认屏蔽').click();await ready(()=>root.querySelector('textarea')!.disabled);expect(drafts[thread.id]).toBeUndefined();expect((await call(b,'messages.inbox')).conversations).toHaveLength(0);await expect(call(b,'messages.send',{conversationId:thread.id,body:'已屏蔽',requestId:randomUUID()})).rejects.toMatchObject({code:'conversation_unavailable'});
});
it('read-acknowledgement failures have explicit retry and retain the displayed messages',async()=>{
 await call(b,'messages.send',{conversationId:thread.id,body:'待读',requestId:randomUUID()});let fail=true,unreadFail=true;bridge.execute.mockImplementation((action,body)=>{if(action==='messages.read'&&fail)return Promise.reject(Error('network_unavailable'));if(action==='messages.unread'&&!fail&&unreadFail){unreadFail=false;return Promise.reject(Error('network_unavailable'));}return call(a,action,body);});await mount();await ready(()=>!!button('未读状态尚未同步，点击重试'));expect(rows()).toHaveLength(1);fail=false;button('未读状态尚未同步，点击重试').click();await ready(()=>!unreadFail);await ready(()=>!!button('未读状态尚未同步，点击重试'));button('未读状态尚未同步，点击重试').click();await ready(()=>!button('未读状态尚未同步，点击重试'));expect((await call(a,'messages.unread')).messageUnreadCount).toBe(0);
});
it('late history responses after unmount cannot publish message text or write another account draft',async()=>{
 await mount();await type('本机草稿');let release:()=>void=()=>{};bridge.execute.mockImplementation(async(action,body)=>{const r=await call(a,action,body);if(action==='messages.list')await new Promise<void>(resolve=>release=resolve);return r;});document.dispatchEvent(new Event('visibilitychange'));await new Promise(r=>setTimeout(r,30));app!.unmount();app=null;root.textContent='新账号页面';release();await new Promise(r=>setTimeout(r,30));expect(root.textContent).toBe('新账号页面');expect(drafts[thread.id].body).toBe('本机草稿');
});
it('an expired private session reports expiry and does not persist its draft on unmount',async()=>{
 await mount();await type('过期账号草稿');delete drafts[thread.id];bridge.execute.mockImplementation(()=>Promise.reject(Error('session_expired')));document.dispatchEvent(new Event('visibilitychange'));await ready(()=>expired===1);app!.unmount();app=null;expect(drafts[thread.id]).toBeUndefined();
});
