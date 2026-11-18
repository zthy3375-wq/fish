// @vitest-environment jsdom
import 'fake-indexeddb/auto';
import {afterAll,afterEach,beforeAll,beforeEach,expect,it,vi} from 'vitest';
import {createApp,nextTick} from 'vue';
import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
// @ts-expect-error Exercise the real server module with PostgreSQL.
import {createCommunity} from '../cloudbase/functions/community/core.mjs';
import Treehole from '../src/components/Treehole.vue';
const bridge=vi.hoisted(()=>({execute:vi.fn()}));
vi.mock('../src/services/treehole',async original=>({...await original<object>(),treeholeRequest:(...args:unknown[])=>bridge.execute(...args)}));
let pg:PGlite,api:any,a:any,b:any,app:ReturnType<typeof createApp>|null,root:HTMLElement,legacy=false,failStats=false,legacyResponses=false;
const call=(who:any,action:string,body={})=>api.execute(action,body,who.sessionToken,'social-ui');
const button=(name:string)=>[...root.querySelectorAll<HTMLButtonElement>('button')].find(x=>x.getAttribute('aria-label')===name||x.textContent?.trim()===name)!;
const wait=async(check:()=>unknown)=>{await expect.poll(check,{timeout:6000}).toBeTruthy();await nextTick();};
async function mount(){root=document.createElement('div');document.body.append(root);app=createApp(Treehole);app.mount(root);await wait(()=>!!root.querySelector('.th-self')&&!root.querySelector('.th-progress'));}
beforeAll(async()=>{pg=new PGlite();await pg.exec(await readFile('cloudbase/community-schema.sql','utf8'));api=createCommunity({registrationEnabled:true,db:async(action:string,body:object,hash:string)=>(await pg.query<any>('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result});const reg=(username:string)=>api.execute('register',{username,nickname:username,password:'synthetic-social-ui-password',agreed:true},'',username);a=await reg('social_alice');b=await reg('social_bob');});
beforeEach(async()=>{await pg.exec('DELETE FROM hyt_follows; DELETE FROM hyt_blocks; DELETE FROM hyt_community_rate; TRUNCATE hyt_posts CASCADE;');legacy=false;failStats=false;legacyResponses=false;window.scrollTo=vi.fn();HTMLElement.prototype.scrollIntoView=vi.fn();window.matchMedia=vi.fn().mockReturnValue({matches:true,addEventListener:vi.fn(),removeEventListener:vi.fn()});bridge.execute.mockReset().mockImplementation((action,body)=>{if(action==='me'&&(legacy||legacyResponses))return call(a,'me',{});if(action==='config'){const c=api.config();if(legacyResponses)delete c.responseKinds;if(legacy){delete c.socialEnabled;delete c.messagesEnabled;}return c;}if(action==='follows.stats'&&failStats)throw Error('network_unavailable');return call(a,action,body);});});
afterEach(()=>{app?.unmount();app=null;root.remove();});afterAll(()=>pg.close());
it('exposes real counts and own follower/following lists, supports follow-back, and opens private chat from a profile',async()=>{
 await call(b,'follows.set',{memberId:a.user.id,enabled:true});await mount();root.querySelector<HTMLButtonElement>('.th-self')!.click();await wait(()=>button('我的粉丝列表')?.querySelector('strong')?.textContent==='1');expect(button('我的关注列表').querySelector('strong')!.textContent).toBe('0');button('我的粉丝列表').click();await wait(()=>!!button('回关 social_bob'));button('回关 social_bob').click();await wait(()=>!!button('取消关注 social_bob'));expect(root.querySelectorAll('.th-person')).toHaveLength(1);
 button('返回社区').click();await wait(()=>button('我的关注列表')?.querySelector('strong')?.textContent==='1');button('我的关注列表').click();await wait(()=>!!button('查看 social_bob 的主页'));button('查看 social_bob 的主页').click();await wait(()=>!!button('发私信'));button('发私信').click();await wait(()=>!!root.querySelector('[aria-label="私信内容"]')&&!root.querySelector('.dm-state'));expect(root.querySelector('.dm-chat-heading')!.textContent).toContain('social_bob');expect(root.textContent).not.toContain('sessionToken');
});
it('shows failed social statistics as unavailable with explicit retry, then restores server counts',async()=>{
 await call(b,'follows.set',{memberId:a.user.id,enabled:true});failStats=true;await mount();root.querySelector<HTMLButtonElement>('.th-self')!.click();await wait(()=>!!button('重试统计'));expect(button('我的粉丝列表').querySelector('strong')!.textContent).toBe('—');failStats=false;button('重试统计').click();await wait(()=>button('我的粉丝列表')?.querySelector('strong')?.textContent==='1');
});
it('retains existing following support with an older server while hiding unsupported private messaging and fan counts',async()=>{
 legacy=true;await mount();root.querySelector<HTMLButtonElement>('.th-self')!.click();await nextTick();expect(button('我关注的人')).toBeDefined();expect(button('我的粉丝列表')).toBeUndefined();expect(button('我的私信')).toBeUndefined();expect(bridge.execute.mock.calls.some(c=>c[0].startsWith('messages.')||c[0]==='follows.stats')).toBe(false);
});

it('composer exposes a writing surface, one attachment toolbar and an explicit anonymous identity',async()=>{
 await mount();button('发帖').click();await wait(()=>!!root.querySelector('.th-compose-writing'));expect(root.querySelectorAll('[aria-label="帖子附件"]')).toHaveLength(1);expect(root.querySelector('.th-add-photo')).toBeNull();expect(root.querySelector('.th-title-input')!.getAttribute('placeholder')).toBe('标题（选填）');const body=root.querySelector<HTMLTextAreaElement>('textarea')!;expect(body.required).toBe(true);expect(button('以昵称发布').disabled).toBe(true);
 body.value='一件普通的小事';body.dispatchEvent(new Event('input',{bubbles:true}));await nextTick();expect(button('以昵称发布').disabled).toBe(false);const anon=root.querySelector<HTMLInputElement>('.th-anon-pill input')!;anon.checked=true;anon.dispatchEvent(new Event('change',{bubbles:true}));await nextTick();expect(button('匿名发布')).toBeDefined();expect(root.querySelector('.th-compose-identity')!.textContent).toContain('匿名身份');button('返回社区').click();await wait(()=>!!button('保存草稿并返回'));button('保存草稿并返回').click();await wait(()=>!!root.querySelector('.th-draft-resume'));
});
it('pointer and keyboard navigation retain distinct feedback modes without changing the input text',async()=>{
 await mount();button('发帖').click();await wait(()=>!!root.querySelector('.th-compose-writing'));const body=root.querySelector<HTMLTextAreaElement>('textarea')!;body.focus();body.dispatchEvent(new KeyboardEvent('keydown',{key:'Tab',bubbles:true}));await nextTick();expect(root.querySelector('.treehole')!.classList.contains('keyboard-navigation')).toBe(true);body.dispatchEvent(new MouseEvent('pointerdown',{bubbles:true}));await nextTick();expect(root.querySelector('.treehole')!.classList.contains('keyboard-navigation')).toBe(false);expect(document.activeElement).toBe(body);
});
it('reaction row is useful, joy, hug and supports a real independent joy choice without entering the post',async()=>{
 const p=(await call(b,'posts.create',{body:'合成欢乐帖',anonymous:false,requestId:crypto.randomUUID()})).post;await mount();const choices=[...root.querySelectorAll<HTMLButtonElement>('.th-responses button')];expect(choices.map(x=>x.getAttribute('aria-label'))).toEqual(['有用','欢乐','抱抱']);choices[1].click();await wait(()=>choices[1].getAttribute('aria-pressed')==='true');await wait(()=>!choices[1].disabled);expect(root.querySelector('.th-detail')).toBeNull();expect((await call(a,'posts.get',{postId:p.id})).post.myResponse).toBe('joy');choices[1].click();await wait(()=>choices[1].getAttribute('aria-pressed')==='false');expect((await call(a,'posts.get',{postId:p.id})).post.responseCounts).toEqual({});
});
it('old response services keep useful and hug while an unavailable joy never writes an old same vote',async()=>{
 legacyResponses=true;const p=(await call(b,'posts.create',{body:'旧服务合成帖子',anonymous:false,requestId:crypto.randomUUID()})).post;await mount();const joy=button('欢乐');expect(joy.getAttribute('aria-disabled')).toBe('true');joy.click();await nextTick();expect(bridge.execute.mock.calls.some(c=>c[0]==='responses.set')).toBe(false);expect(root.textContent).toContain('欢乐回应暂时不可用');button('有用').click();await wait(()=>button('有用').getAttribute('aria-pressed')==='true');expect((await call(a,'posts.get',{postId:p.id})).post.myResponse).toBe('useful');
});
it('adding a poll expands only its editor and prevents publication until the choices are complete',async()=>{
 await mount();button('发帖').click();await wait(()=>!!button('添加投票'));button('添加投票').click();await nextTick();expect(root.querySelector('[aria-label="编辑投票"]')).not.toBeNull();expect(root.querySelector<HTMLButtonElement>('.th-publish')!.disabled).toBe(true);for(const [label,value] of [['投票问题','周末去哪'],['投票选项 1','图书馆'],['投票选项 2','操场']]){const input=root.querySelector<HTMLInputElement>('[aria-label="'+label+'"]')!;input.value=value;input.dispatchEvent(new Event('input',{bubbles:true}));await nextTick();}await nextTick();expect(root.querySelector<HTMLButtonElement>('.th-publish')!.disabled).toBe(false);button('移除投票').click();await nextTick();expect(root.querySelector('[aria-label="编辑投票"]')).toBeNull();
});

it('fetches fresh unread counts on explicit refresh and throttles passive visibility changes',async()=>{
 const visibility=vi.spyOn(document,'hidden','get').mockReturnValue(false);
 const previous=bridge.execute.getMockImplementation()!;
 let reads=0;
 bridge.execute.mockImplementation((...args)=>{
  if(args[0]==='notifications.unread'){
   reads++;
   return Promise.resolve({unreadCount:reads===1?0:2,messageUnreadCount:0});
  }
  return previous(...args);
 });
 try{
  await mount();
  await wait(()=>reads===1);
  document.dispatchEvent(new Event('visibilitychange'));
  await nextTick();
  expect(reads).toBe(1);
  button('刷新树洞').click();
  await wait(()=>root.querySelector('.th-unread-badge')?.textContent==='2');
  expect(reads).toBe(2);
 }finally{visibility.mockRestore();}
});

it('shows the empty discussion for legacy pages containing only deleted root comments',async()=>{
 const post=(await call(a,'posts.create',{body:'空讨论',anonymous:false,requestId:crypto.randomUUID()})).post;
 const previous=bridge.execute.getMockImplementation()!;
 bridge.execute.mockImplementation(async(action,body)=>{
  const result=await previous(action,body);
  if(action!=='posts.get')return result;
  const tombstone={postId:post.id,deleted:true,body:'这条评论已删除',author:{name:'已删除'},replyCount:0,replies:[]};
  return {...result,comments:[{...tombstone,id:'one'},{...tombstone,id:'two'}],next:{afterId:'two'}};
 });
 await mount();
 button('查看评论，共 0 条').click();
 await wait(()=>!!root.querySelector('.th-no-comments'));
 expect(root.querySelector('.th-discussion-title h2')?.textContent).toContain('0');
 expect(root.querySelectorAll('.th-comment')).toHaveLength(0);
 expect(root.textContent).not.toContain('这条评论已删除');
 expect(button('加载更多评论')).toBeUndefined();
});

it('keeps live replies to a deleted root readable through preview and legacy reply pagination',async()=>{
 const post=(await call(a,'posts.create',{body:'保留讨论',anonymous:false,requestId:crypto.randomUUID()})).post;
 const comment=async(body:string,replyTo?:string)=>(await call(b,'comments.create',{postId:post.id,body,anonymous:false,replyTo,requestId:crypto.randomUUID()})).comment;
 const parent=await comment('原评论');
 await comment('仍可阅读的回复',parent.id);
 await call(b,'comments.delete',{postId:post.id,commentId:parent.id});
 const previous=bridge.execute.getMockImplementation()!;
 bridge.execute.mockImplementation(async(action,body)=>{
  const result=await previous(action,body);
  if(action!=='comments.replies')return result;
  return {...result,comments:[{...parent,id:'old',deleted:true,body:'这条评论已删除'},...result.comments]};
 });
 await mount();
 button('查看评论，共 1 条').click();
 await wait(()=>root.querySelector('.th-nested-body')?.textContent==='仍可阅读的回复');
 expect(root.querySelector('.th-comment header')).toBeNull();
 button('全部 1 条回复').click();
 await wait(()=>!!button('收起回复'));
 expect(root.querySelectorAll('.th-nested-reply')).toHaveLength(1);
 expect(root.querySelector('.th-comments')?.textContent).not.toContain('已删除');
});
