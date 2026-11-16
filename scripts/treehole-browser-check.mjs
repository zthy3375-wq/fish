/** Actual PostgreSQL + HTTP + UI integration; only the native bridge/storage is adapted. */
import {createServer as staticServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {chromium} from 'playwright';
import {createCommunity} from '../cloudbase/functions/community/core.mjs';
import {createServer} from '../cloudbase/functions/community/server.mjs';

const root=path.resolve('dist'),output='/tmp/handan-community-v12-qa';await mkdir(output,{recursive:true});
const db=new PGlite();await db.exec(await readFile('cloudbase/community-schema.sql','utf8'));
const objects=new Map();let mediaOrigin='';
const storage={put:async(k,v)=>objects.set(k,v),url:async k=>mediaOrigin+'/fixtures/'+k,remove:async k=>objects.delete(k)};
const fixture=await readFile('public/art/campus-autumn.webp');
const api=createCommunity({registrationEnabled:true,storage,db:async(a,b,t)=>(await db.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t])).rows[0].result});
const backend=createServer(api);await new Promise(r=>backend.listen(0,'127.0.0.1',r));
const endpoint=`http://127.0.0.1:${backend.address().port}`;
const server=staticServer(async(req,res)=>{try{
 const name=new URL(req.url,'http://localhost').pathname;
 if(name.startsWith('/fixtures/')){const bytes=objects.get(name.slice('/fixtures/'.length));if(!bytes)throw Error();res.setHeader('Content-Type','image/jpeg');res.end(bytes);return;}
 const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));
 if(!file.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.webp':'image/webp'})[path.extname(file)]||'application/octet-stream');res.end(await readFile(file));
}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));mediaOrigin=`http://127.0.0.1:${server.address().port}`;const url=mediaOrigin+'/#/community';
const browser=await chromium.launch({args:['--no-sandbox'],executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||undefined});
const checks=[];let active;
async function client(width){
 const context=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});
 const state={token:null,dropNextPost:false,failNextReaction:false,releaseReaction:null,breakNextImage:false,delayImage:false,publicResponses:[],actions:[],requests:[],holdNextPage:false,releasePage:null,failNextPage:false,holdNextDetail:false,releaseDetail:null,failNextDetail:false};
 await context.exposeBinding('__treeholeNative',async(_,options)=>{
  const {action,body}=options;if(action==='buddies.join'&&state.failBuddy){state.failBuddy=false;return {error:'network_unavailable'};}if(action==='polls.vote'&&state.failVote){state.failVote=false;return {error:'network_unavailable'};}if(action==='media.upload'&&body?.purpose==='comment'&&state.failCommentUpload){state.failCommentUpload=false;return {error:'network_unavailable'};}if(action==='follows.set'&&state.failFollow){state.failFollow=false;return {error:'network_unavailable'};}if(action==='follows.list'&&state.failFollowList){state.failFollowList=false;return {error:'network_unavailable'};}if(action==='posts.list'&&!body?.beforeId&&state.failNextFeed){state.failNextFeed=false;return {error:'network_unavailable'};}if(action==='notifications.unread'&&state.expireUnread){state.expireUnread=false;return {error:'session_expired'};}if(action==='media.upload'&&state.failAvatarUpload){state.failAvatarUpload=false;return {error:'network_unavailable'};}if(action==='responses.set'&&state.failResponse){state.failResponse=false;return {error:'network_unavailable'};}state.actions.push(action);state.requests.push({action,body});if(action==='posts.get'&&state.failNextDetail){state.failNextDetail=false;return {error:'network_unavailable'};}if(action==='posts.list'&&body?.beforeId&&state.failNextPage){state.failNextPage=false;return {error:'network_unavailable'};}if(action==='reactions.set'&&state.failNextReaction){state.failNextReaction=false;await new Promise(resolve=>state.releaseReaction=resolve);return {error:'network_unavailable'};}const headers={'Content-Type':'application/json'};
  if(state.token)headers.Authorization='Bearer '+state.token;
  const result=await fetch(endpoint+'/v1/'+action,{method:action==='config'?'GET':'POST',headers,...(action==='config'?{}:{body:JSON.stringify(body)})});
  const json=await result.json();if(action==='buddies.join'&&state.holdBuddy){state.holdBuddy=false;await new Promise(resolve=>state.releaseBuddy=resolve);}if(action==='buddies.join'&&state.dropBuddy){state.dropBuddy=false;return {error:'network_unavailable'};}if(action==='follows.set'&&state.holdFollow){state.holdFollow=false;await new Promise(resolve=>state.releaseFollow=resolve);}if(action==='avatar.set'&&state.holdAvatarSet){state.holdAvatarSet=false;await new Promise(resolve=>state.releaseAvatarSet=resolve);}if(action==='config'&&state.legacyConfig){delete json.avatarsEnabled;delete json.responsesEnabled;delete json.discoveryEnabled;delete json.followingEnabled;delete json.buddiesEnabled;delete json.pollsEnabled;delete json.commentImagesEnabled;}if(action==='posts.get'&&state.holdNextDetail){state.holdNextDetail=false;await new Promise(resolve=>state.releaseDetail=resolve);}if(action==='posts.list'&&body?.beforeId&&state.holdNextPage){state.holdNextPage=false;await new Promise(resolve=>state.releasePage=resolve);}if(!result.ok)return {error:json.error};
  if(json.sessionToken){state.token=json.sessionToken;delete json.sessionToken;}
  if(action==='logout'||action==='account.delete')state.token=null;
  if(action.startsWith('posts.')||action.startsWith('comments.'))state.publicResponses.push(json);
  if(action==='media.url'&&state.breakNextImage){state.breakNextImage=false;json.image.url=mediaOrigin+'/fixtures/expired-image';}
  else if(action==='media.url'&&state.delayImage)await new Promise(r=>setTimeout(r,180));
  if(action==='avatar.set'&&state.dropAvatarSet){state.dropAvatarSet=false;return {error:'network_unavailable'};}
  if(action==='posts.create'&&state.dropNextPost){state.dropNextPost=false;return {error:'network_unavailable'};}
  if(action==='comments.create'&&state.dropComment){state.dropComment=false;return {error:'network_unavailable'};}
  return {result:json};
 });
 await context.addInitScript(()=>{
  const methods={Treehole:['request'],Preferences:['get','set','remove'],App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
  window.androidBridge={};window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:'promise'}))})),nativePromise:async(plugin,method,args)=>{
   if(plugin==='Treehole'){const value=await window.__treeholeNative(args);if(value.error)throw Error(value.error);return value.result;}
   if(plugin==='Preferences'){if(method==='get')return {value:localStorage.getItem(args.key)};if(method==='set')localStorage.setItem(args.key,args.value);if(method==='remove')localStorage.removeItem(args.key);}
   if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};return {};
  }};
 });
 const page=await context.newPage();page.setDefaultTimeout(15000);const errors=[];page.on('pageerror',e=>errors.push(e.message));active=page;
 await page.goto(url);await page.getByRole('heading',{name:'说说校园里的那些事'}).waitFor();
 return {page,context,state,errors};
}
async function register(page,username,nickname){
 await page.getByRole('button',{name:'注册账号',exact:true}).click();
 await page.getByLabel('登录账号',{exact:true}).fill(username);await page.getByLabel('公开昵称',{exact:true}).fill(nickname);
 await page.getByLabel('密码',{exact:true}).fill('synthetic-long-password');await page.getByRole('checkbox',{name:/我已阅读/}).check();
 await page.getByRole('button',{name:'创建账号',exact:true}).click();await page.getByRole('heading',{name:'保存你的账号恢复码'}).waitFor();
 await page.getByRole('button',{name:'我已保存恢复码'}).click();await page.getByRole('heading',{name:'邯院社区',exact:true}).waitFor();
}
try{
 if(!process.env.HYT_POLLS_ONLY&&!process.env.HYT_BUDDIES_ONLY){
 for(const width of [360,390,430]){
  const a=await client(width);
  await a.page.screenshot({path:path.join(output,`treehole-login-${width}.png`),animations:'disabled'});
  const beforePostCount=(await db.query('SELECT count(*)::int AS n FROM hyt_posts')).rows[0].n;
  await register(a.page,'author_'+width,'测试同学甲');
  const nav=a.page.getByRole('navigation',{name:'主导航'});
  assert.deepEqual(await nav.getByRole('button').allTextContents(),['首页','课表','社区','待办','我的']);
  assert.equal(await nav.getByRole('button',{name:'社区',exact:true}).getAttribute('aria-current'),'page');
  const slots=await nav.getByRole('button').evaluateAll(els=>els.map(el=>el.getBoundingClientRect().width));assert(slots.every(w=>w>=44));
  const rows=await nav.getByRole('button').evaluateAll(els=>els.map(el=>el.getBoundingClientRect().y));assert(rows.every(y=>Math.abs(y-rows[0])<1));
  await a.page.waitForTimeout(400);const indicator=await nav.locator('.nav-indicator').boundingBox(),middle=await nav.getByRole('button',{name:'社区',exact:true}).boundingBox();assert(Math.abs(indicator.x+indicator.width/2-middle.x-middle.width/2)<2);
  const fab=await a.page.getByRole('button',{name:'发帖',exact:true}).boundingBox(),dock=await nav.boundingBox();assert(fab.y+fab.height<dock.y);
  checks.push(`${width}: treehole is the middle tab, all five targets fit and composer clears the dock`);
  await a.page.getByRole('button',{name:'发帖',exact:true}).click();await a.page.getByLabel('想说的话').fill('今天图书馆靠窗的位置很安静。下课后，给自己一点慢下来的时间。');
  assert.equal(await nav.count(),0);checks.push(`${width}: composing hides main navigation to protect the draft`);
  await a.page.getByLabel('帖子标题').fill('图书馆的午后');await a.page.getByLabel('选择分区').selectOption('study');await a.page.getByLabel('添加图片').setInputFiles({name:'campus-fixture.webp',mimeType:'image/webp',buffer:fixture});await a.page.locator('.th-draft-images img').waitFor();
  await a.page.getByRole('checkbox',{name:'匿名发布',exact:true}).check();await a.page.screenshot({path:path.join(output,`treehole-compose-${width}.png`),animations:'disabled'});a.state.dropNextPost=true;
  await a.page.getByRole('button',{name:'匿名发布',exact:true}).click();await a.page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();
  assert.equal(await a.page.getByLabel('想说的话').inputValue(),'今天图书馆靠窗的位置很安静。下课后，给自己一点慢下来的时间。');
  await a.page.getByRole('button',{name:'匿名发布',exact:true}).click();await a.page.getByRole('heading',{name:'评论',exact:true}).waitFor();
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_posts')).rows[0].n,beforePostCount+1);
  checks.push(`${width}: lost response preserves image draft and retry creates one post`);
  assert.equal(await a.page.locator('.th-detail h2').innerText(),'图书馆的午后');assert.equal(a.state.actions.filter(x=>x==='media.upload').length,1);
  await a.page.getByRole('button',{name:'查看图片 1，共 1 张'}).click();await a.page.getByRole('dialog').waitFor();assert(await a.page.locator('.th-gallery img').evaluate(i=>i.complete&&i.naturalWidth>0));await a.page.getByRole('button',{name:'关闭大图'}).click();checks.push(`${width}: image upload, section, title and full-screen viewer work`);
  assert.equal(await a.page.getByLabel('你的回复',{exact:true}).count(),0);assert((await a.page.locator('.th-readbar').boundingBox()).height<80);
  await a.page.locator('.th-reply-entry').click();
  const locked=a.page.getByRole('checkbox',{name:'保持楼主匿名身份'});assert(await locked.isChecked());assert(await locked.isDisabled());
  await a.page.getByLabel('你的回复',{exact:true}).fill('这是楼主自己的回复。');await a.page.getByRole('button',{name:'发布回复',exact:true}).click();await a.page.getByText('这是楼主自己的回复。',{exact:true}).waitFor();
  assert.equal(await a.page.locator('.th-comment strong em').first().innerText(),'楼主');checks.push(`${width}: anonymous author replies retain alias`);
  await a.page.screenshot({path:path.join(output,`treehole-detail-${width}.png`),animations:'disabled'});
  await a.page.setViewportSize({width,height:400});await a.page.locator('.th-reply-entry').click();await a.page.getByLabel('你的回复',{exact:true}).focus();
  await a.page.waitForFunction(()=>!document.querySelector('.th-sheet-motion-enter-active'));
  const replyBounds=await a.page.locator('.th-reply-box').boundingBox();const sendBounds=await a.page.getByRole('button',{name:'发布回复',exact:true}).boundingBox();
  assert(replyBounds.y>=0&&replyBounds.y+replyBounds.height<=401);assert(sendBounds.y>=0&&sendBounds.y+sendBounds.height<=401);
  await a.page.getByRole('button',{name:'收起回复编辑器'}).click();await a.page.locator('.th-dialog').waitFor({state:'detached'});await a.page.setViewportSize({width,height:844});checks.push(`${width}: reply controls remain visible in keyboard-sized viewport`);

  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.getByRole('heading',{name:'邯院社区',exact:true}).waitFor();
  await a.page.screenshot({path:path.join(output,`treehole-feed-${width}.png`),animations:'disabled'});
  assert.equal(await a.page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);checks.push(`${width}: compact feed has no horizontal overflow`);
  const b=await client(width);await register(b.page,'reader_'+width,'测试同学乙');
  await b.page.locator('.th-post-body').first().click();await b.page.getByRole('heading',{name:'评论',exact:true}).waitFor();
  await b.page.locator('.th-comment-loading').waitFor({state:'hidden'});const viewer=b.state.publicResponses.at(-1);assert(!JSON.stringify(viewer).includes('测试同学甲'));assert(!JSON.stringify(viewer).includes('author_'+width));
  await b.page.locator('.th-reply-entry').click();
  assert.equal(await b.page.getByRole('checkbox',{name:'匿名回复',exact:true}).isDisabled(),false);checks.push(`${width}: second account sees anonymous projections without account identity`);
  await b.page.getByLabel('你的回复',{exact:true}).fill('今天也要好好休息呀。');await b.page.getByRole('button',{name:'发布回复',exact:true}).click();await b.page.getByText('今天也要好好休息呀。',{exact:true}).waitFor();
  await b.page.locator('.th-comment').first().getByRole('button',{name:'回复',exact:true}).click();
  await b.page.getByLabel('你的回复',{exact:true}).fill('回复楼主：下次也去靠窗坐坐。');await b.page.getByRole('button',{name:'发布回复',exact:true}).click();
  await b.page.locator('.th-nested-reply').filter({hasText:'回复楼主：下次也去靠窗坐坐。'}).waitFor();
  assert(!await b.page.locator('.th-comment').first().innerText().then(t=>t.includes('测试同学甲')));checks.push(`${width}: replies stay grouped beneath anonymous root comment`);
  await b.page.locator('.th-comment').first().getByRole('button',{name:'点赞评论',exact:true}).first().click();await b.page.getByRole('button',{name:'取消评论点赞',exact:true}).waitFor();
  await b.page.getByRole('button',{name:'全部 1 条回复',exact:true}).click();await b.page.locator('.th-nested-reply').first().waitFor();checks.push(`${width}: comment likes and reply expansion use committed server state`);
  await b.page.getByRole('button',{name:'收起回复',exact:true}).click();assert.equal(await b.page.getByRole('button',{name:'全部 1 条回复',exact:true}).count(),1);const loaded=b.state.actions.filter(x=>x==='comments.replies').length;await b.page.getByRole('button',{name:'全部 1 条回复',exact:true}).click();assert.equal(b.state.actions.filter(x=>x==='comments.replies').length,loaded);checks.push(`${width}: collapsed threads reopen from loaded replies`);
  b.state.failNextReaction=true;await b.page.getByRole('button',{name:'点赞',exact:true}).click();await b.page.getByRole('button',{name:'取消点赞',exact:true}).waitFor();assert(await b.page.getByRole('button',{name:'取消点赞',exact:true}).isDisabled());assert(!await b.page.getByRole('button',{name:'帖子操作'}).isDisabled());assert(!await b.page.getByRole('button',{name:'收藏',exact:true}).isDisabled());
  await b.page.waitForFunction(()=>true);while(!b.state.releaseReaction)await new Promise(r=>setTimeout(r,10));b.state.releaseReaction();await b.page.getByRole('button',{name:'点赞',exact:true}).waitFor();await b.page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();checks.push(`${width}: failed optimistic like rolls back without freezing reading or saving`);
  await b.page.locator('.th-reply-entry').click();await b.page.getByLabel('你的回复',{exact:true}).fill('暂存的回复');await b.page.getByRole('button',{name:'收起回复编辑器'}).click();await b.page.locator('.th-dialog').waitFor({state:'detached'});assert.equal(await b.page.getByLabel('你的回复',{exact:true}).count(),0);await b.page.locator('.th-reply-entry').click();assert.equal(await b.page.getByLabel('你的回复',{exact:true}).inputValue(),'暂存的回复');await b.page.getByLabel('你的回复',{exact:true}).fill('');await b.page.getByRole('button',{name:'收起回复编辑器'}).click();await b.page.locator('.th-dialog').waitFor({state:'detached'});checks.push(`${width}: compact read bar opens editor and preserves text when folded`);
  await b.page.getByRole('button',{name:'点赞',exact:true}).click();await b.page.getByRole('button',{name:'取消点赞',exact:true}).waitFor();
  await b.page.getByRole('button',{name:'收藏',exact:true}).click();await b.page.getByRole('button',{name:'取消收藏',exact:true}).waitFor();checks.push(`${width}: reactions show committed server state`);
  await b.page.getByRole('button',{name:'帖子操作'}).click();
  for(let i=0;i<5;i++){await b.page.keyboard.press('Tab');assert(await b.page.evaluate(()=>!!document.activeElement?.closest('[role=dialog]')));}
  await b.page.keyboard.press('Escape');await b.page.locator('.th-dialog').waitFor({state:'detached'});assert.equal(await b.page.getByRole('dialog').count(),0);assert.equal(await b.page.getByRole('button',{name:'帖子操作'}).evaluate(e=>e===document.activeElement),true);
  checks.push(`${width}: action sheet traps focus and restores the trigger`);
  await b.page.getByRole('button',{name:'帖子操作'}).click();await b.page.getByRole('button',{name:'举报',exact:true}).click();
  await b.page.getByLabel('原因',{exact:true}).fill('人工测试举报');await b.page.getByRole('button',{name:'提交举报',exact:true}).click();await b.page.getByText('举报已提交，管理员会查看处理',{exact:true}).waitFor();checks.push(`${width}: named comments and reporting work across accounts`);
  active=a.page;
  await a.page.getByRole('button',{name:'刷新树洞',exact:true}).click();await a.page.locator('.th-unread-badge').waitFor();
  await a.page.getByRole('button',{name:'互动消息',exact:true}).click();await a.page.locator('.th-inbox-item').first().waitFor();
  assert.equal(await a.page.getByRole('navigation',{name:'主导航'}).count(),0);
  await a.page.getByRole('navigation',{name:'互动消息筛选'}).getByRole('button',{name:'回复与招募',exact:true}).click();
  const notification=a.page.locator('.th-inbox-item').filter({hasText:'回复楼主：下次也去靠窗坐坐。'});await notification.waitFor();
  const noticeId=await notification.getAttribute('data-notification-id');
  await a.page.screenshot({path:path.join(output,`community-inbox-${width}.png`),animations:'disabled'});
  await notification.click();await a.page.getByLabel('消息对应的回复',{exact:true}).waitFor();
  assert((await a.page.locator('.th-focus-context').innerText()).includes('回复楼主：下次也去靠窗坐坐。'));
  assert(!await a.page.locator('.th-focus-context').innerText().then(t=>t.includes('测试同学甲')));
  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.locator('.th-inbox-item').first().waitFor();
  assert(!await a.page.locator(`[data-notification-id="${noticeId}"]`).getAttribute('class').then(t=>t.includes('is-unread')));
  await a.page.getByRole('navigation',{name:'互动消息筛选'}).getByRole('button',{name:'赞与回应',exact:true}).click();await a.page.locator('.th-inbox-item').first().waitFor();
  assert((await a.page.locator('.th-inbox-item').allTextContents()).every(t=>t.includes('一位同学')));
  await a.page.getByRole('button',{name:'将当前消息标为已读',exact:true}).click();await a.page.waitForFunction(()=>!document.querySelector('.th-inbox-item.is-unread'));
  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.locator('.th-return-links').getByRole('button',{name:'我参与的',exact:true}).click();await a.page.locator('.th-post').first().waitFor();
  assert.equal(await a.page.locator('.th-scope strong').innerText(),'我参与的');
  await a.page.locator('.th-return-links').getByRole('button',{name:'广场',exact:true}).click();await a.page.locator('.th-post').first().waitFor();
  checks.push(`${width}: reply/like inbox, anonymous previews, nested notification context, read state and return to inbox work`);
  active=b.page;
  await b.page.getByRole('button',{name:'取消关注',exact:true}).click();await b.page.getByRole('button',{name:'关注讨论',exact:true}).waitFor();
  await b.page.getByRole('button',{name:'关注讨论',exact:true}).click();await b.page.getByRole('button',{name:'取消关注',exact:true}).waitFor();
  checks.push(`${width}: discussion follow toggle reflects committed state`);
  await b.page.getByRole('button',{name:'返回社区',exact:true}).click();await b.page.getByRole('button',{name:'测试同学乙',exact:true}).click();await b.page.getByRole('button',{name:/我的收藏/}).click();await b.page.locator('.th-post-body').first().waitFor();
  assert.equal(await b.page.locator('.th-post').count(),1);
  await b.page.getByRole('button',{name:'搜索帖子',exact:true}).click();await b.page.getByLabel('搜索树洞文字').fill('这个关键词没有帖子');await b.page.getByRole('button',{name:'搜索',exact:true}).click();await b.page.getByRole('heading',{name:'还没找到这段回声'}).waitFor();
  await b.page.getByRole('button',{name:'清除搜索',exact:true}).click();await b.page.locator('.th-post-body').first().waitFor();checks.push(`${width}: saved feed and search preserve scope`);
  await b.page.getByLabel('帖子分区').getByRole('button',{name:'校园日常',exact:true}).click();await b.page.getByRole('group',{name:'校园内容筛选'}).getByRole('button',{name:'提问求助',exact:true}).click();await b.page.getByRole('heading',{name:'这里，等你说第一句话'}).waitFor();await b.page.getByRole('group',{name:'校园内容筛选'}).getByRole('button',{name:'学习交流',exact:true}).click();await b.page.locator('.th-post-body').first().waitFor();checks.push(`${width}: section filtering excludes unrelated posts`);
  const previousRefresh=b.state.actions.filter(x=>x==='posts.list').length;
  await b.page.evaluate(()=>{window.scrollTo(0,0);const target=document.querySelector('.th-feed-intro');for(const [type,y] of [['touchstart',120],['touchend',260]]){const event=new Event(type,{bubbles:true});Object.defineProperty(event,'changedTouches',{value:[{clientY:y}]});target.dispatchEvent(event);}});
  await b.page.getByText('帖子已刷新',{exact:true}).waitFor();assert.equal(b.state.actions.filter(x=>x==='posts.list').length,previousRefresh+1);checks.push(`${width}: pull gesture refreshes community posts`);
  await b.page.getByRole('button',{name:'测试同学乙',exact:true}).click();
  await b.page.screenshot({path:path.join(output,`treehole-account-${width}.png`),animations:'disabled'});
  await b.page.getByRole('button',{name:'退出邯院通账号',exact:true}).click();await b.page.getByRole('button',{name:'确认',exact:true}).click();await b.page.getByRole('heading',{name:'说说校园里的那些事'}).waitFor();
  assert.equal(b.state.token,null);assert.equal(await b.page.locator('.th-post').count(),0);checks.push(`${width}: logout clears content and session`);
  await a.page.getByRole('button',{name:'发帖',exact:true}).click();await a.page.getByLabel('想说的话').fill('还没写完的草稿');await a.page.getByRole('button',{name:'返回社区',exact:true}).click();
  await a.page.getByRole('heading',{name:'放弃还没发布的文字？'}).waitFor();await a.page.getByRole('button',{name:'继续编辑',exact:true}).click();assert.equal(await a.page.getByLabel('想说的话').inputValue(),'还没写完的草稿');checks.push(`${width}: back navigation protects unpublished text`);
  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.getByRole('button',{name:'保存草稿并返回',exact:true}).click();await a.page.getByRole('heading',{name:'邯院社区',exact:true}).waitFor();
  active=a.page;await a.page.reload();await a.page.locator('.th-draft-resume').waitFor();await a.page.locator('.th-draft-resume').click();assert.equal(await a.page.getByLabel('想说的话').inputValue(),'还没写完的草稿');checks.push(`${width}: account draft survives page recreation`);
  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.getByRole('button',{name:'放弃并返回',exact:true}).click();
  await a.page.locator('.th-post-body').first().click();await a.page.locator('.th-comment').first().getByRole('button',{name:'回复',exact:true}).click();
  await a.page.getByRole('button',{name:'收起回复编辑器'}).click();await a.page.locator('.th-dialog').waitFor({state:'detached'});await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.getByRole('button',{name:'发帖',exact:true}).click();
  await a.page.getByLabel('想说的话').fill('第二条树洞，开始一段新的讨论。');await a.page.getByRole('button',{name:'以昵称发布',exact:true}).click();await a.page.getByRole('heading',{name:'评论',exact:true}).waitFor();
  assert.equal(await a.page.locator('.th-reply-target').count(),0,'A new discussion must not inherit the previous reply target');
  await a.page.locator('.th-reply-entry').click();await a.page.getByLabel('你的回复',{exact:true}).fill('新讨论里的第一条回复。');await a.page.getByRole('button',{name:'发布回复',exact:true}).click();await a.page.getByText('新讨论里的第一条回复。',{exact:true}).waitFor();
  checks.push(`${width}: new post resets the previous discussion reply target`);
  await a.page.getByRole('button',{name:'查看 测试同学甲 的主页',exact:true}).click();await a.page.locator('.th-public-profile').waitFor();
  assert.equal(await a.page.locator('.th-post').count(),1);assert(!(await a.page.locator('.th-post').innerText()).includes('图书馆的午后'));
  await a.page.screenshot({path:path.join(output,`community-profile-${width}.png`),animations:'disabled'});
  await a.page.locator('.th-post-body').click();await a.page.locator('.th-detail').waitFor();
  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.locator('.th-public-profile').waitFor();
  await a.page.getByRole('button',{name:'返回社区',exact:true}).click();await a.page.locator('.th-detail').waitFor();
  checks.push(`${width}: named avatar opens profile, anonymous posts stay private, nested back restores each page`);

  assert.deepEqual(a.errors,[]);assert.deepEqual(b.errors,[]);
  await a.context.close();await b.context.close();console.log(`account/read regressions ${width}: ${checks.length} checks`);
 }

 // Representative local-only content: no seed data is sent to the live community.
 const visual=await client(390);await register(visual.page,'visual_reader','校园观察员');
 const call=async(action,body={})=>{const r=await visual.page.evaluate(async({action,body})=>window.__treeholeNative({action,body}),{action,body});assert(!r.error,`${action}: ${r.error}`);return r.result;};
 const campusJPEG=Array.from(objects.values())[0].toString('base64');
 const noticeJPEG=await visual.page.evaluate(()=>{
  const canvas=document.createElement('canvas');canvas.width=480;canvas.height=1600;const ctx=canvas.getContext('2d');ctx.fillStyle='#f3f4f6';ctx.fillRect(0,0,480,1600);ctx.fillStyle='#26343d';ctx.fillRect(0,0,480,170);ctx.fillStyle='#fff';ctx.font='bold 30px sans-serif';ctx.fillText('校园周末活动清单',30,70);ctx.font='18px sans-serif';ctx.fillText('仅用于本地界面测试',30,112);
  for(let i=0;i<7;i++){const y=205+i*190;ctx.fillStyle='#fff';ctx.fillRect(24,y,432,155);ctx.fillStyle='#25343c';ctx.font='bold 22px sans-serif';ctx.fillText(['图书馆阅读','操场慢跑','校园摄影','社团交流','自习与讨论','一起做项目','周末小结'][i],42,y+40);ctx.fillStyle='#879096';ctx.font='17px sans-serif';ctx.fillText('地点与时间，以实际通知为准',42,y+78);ctx.fillStyle='#e9edf0';ctx.fillRect(42,y+106,340,8);}
  return canvas.toDataURL('image/jpeg',.85).split(',')[1];
 });
 async function seed(title,body,category,photos=[]){const ids=[];for(const data of photos){ids.push((await call('media.upload',{data,requestId:crypto.randomUUID()})).image.id);}return (await call('posts.create',{title,body,category,images:ids,anonymous:false,requestId:crypto.randomUUID()})).post;}
 const many=await seed('秋天的校园，想多待一会儿','从图书馆出来，刚好遇见夕阳。照片用的是项目里的校园插画，作为九图显示测试。','daily',Array(9).fill(campusJPEG));
 const long=await seed('周末活动清单：一张长截图','整理了几个校园活动。长图点开可以看完整内容，欢迎补充。','buddies',[noticeJPEG]);
 await seed('想找几位一起做校园项目的同学','想做一个真正能用的小项目，慢慢打磨界面和体验。设计、前端、安卓或者只是有想法的同学，都可以聊聊。\n希望能从身边的小问题开始。','study');
 const two=await seed('两张图也应该排得舒服','同一张校园插画用于测试双图比例。','daily',[campusJPEG,campusJPEG]);
 const roots=[];for(const text of ['长图里的信息很多，竖着看应该完整保留。','评论再长也要有舒服的行距，点赞和回复入口保持清楚。这里加一段足够长的文字，检查小屏幕上换行后会不会挤在一起。']){roots.push((await call('comments.create',{postId:long.id,body:text,anonymous:false,requestId:crypto.randomUUID()})).comment);}
 for(let i=0;i<4;i++)await call('comments.create',{postId:long.id,body:['谢谢整理，周末打算去看看。','想知道有没有一起拍照的同学。','先收藏了，等安排出来再看。','这条回复用来检查展开和收起。'][i],anonymous:i%2===0,requestId:crypto.randomUUID(),replyTo:roots[0].id});
 await visual.page.reload();await visual.page.getByRole('heading',{name:two.title,exact:true}).waitFor();
 for(const width of [360,390,430]){
  await visual.page.setViewportSize({width,height:844});await visual.page.screenshot({path:path.join(output,`treehole-content-feed-${width}.png`),fullPage:true,animations:'disabled'});assert.equal(await visual.page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  const dual=visual.page.locator('.th-post').filter({hasText:two.title});assert.equal(await dual.locator('.th-images.two button').count(),2);
  const nine=visual.page.locator('.th-post').filter({hasText:many.title});assert.equal(await nine.locator('.th-images button').count(),9);
  const tall=visual.page.locator('.th-post').filter({hasText:long.title});assert.equal(await tall.locator('.th-long-image').innerText(),'长图');assert((await tall.locator('.th-images button').boundingBox()).height<=325);
  await tall.getByRole('button',{name:/查看评论/}).click();await visual.page.getByRole('heading',{name:'评论',exact:true}).waitFor();await visual.page.waitForFunction(()=>document.querySelector('.th-discussion-title').getBoundingClientRect().top<120);const full=await visual.page.locator('.th-detail .th-images button').boundingBox();assert(Math.abs(full.width/full.height-.3)<.01);assert.equal(await visual.page.getByLabel('你的回复',{exact:true}).count(),0);
  await visual.page.locator('.th-detail-tabs').getByRole('button',{name:'评论',exact:true}).click();await visual.page.waitForFunction(()=>document.querySelector('.th-discussion-title').getBoundingClientRect().top<120);assert.equal(await visual.page.locator('.th-detail-tabs').getByRole('button',{name:'评论',exact:true}).getAttribute('aria-pressed'),'true');
  await visual.page.locator('.th-comment').first().waitFor();assert.equal(await visual.page.locator('.th-comment').first().locator('.th-nested-reply').count(),2);await visual.page.screenshot({path:path.join(output,`treehole-content-comments-${width}.png`),animations:'disabled'});
  await visual.page.getByRole('button',{name:'全部 4 条回复',exact:true}).click();await visual.page.getByRole('button',{name:'收起回复',exact:true}).waitFor();assert.equal(await visual.page.locator('.th-comment').first().locator('.th-nested-reply').count(),4);await visual.page.getByRole('button',{name:'收起回复',exact:true}).click();assert.equal(await visual.page.locator('.th-comment').first().locator('.th-nested-reply').count(),2);
  await visual.page.locator('.th-reply-entry').click();await visual.page.getByLabel('你的回复',{exact:true}).fill('编辑器展开后再选择匿名，阅读时保留更多空间。');await visual.page.screenshot({path:path.join(output,`treehole-content-editor-${width}.png`),animations:'disabled'});await visual.page.getByLabel('你的回复',{exact:true}).fill('');await visual.page.getByRole('button',{name:'收起回复编辑器'}).click();
  await visual.page.getByRole('button',{name:'返回社区',exact:true}).click();await visual.page.locator('.th-post').filter({hasText:many.title}).locator('.th-post-body').click();await visual.page.getByRole('heading',{name:'评论',exact:true}).waitFor();assert.equal(await visual.page.locator('.carousel button').count(),9);
  await visual.page.locator('.carousel').evaluate(el=>el.scrollTo({left:el.clientWidth*2,behavior:'instant'}));await visual.page.waitForFunction(()=>document.querySelector('.th-media-pagination strong').textContent==='3 / 9');await visual.page.getByRole('button',{name:'查看图片 3，共 9 张',exact:true}).click();await visual.page.getByRole('button',{name:'下一张',exact:true}).click();assert.equal(await visual.page.locator('.th-gallery-bar>span').innerText(),'4 / 9');await visual.page.getByRole('button',{name:'关闭大图'}).click();await visual.page.getByRole('button',{name:'返回社区',exact:true}).click();
  checks.push(`${width}: long image keeps full aspect, two/nine photos, selected comment tab, preview-two/expand-four and carousel/gallery indices`);
 }
 visual.state.breakNextImage=true;await visual.page.locator('.th-post').filter({hasText:two.title}).getByRole('button',{name:'查看配图 1，共 2 张'}).click();assert.equal(await visual.page.locator('.th-detail').count(),0);await visual.page.getByRole('button',{name:'图片暂未加载，点击重试',exact:true}).waitFor();visual.state.delayImage=true;await visual.page.getByRole('button',{name:'图片暂未加载，点击重试',exact:true}).click();await visual.page.locator('.th-gallery img').waitFor();await visual.page.waitForFunction(()=>{const image=document.querySelector('.th-gallery img');return image&&image.complete&&image.naturalWidth>0;});await visual.page.getByRole('button',{name:'关闭大图'}).click();checks.push('expired gallery URL recovers on the first retry even when the old image fails during URL renewal');
 await db.query('UPDATE hyt_posts SET locked=true WHERE id=$1',[long.id]);await visual.page.locator('.th-post').filter({hasText:long.title}).locator('.th-post-body').click();await visual.page.getByText('这条讨论已暂停回复。',{exact:true}).waitFor();assert(await visual.page.locator('.th-reply-entry').isDisabled());assert(!await visual.page.getByRole('button',{name:'点赞',exact:true}).isDisabled());await visual.page.getByRole('button',{name:'收藏',exact:true}).click();await visual.page.getByRole('button',{name:'取消收藏',exact:true}).waitFor();checks.push('locked discussion keeps like/save controls while disabling reply entry');

 await visual.page.getByRole('button',{name:'返回社区',exact:true}).click();
 const vp=visual.page;
 const visibleCard=()=>vp.locator('.th-post').filter({hasText:two.title});
 async function backToCards(){await vp.getByRole('button',{name:'返回社区',exact:true}).click();await visibleCard().waitFor();await vp.waitForTimeout(260);}
 for(const region of ['padding','footer']){
  await visibleCard().scrollIntoViewIfNeeded();await vp.waitForTimeout(260);visual.state.holdNextDetail=true;
  const box=await visibleCard().boundingBox();
  if(region==='image')await visibleCard().locator('.th-images button').first().click();
  else {const point=region==='author'?await visibleCard().locator('.th-post-byline').boundingBox():region==='footer'?await visibleCard().locator('.th-action-spacer').boundingBox():{x:box.x+2,y:box.y+60,width:8,height:8};await vp.mouse.click(point.x+point.width/2,point.y+point.height/2);}
  await vp.locator('.th-detail').waitFor();await vp.locator('.th-comment-loading').waitFor();
  assert.equal(await vp.locator('.th-detail h2').innerText(),two.title);assert(!await vp.getByRole('button',{name:'返回社区',exact:true}).isDisabled());assert.equal(await vp.getByRole('dialog').count(),0);
  while(!visual.state.releaseDetail)await new Promise(r=>setTimeout(r,10));
  await backToCards();visual.state.releaseDetail();visual.state.releaseDetail=null;await vp.waitForTimeout(100);assert.equal(await vp.locator('.th-detail').count(),0);
  checks.push(`hit ${region}: immediate cached detail, nonblocking loading, back discards delayed response`);
 }
 // Child controls must not bubble into navigation.
 await visibleCard().getByRole('button',{name:'点赞',exact:true}).click();await visibleCard().getByRole('button',{name:'取消点赞',exact:true}).waitFor();assert.equal(await vp.locator('.th-detail').count(),0);
 await visibleCard().getByRole('button',{name:'帖子操作',exact:true}).click();await vp.getByRole('heading',{name:'帖子操作',exact:true}).waitFor();assert.equal(await vp.locator('.th-detail').count(),0);await vp.getByRole('button',{name:'取消',exact:true}).click();
 checks.push('like and more controls remain isolated from card navigation');
 // Drag and long press generate no accidental click navigation.
 await visibleCard().scrollIntoViewIfNeeded();const rect=await visibleCard().boundingBox();
 await vp.mouse.move(rect.x+7,rect.y+70);await vp.mouse.down();await vp.mouse.move(rect.x+7,rect.y+110,{steps:6});await vp.mouse.up();assert.equal(await vp.locator('.th-detail').count(),0);
 await vp.mouse.move(rect.x+7,rect.y+70);await vp.mouse.down();await vp.waitForTimeout(650);await vp.mouse.up();assert.equal(await vp.locator('.th-detail').count(),0);
 checks.push('movement and long press suppress accidental card activation');
 visual.state.failNextDetail=true;await visibleCard().locator('.th-post-body').click();await vp.locator('.th-detail-error').waitFor();assert.equal(await vp.locator('.th-detail h2').innerText(),two.title);await vp.locator('.th-detail-error').getByRole('button',{name:'重试',exact:true}).click();await vp.locator('.th-detail-error').waitFor({state:'hidden'});await vp.locator('.th-comment-loading').waitFor({state:'hidden'});checks.push('detail failure retains cached body and inline retry recovers');await backToCards();
 await vp.emulateMedia({reducedMotion:'reduce'});await visibleCard().locator('.th-post-body').focus();await vp.keyboard.press('Enter');await vp.locator('.th-detail').waitFor();assert.equal(await vp.locator('.th-screen-panel').evaluate(el=>getComputedStyle(el).animationName),'none');checks.push('keyboard opens detail and reduced motion disables page animation');await backToCards();await vp.emulateMedia({reducedMotion:'no-preference'});
 await vp.evaluate(()=>document.documentElement.style.fontSize='22px');assert.equal(await vp.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await vp.evaluate(()=>document.documentElement.style.fontSize='');checks.push('large text retains single-column reading without horizontal overflow');
 assert.deepEqual(visual.errors,[]);await visual.context.close();

 // Forty-five deterministic SQL fixtures exercise real cursor paging without rate-limit bypass in product code.
 for(const width of [360,390,430]){
  const pager=await client(width);await register(pager.page,'pager_'+width,'翻页测试同学');
  const member=(await db.query('SELECT id FROM hyt_members WHERE username=$1',['pager_'+width])).rows[0].id;
  const keyword='分页样本'+width;
  await db.query(`INSERT INTO hyt_posts(author_id,body,anonymous,request_id,title,category,created_at)
    SELECT $1,'校园图书馆的午后，记录一件普通的小事。',false,gen_random_uuid(),$2||' · '||lpad(n::text,2,'0'),'daily',now()-n*interval '1 minute' FROM generate_series(1,45) AS n`,[member,keyword]);
  const page=pager.page,card=()=>page.locator('.th-post'),pageCalls=()=>pager.state.requests.filter(r=>r.action==='posts.list'&&r.body?.beforeId),firstCalls=()=>pager.state.requests.filter(r=>r.action==='posts.list'&&!r.body?.beforeId).length;
  const count=async n=>page.waitForFunction(n=>document.querySelectorAll('.th-post').length===n,n);
  await page.getByRole('button',{name:'搜索帖子',exact:true}).click();await page.getByLabel('搜索树洞文字').fill(keyword);await page.locator('.th-search').getByRole('button',{name:'搜索',exact:true}).click();await count(20);
  pager.state.holdNextPage=true;await page.locator('.th-page-end').scrollIntoViewIfNeeded();await page.getByText('正在加载更多帖子…',{exact:true}).waitFor();
  assert.equal(pageCalls().length,1);assert.equal(await page.getByRole('button',{name:'发帖',exact:true}).isDisabled(),false);assert.equal(await card().first().locator('.th-post-body').isDisabled(),false);
  while(!pager.state.releasePage)await new Promise(r=>setTimeout(r,10));pager.state.releasePage();pager.state.releasePage=null;await count(40);
  assert.equal(pageCalls().length,1);const snapshot=pageCalls()[0].body.snapshotTime;assert(snapshot);checks.push(`${width}: near-bottom loads page two once, keeps snapshot and leaves reading enabled`);
  pager.state.failNextPage=true;await page.locator('.th-page-end').scrollIntoViewIfNeeded();await page.getByRole('button',{name:'重试加载',exact:true}).waitFor();assert.equal(await card().count(),40);
  const afterFailure=pageCalls().length;await page.evaluate(()=>window.scrollBy(0,-350));await page.locator('.th-page-end').scrollIntoViewIfNeeded();await page.waitForTimeout(120);assert.equal(pageCalls().length,afterFailure);
  await page.screenshot({path:path.join(output,`treehole-pagination-retry-${width}.png`),animations:'disabled'});
  await page.getByRole('button',{name:'重试加载',exact:true}).click();await count(45);assert.equal(await page.locator('.th-page-end').count(),0);assert(pageCalls().every(r=>r.body.snapshotTime===snapshot));
  const ids=await card().evaluateAll(els=>els.map(el=>el.dataset.postId));assert.equal(new Set(ids).size,45);checks.push(`${width}: failed third page retains forty cards, pauses auto retry, manual retry appends five unique cards`);
  const target=card().nth(26),id=ids[26];await target.evaluate(el=>window.scrollTo({top:window.scrollY+el.getBoundingClientRect().top-150,behavior:'instant'}));
  const origin=await page.evaluate(()=>window.scrollY),beforeReturn=firstCalls();await target.getByRole('button',{name:/查看评论/}).click();await page.getByRole('heading',{name:'评论',exact:true}).waitFor();
  assert.equal(await page.getByRole('navigation',{name:'主导航'}).count(),0);
  await page.waitForFunction(()=>document.querySelector('.th-detail-tabs button[aria-pressed=true]')?.textContent==='评论');
  const discussion=await page.locator('.th-discussion-title').boundingBox();assert(discussion.y>=0&&discussion.y<650);
  await page.locator('.th-reply-entry').click();await page.getByLabel('你的回复',{exact:true}).fill('翻页之后也能正确回复。');await page.getByRole('button',{name:'发布回复',exact:true}).click();await page.getByText('翻页之后也能正确回复。',{exact:true}).waitFor();
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await count(45);await page.waitForFunction(y=>Math.abs(window.scrollY-y)<3,origin);assert.equal(firstCalls(),beforeReturn);await page.locator(`.th-post[data-post-id="${id}"]`).getByRole('button',{name:'查看评论，共 1 条',exact:true}).waitFor();
  checks.push(`${width}: comment icon enters discussion; reply count updates; back retains all pages, exact scroll and makes no refresh request`);
  const tab=label=>page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:label,exact:true});
  await tab('课表').click();await page.waitForFunction(()=>location.hash==='#/schedule');await page.waitForFunction(()=>window.scrollY===0);
  await tab('社区').click();await count(45);await page.waitForFunction(y=>Math.abs(window.scrollY-y)<3,origin);
  assert.equal(await page.getByLabel('搜索树洞文字').inputValue(),keyword);assert.equal(firstCalls(),beforeReturn);
  await page.screenshot({path:path.join(output,`community-middle-tab-${width}.png`),animations:'disabled'});
  checks.push(`${width}: switching to timetable and back keeps filter, forty-five posts and exact reading position without refresh`);
  await page.locator(`.th-post[data-post-id="${id}"] .th-post-body`).click();await page.getByRole('heading',{name:'评论',exact:true}).waitFor();await page.waitForFunction(()=>window.scrollY===0);await page.getByRole('button',{name:'返回社区',exact:true}).click();await count(45);checks.push(`${width}: body opens at the top while comment icon opens discussion`);
  await page.getByRole('button',{name:'刷新树洞',exact:true}).click();await count(20);pager.state.holdNextPage=true;await page.locator('.th-page-end').scrollIntoViewIfNeeded();await page.getByText('正在加载更多帖子…',{exact:true}).waitFor();while(!pager.state.releasePage)await new Promise(r=>setTimeout(r,10));
  await page.locator('.th-category-nav').getByRole('button',{name:'校园日常',exact:true}).click();await page.getByRole('group',{name:'校园内容筛选'}).getByRole('button',{name:'提问求助',exact:true}).click();await count(0);pager.state.releasePage();pager.state.releasePage=null;await page.waitForTimeout(120);assert.equal(await card().count(),0);checks.push(`${width}: stale page response cannot append after category changes`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(pager.errors,[]);await pager.context.close();
 }
 for(const width of [360,390,430]){
  const a=await client(width);const page=a.page;await register(page,'participation_'+width,'头像同学');
  await page.getByRole('button',{name:'发帖',exact:true}).click();await page.getByLabel('想说的话').fill('头像与轻量回应的合成验收帖子');await page.getByRole('button',{name:'以昵称发布',exact:true}).click();await page.locator('.th-detail').waitFor();
  const postId=await page.locator('.th-detail').getAttribute('data-post-id');
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.locator('.th-self').click();
  const file={name:'avatar-fixture.webp',mimeType:'image/webp',buffer:fixture};await page.getByLabel('选择头像图片').setInputFiles(file);await page.getByAltText('新头像预览').waitFor();
  assert.equal(await page.getByAltText('新头像预览').evaluate(i=>i.naturalWidth===i.naturalHeight&&i.naturalWidth<=512),true);
  await page.locator('.th-avatar-editor').getByRole('button',{name:'取消',exact:true}).click();assert.equal(a.state.actions.filter(x=>x==='media.upload').length,0);
  await page.getByLabel('选择头像图片').setInputFiles(file);await page.getByAltText('新头像预览').waitFor();a.state.failAvatarUpload=true;
  await page.getByRole('button',{name:'使用这张头像',exact:true}).click();await page.getByText('连接失败，请检查网络后重试',{exact:true}).waitFor();assert.equal(await page.getByAltText('新头像预览').count(),1);assert.equal(await page.locator('.th-profile img').count(),0);
  a.state.dropAvatarSet=true;await page.getByRole('button',{name:'使用这张头像',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.th-avatar-editor button')?.disabled===false);assert.equal(await page.getByAltText('新头像预览').count(),1);
  await page.getByRole('button',{name:'使用这张头像',exact:true}).click();await page.getByText('头像已更新',{exact:true}).waitFor();await page.waitForFunction(()=>{const img=document.querySelector('.th-profile img');return img?.naturalWidth>0;});
  assert.equal(a.state.actions.filter(x=>x==='media.upload').length,1);await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(output,`avatar-account-${width}.png`),animations:'disabled'});
  checks.push(`${width}: square avatar preview, cancel, upload failure and lost confirmation retry preserve identity without duplicate uploads`);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();const card=page.locator(`[data-post-id="${postId}"]`);await card.locator('.treehole-avatar img').waitFor();
  const response=kind=>card.getByRole('button',{name:kind,exact:true});await response('我也一样').click();await page.waitForFunction(()=>document.querySelector('.th-responses button[aria-label="我也一样"]')?.getAttribute('aria-pressed')==='true');
  await response('抱抱').click();await page.waitForFunction(()=>document.querySelector('.th-responses button[aria-label="抱抱"]')?.getAttribute('aria-pressed')==='true');assert.equal(await response('我也一样').getAttribute('aria-pressed'),'false');
  await card.locator('.th-post-body').click();await page.locator('.th-detail').waitFor();assert.equal(await page.locator('.th-detail').getByRole('button',{name:'抱抱',exact:true}).getAttribute('aria-pressed'),'true');
  a.state.failResponse=true;await page.locator('.th-detail').getByRole('button',{name:'有用',exact:true}).click();await page.getByText('连接失败，请检查网络后重试',{exact:true}).waitFor();assert.equal(await page.locator('.th-detail').getByRole('button',{name:'抱抱',exact:true}).getAttribute('aria-pressed'),'true');
  await page.locator('.th-detail').getByRole('button',{name:'抱抱',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.th-responses button[aria-pressed="true"]'));
  await page.getByRole('button',{name:'返回社区',exact:true}).click();assert.equal(await card.locator('.th-responses button[aria-pressed="true"]').count(),0);assert.equal(await page.locator('.th-detail').count(),0);
  await response('有用').click();await page.waitForFunction(()=>document.querySelector('.th-responses button[aria-label="有用"]')?.getAttribute('aria-pressed')==='true');
  await page.screenshot({path:path.join(output,`response-feed-${width}.png`),animations:'disabled'});checks.push(`${width}: responses select, switch, cancel, survive detail return and roll back failures without opening cards`);
  await page.getByRole('button',{name:'发帖',exact:true}).click();await page.getByLabel('想说的话').fill('匿名头像隔离检查');await page.getByRole('checkbox',{name:'匿名发布',exact:true}).check();assert.equal(await page.locator('.th-compose-identity .treehole-avatar img').count(),0);
  await page.getByRole('button',{name:'匿名发布',exact:true}).click();await page.locator('.th-detail').waitFor();assert.equal(await page.locator('.th-detail header .treehole-avatar img').count(),0);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.locator('.th-self').click();await page.getByRole('button',{name:'恢复默认头像',exact:true}).click();await page.getByRole('button',{name:'确认',exact:true}).click();await page.getByText('已恢复默认头像',{exact:true}).waitFor();assert.equal(await page.locator('.th-profile img').count(),0);checks.push(`${width}: uploaded avatar never appears on anonymous compose/post and can be removed`);
  await page.getByLabel('选择头像图片').setInputFiles(file);await page.getByAltText('新头像预览').waitFor();a.state.holdAvatarSet=true;await page.getByRole('button',{name:'使用这张头像',exact:true}).click();for(let attempt=0;!a.state.releaseAvatarSet&&attempt<1500;attempt++)await new Promise(r=>setTimeout(r,10));assert(a.state.releaseAvatarSet,'avatar confirmation should reach transport');
  a.state.expireUnread=true;await page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await page.getByRole('heading',{name:'说说校园里的那些事'}).waitFor();a.state.releaseAvatarSet();a.state.releaseAvatarSet=null;await page.waitForTimeout(100);assert.equal(await page.locator('.th-profile').count(),0);assert.equal(await page.getByLabel('选择头像图片').count(),0);checks.push(`${width}: late avatar confirmation cannot restore an expired account`);
  a.state.legacyConfig=true;await page.reload();await page.locator('.th-post').first().waitFor();assert.equal(await page.getByRole('group',{name:'轻量回应'}).count(),0);await page.locator('.th-self').click();assert.equal(await page.getByLabel('选择头像图片').count(),0);checks.push(`${width}: older backend hides new controls and keeps existing reading/account flows`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(a.errors,[]);await a.context.close();console.log(`participation ${width}: ${checks.length} checks`);
 }
 for(const width of [360,390,430]){
  const a=await client(width),page=a.page;active=page;await register(page,`discovery_${width}`,'兴趣同学');
  const nav=page.getByRole('navigation',{name:'帖子分区'}),tabs=page.getByRole('group',{name:'兴趣标签'});
  assert.deepEqual(await nav.getByRole('button').allTextContents(),['全部','校园日常','兴趣娱乐','搭子广场','匿名树洞']);
  for(const button of await nav.getByRole('button').all()){const box=await button.boundingBox();assert(box.x>=0&&box.x+box.width<=width&&box.height>=44);}
  const create=(category,extra={})=>api.execute('posts.create',{category,body:'发现合成内容 '+category,anonymous:false,requestId:crypto.randomUUID(),...extra},a.state.token,`discovery-${width}`);
  await create('help');await create('study',{anonymous:true});await create('entertainment',{interest:'music',body:'音乐合成内容'});
  await nav.getByRole('button',{name:'校园日常',exact:true}).click();await page.getByRole('group',{name:'校园内容筛选'}).getByRole('button',{name:'学习交流',exact:true}).click();await page.locator('.th-post').first().waitFor();assert((await page.locator('.th-post').allTextContents()).every(t=>t.includes('学习交流')));checks.push(`${width}: compact four-section navigation preserves legacy study and anonymous identity`);
  await nav.getByRole('button',{name:'兴趣娱乐',exact:true}).click();await tabs.getByRole('button',{name:'游戏',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.th-progress'));if(width===360)await page.getByRole('heading',{name:'这里，等你说第一句话'}).waitFor();
  await page.getByRole('button',{name:'发帖',exact:true}).click();assert.equal(await page.getByLabel('选择分区').inputValue(),'entertainment');assert.equal(await page.getByLabel('选择兴趣标签').inputValue(),'games');
  await page.getByLabel('帖子标题').fill(`周末${width}游戏讨论`);await page.getByLabel('想说的话').fill('这周找到一款喜欢的游戏，想聊聊体验。');await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'保存草稿并返回',exact:true}).click();await page.reload();await page.locator('.th-draft-resume').click();
  assert.equal(await page.getByLabel('选择兴趣标签').inputValue(),'games');assert.equal(await page.getByLabel('帖子标题').inputValue(),`周末${width}游戏讨论`);await page.screenshot({path:path.join(output,`discovery-compose-${width}.png`)});checks.push(`${width}: selected interest is inherited and retained in the persisted draft`);
  await page.getByRole('button',{name:'以昵称发布',exact:true}).click();await page.locator('.th-detail').waitFor();const created=a.state.publicResponses.filter(r=>r.post?.title===`周末${width}游戏讨论`).at(-1).post;assert.equal(created.interest,'games');assert.equal(created.anonymous,false);
  await page.locator('.th-detail .th-category-tag').click();await tabs.waitFor();await page.waitForFunction(()=>!document.querySelector('.th-progress'));assert.equal(await tabs.getByRole('button',{name:'游戏',exact:true}).getAttribute('aria-pressed'),'true');const shownIds=await page.locator('.th-post').evaluateAll(nodes=>nodes.map(n=>n.dataset.postId));assert(shownIds.includes(created.id));
  a.state.failNextFeed=true;await tabs.getByRole('button',{name:'音乐',exact:true}).click();await page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();assert.equal(await tabs.getByRole('button',{name:'游戏',exact:true}).getAttribute('aria-pressed'),'true');assert.deepEqual(await page.locator('.th-post').evaluateAll(nodes=>nodes.map(n=>n.dataset.postId)),shownIds);checks.push(`${width}: post interest opens the matching feed; failed switching restores selection and prior content`);
  await tabs.getByRole('button',{name:'游戏',exact:true}).click();await page.getByRole('button',{name:'搜索帖子',exact:true}).click();await page.getByLabel('搜索树洞文字').fill(`周末${width}`);await page.locator('.th-search').getByRole('button',{name:'搜索',exact:true}).click();await page.locator('.th-post').first().waitFor();await page.getByRole('button',{name:'热门',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.th-progress'));
  const criteria=a.state.requests.filter(r=>r.action==='posts.list').at(-1).body;assert.equal(criteria.section,'entertainment');assert.equal(criteria.interest,'games');assert.equal(criteria.query,`周末${width}`);assert.equal(criteria.sort,'hot');
  await page.locator('.th-post-body').click();await page.locator('.th-detail').waitFor();await page.getByRole('button',{name:'返回社区',exact:true}).click();assert.equal(await tabs.getByRole('button',{name:'游戏',exact:true}).getAttribute('aria-pressed'),'true');checks.push(`${width}: interest, search, hot sort and detail return use the same feed criteria`);
  await page.getByRole('button',{name:'清除搜索',exact:true}).click();await page.getByRole('button',{name:'搜索帖子',exact:true}).click();await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(output,`discovery-feed-${width}.png`)});
  await nav.getByRole('button',{name:'匿名树洞',exact:true}).click();await page.getByRole('button',{name:'发帖',exact:true}).click();const anon=page.getByRole('checkbox',{name:'匿名发布',exact:true});assert(await anon.isChecked());assert(await anon.isDisabled());await page.getByLabel('想说的话').fill('匿名树洞里的合成文字');await page.getByRole('button',{name:'匿名发布',exact:true}).click();await page.locator('.th-detail').waitFor();const hidden=a.state.publicResponses.filter(r=>r.post?.category==='treehole').at(-1).post;assert(hidden.anonymous);assert(!hidden.author.id);assert(!hidden.author.avatar);checks.push(`${width}: anonymous section enforces identity separation through publishing`);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await nav.getByRole('button',{name:'搭子广场',exact:true}).click();await page.getByRole('button',{name:'发帖',exact:true}).click();assert.equal(await page.getByLabel('选择分区').inputValue(),'buddies');assert.equal(await anon.isDisabled(),false);checks.push(`${width}: buddies remain ordinary posts and other sections keep optional anonymity`);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();a.state.legacyConfig=true;await page.reload();await page.locator('.th-post').first().waitFor();assert.equal(await page.getByRole('navigation',{name:'帖子分区'}).getByRole('button',{name:'兴趣娱乐',exact:true}).count(),0);checks.push(`${width}: old backend keeps the original category navigation`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);assert.deepEqual(a.errors,[]);await a.context.close();
 }
 for(const width of [360,390,430]){
  const a=await client(width),b=await client(width),page=b.page;await register(a.page,'following_author_'+width,'关注作者'+width);await register(page,'following_reader_'+width,'关注读者'+width);
  const author=(await db.query('SELECT id FROM hyt_members WHERE username=$1',['following_author_'+width])).rows[0].id;
  const title='关注公开分享'+width;
  await api.execute('posts.create',{title,body:'合成游戏分享',category:'entertainment',interest:'games',anonymous:false,requestId:crypto.randomUUID()},a.state.token,'following');
  await api.execute('posts.create',{title:'关注匿名秘密'+width,body:'匿名内容不进入关注动态',category:'treehole',anonymous:true,requestId:crypto.randomUUID()},a.state.token,'following');
  const scopes=page.locator('.th-return-links'),followTab=scopes.getByRole('button',{name:'关注动态',exact:true});
  await followTab.click();await page.getByRole('heading',{name:'暂时没有公开动态'}).waitFor();assert.equal(await page.locator('.th-post').count(),0);
  assert.equal(await scopes.evaluate(el=>el.scrollWidth>el.clientWidth),false);checks.push(`${width}: four compact feed scopes fit and an empty following feed never invents posts`);
  await scopes.getByRole('button',{name:'广场',exact:true}).click();const named=page.locator('.th-post').filter({hasText:title});await named.getByRole('button',{name:'查看 关注作者'+width+' 的主页',exact:true}).click();await page.getByRole('button',{name:'关注 TA',exact:true}).waitFor();
  b.state.failFollow=true;await page.getByRole('button',{name:'关注 TA',exact:true}).click();await page.getByRole('alert').waitFor();assert.equal(await page.getByRole('button',{name:'关注 TA',exact:true}).getAttribute('aria-pressed'),'false');
  await page.getByRole('button',{name:'关注 TA',exact:true}).click();await page.getByRole('button',{name:'已关注 · 取消关注',exact:true}).waitFor();await page.screenshot({path:path.join(output,`following-profile-${width}.png`)});checks.push(`${width}: profile follow failure keeps state and explicit retry confirms the server relation`);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await followTab.click();await page.getByRole('heading',{name:title,exact:true}).waitFor();assert.equal(await page.locator('.th-post').count(),1);assert.equal(await page.getByText('关注匿名秘密'+width,{exact:true}).count(),0);
  await page.getByRole('navigation',{name:'帖子分区'}).getByRole('button',{name:'兴趣娱乐',exact:true}).click();await page.getByRole('group',{name:'兴趣标签'}).getByRole('button',{name:'游戏',exact:true}).click();await page.getByRole('button',{name:'热门',exact:true}).click();assert.equal(await followTab.getAttribute('aria-pressed'),'true');
  await page.getByRole('button',{name:'搜索帖子',exact:true}).click();await page.getByLabel('搜索树洞文字').fill('合成游戏');await page.locator('.th-search').getByRole('button',{name:'搜索',exact:true}).click();await named.locator('.th-post-body').click();await page.locator('.th-detail').waitFor();await page.getByRole('button',{name:'返回社区',exact:true}).click();await named.waitFor();assert.equal(await followTab.getAttribute('aria-pressed'),'true');assert.equal(await page.getByLabel('搜索树洞文字').inputValue(),'合成游戏');
  await page.screenshot({path:path.join(output,`following-feed-${width}.png`)});checks.push(`${width}: following excludes anonymous posts and persists through interest/search/hot/detail return`);
  b.state.failNextFeed=true;await scopes.getByRole('button',{name:'广场',exact:true}).click();await page.getByRole('alert').waitFor();assert.equal(await followTab.getAttribute('aria-pressed'),'true');assert.equal(await page.getByLabel('搜索树洞文字').inputValue(),'合成游戏');assert.equal(await page.locator('.th-post').count(),1);checks.push(`${width}: failed feed-scope switch restores criteria and previous visible posts`);
  await page.locator('.th-self').click();await page.getByRole('button',{name:'我关注的人',exact:true}).click();await page.locator('.th-person').waitFor();await page.screenshot({path:path.join(output,`following-people-${width}.png`)});
  await page.getByRole('button',{name:'查看 关注作者'+width+' 的主页',exact:true}).click();await page.getByRole('button',{name:'已关注 · 取消关注',exact:true}).click();await page.getByRole('button',{name:'关注 TA',exact:true}).click();await page.getByRole('button',{name:'已关注 · 取消关注',exact:true}).waitFor();await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.locator('.th-person').waitFor();
  b.state.failFollow=true;await page.getByRole('button',{name:'取消关注 关注作者'+width,exact:true}).click();await page.getByRole('alert').waitFor();assert.equal(await page.locator('.th-person').count(),1);await page.getByRole('button',{name:'取消关注 关注作者'+width,exact:true}).click();await page.getByText('还没有关注同学',{exact:true}).waitFor();
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('heading',{name:'暂时没有公开动态'}).waitFor();checks.push(`${width}: private management survives profile refollow, failed unfollow and return; successful unfollow removes feed posts`);
  if(width===360){
   const reader=(await db.query('SELECT id FROM hyt_members WHERE username=$1',['following_reader_'+width])).rows[0].id;
   for(let i=0;i<25;i++){const id=crypto.randomUUID();await db.query("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash) VALUES($1,$2,$3,'synthetic','synthetic')",[id,'followpage_'+i,'名单同学'+i]);await db.query("INSERT INTO hyt_follows(member_id,followed_id,created_at) VALUES($1,$2,now()-($3||' seconds')::interval)",[reader,id,String(i)]);}
   await page.locator('.th-self').click();await page.getByRole('button',{name:'我关注的人',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.th-person').length===20);
   b.state.failFollowList=true;await page.getByRole('button',{name:'加载更多同学',exact:true}).click();await page.locator('.th-following-list').getByRole('alert').waitFor();assert.equal(await page.locator('.th-person').count(),20);
   await page.getByRole('button',{name:'重试加载',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.th-person').length===25);assert.equal(await page.getByRole('button',{name:'加载更多同学',exact:true}).count(),0);checks.push('360: following list pagination failure retains twenty rows and retry appends five without duplicates');
   await page.locator('.th-person-identity').first().click();await page.getByRole('heading',{name:'同学主页',exact:true}).waitFor();b.state.failFollowList=true;await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.locator('.th-following-list').getByRole('alert').waitFor();assert.equal(await page.locator('.th-person').count(),25);
   await page.getByRole('button',{name:'重试加载',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.th-person').length===20);checks.push('360: failed first-page refresh after profile return retries refresh even with cached rows and no old next cursor');
   await db.query('DELETE FROM hyt_follows WHERE member_id=$1',[reader]);await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'返回社区',exact:true}).click();
  }
  await scopes.getByRole('button',{name:'广场',exact:true}).click();await named.getByRole('button',{name:'查看 关注作者'+width+' 的主页',exact:true}).click();b.state.holdFollow=true;await page.getByRole('button',{name:'关注 TA',exact:true}).click();for(let i=0;!b.state.releaseFollow&&i<1500;i++)await new Promise(r=>setTimeout(r,10));assert(b.state.releaseFollow);
  b.state.expireUnread=true;await page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await page.getByRole('heading',{name:'说说校园里的那些事'}).waitFor();b.state.releaseFollow();b.state.releaseFollow=null;await page.waitForTimeout(100);assert.equal(await page.locator('.th-public-profile').count(),0);assert.equal(await page.locator('.th-following-list').count(),0);checks.push(`${width}: late follow confirmation cannot resurrect an expired account`);
  b.state.legacyConfig=true;await page.reload();await page.locator('.th-post').first().waitFor();assert.equal(await page.getByRole('button',{name:'关注动态',exact:true}).count(),0);await page.locator('.th-self').click();assert.equal(await page.getByRole('button',{name:'我关注的人',exact:true}).count(),0);checks.push(`${width}: older backend hides follow entry points without changing existing account flows`);
  assert.deepEqual(a.errors,[]);assert.deepEqual(b.errors,[]);await a.context.close();await b.context.close();
 }
 }
 // Poll and comment-media paths exercise the same live SQL/HTTP/native boundary.
 if(!process.env.HYT_BUDDIES_ONLY){
 for(const width of [360,390,430]){
  const a=await client(width),page=a.page;await register(page,'poll_author_'+width,'投票同学'+width);
  await page.getByRole('button',{name:'发帖',exact:true}).click();await page.getByRole('button',{name:'＋ 添加投票',exact:true}).click();
  assert(await page.getByRole('button',{name:'以昵称发布',exact:true}).isDisabled());
  await page.getByLabel('投票问题',{exact:true}).fill('周末一起做什么？');await page.getByLabel('投票选项 1',{exact:true}).fill('去运动');await page.getByLabel('投票选项 2',{exact:true}).fill('去运动');assert(await page.getByRole('button',{name:'以昵称发布',exact:true}).isDisabled());
  await page.getByLabel('投票选项 2',{exact:true}).fill('去拍照');await page.getByLabel('投票时长',{exact:true}).selectOption('24');
  for(let i=0;i<4;i++)await page.getByRole('button',{name:'＋ 添加选项',exact:true}).click();assert.equal(await page.getByRole('button',{name:'＋ 添加选项',exact:true}).count(),0);
  for(let i=6;i>2;i--)await page.getByRole('button',{name:'移除选项 '+i,exact:true}).click();
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'保存草稿并返回',exact:true}).click();await page.reload();await page.locator('.th-draft-resume').click();assert.equal(await page.getByLabel('投票问题',{exact:true}).inputValue(),'周末一起做什么？');assert.equal(await page.getByLabel('投票时长',{exact:true}).inputValue(),'24');
  checks.push(`${width}: poll validates unique options, limits six, and restores poll-only draft with duration`);
  a.state.dropNextPost=true;await page.getByRole('button',{name:'以昵称发布',exact:true}).click();await page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();await page.getByRole('button',{name:'以昵称发布',exact:true}).click();await page.locator('.th-detail .th-poll').waitFor();
  const pid=a.state.requests.filter(r=>r.action==='posts.get').at(-1).body.postId;
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_posts WHERE author_id=(SELECT id FROM hyt_members WHERE username=$1)',['poll_author_'+width])).rows[0].n,1);
  const poll=page.locator('.th-detail .th-poll');assert.equal(await page.locator('.th-detail .th-full-body p').count(),0);
  await poll.getByRole('button',{name:'投票：去运动',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.th-detail .th-poll-option')?.getAttribute('aria-pressed')==='true');
  a.state.failVote=true;await poll.getByRole('button',{name:'投票：去拍照',exact:true}).click();await page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();assert.equal(await poll.getByRole('button',{name:'投票：去运动',exact:true}).getAttribute('aria-pressed'),'true');
  await poll.getByRole('button',{name:'投票：去拍照',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.th-detail .th-poll-option')[1]?.getAttribute('aria-pressed')==='true');
  await page.getByRole('button',{name:'返回社区',exact:true}).click();const card=page.locator(`[data-post-id="${pid}"]`);await card.waitFor();assert.equal(await card.getByRole('button',{name:'投票：去拍照',exact:true}).getAttribute('aria-pressed'),'true');
  await card.getByRole('button',{name:'撤回投票',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.th-poll-option[aria-pressed=true]'));assert.equal(await page.locator('.th-detail').count(),0);assert((await card.innerText()).includes('0 人参与'));
  checks.push(`${width}: lost publish retry is idempotent; vote failure, switch, route restore and cancellation keep confirmed counts`);
  await card.getByRole('button',{name:'查看评论，共 0 条',exact:true}).click();await page.locator('.th-detail').waitFor();
  await page.locator('.th-reply-entry').click();await page.getByLabel('添加评论图片').setInputFiles([{name:'one.webp',mimeType:'image/webp',buffer:fixture},{name:'two.webp',mimeType:'image/webp',buffer:fixture},{name:'three.webp',mimeType:'image/webp',buffer:fixture}]);await page.waitForFunction(()=>document.querySelectorAll('.th-comment-photo-editor img').length===3);
  assert.equal(await page.getByLabel('添加评论图片').count(),0);await page.getByRole('button',{name:'移除评论图片 3',exact:true}).click();await page.getByRole('button',{name:'移除评论图片 2',exact:true}).click();
  a.state.failCommentUpload=true;await page.getByRole('button',{name:'发布回复',exact:true}).click();await page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();assert.equal(await page.locator('.th-comment-photo-editor img').count(),1);
  a.state.dropComment=true;await page.getByRole('button',{name:'发布回复',exact:true}).click();await page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();await page.getByRole('button',{name:'发布回复',exact:true}).click();await page.locator('.th-comment .th-media').waitFor();
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_comments WHERE post_id=$1',[pid])).rows[0].n,1);assert.equal((await db.query("SELECT count(*)::int AS n FROM hyt_media WHERE post_id=$1 AND comment_id IS NOT NULL",[pid])).rows[0].n,1);
  await page.locator('.th-comment .th-media button').first().click();await page.locator('.th-gallery').waitFor();assert(await page.locator('.th-gallery img').evaluate(i=>i.complete&&i.naturalWidth>0));await page.getByRole('button',{name:'关闭大图'}).click();
  checks.push(`${width}: three-image picker limit, upload failure, lost comment retry, image-only comment and full gallery`);
  await page.locator('.th-comment').first().getByRole('button',{name:'回复',exact:true}).click();await page.getByLabel('添加评论图片').setInputFiles({name:'reply.webp',mimeType:'image/webp',buffer:fixture});await page.locator('.th-comment-photo-editor img').waitFor();await page.getByRole('button',{name:'发布回复',exact:true}).click();await page.locator('.th-replies .th-media').waitFor();await page.locator('.th-replies .th-media button').first().click();await page.locator('.th-gallery').waitFor();await page.getByRole('button',{name:'关闭大图'}).click();assert.equal(await page.locator('.th-detail .th-media').count(),0);
  checks.push(`${width}: image-only nested reply opens gallery independently and comment images never enter post gallery`);
  await db.query("UPDATE hyt_polls SET closes_at=now()-interval '1 second' WHERE post_id=$1",[pid]);await poll.getByRole('button',{name:'投票：去运动',exact:true}).click();await page.getByRole('alert').filter({hasText:'投票已截止'}).waitFor();assert(await poll.getByRole('button',{name:'投票：去运动',exact:true}).isDisabled());
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.screenshot({path:path.join(output,`poll-comments-${width}.png`),animations:'disabled'});checks.push(`${width}: server expiry disables voting and dense poll/comment layout fits screen`);
  a.state.legacyConfig=true;await page.reload();await page.getByRole('button',{name:'发帖',exact:true}).click();assert.equal(await page.getByRole('button',{name:'＋ 添加投票',exact:true}).count(),0);checks.push(`${width}: old backend hides new composer entry`);
  assert.deepEqual(a.errors,[]);await a.context.close();
 }
}
 // Isolate the added scenarios from the earlier groups' synthetic auth-IP budget.
 // Production authentication limits remain unchanged and have dedicated backend tests.
 await db.query('DELETE FROM hyt_community_rate');
 // Buddy registration uses the real SQL transaction, not preview fixture behavior.
 for(const width of [360,390,430]){
  const a=await client(width),b=await client(width),page=a.page;await register(page,'buddy_author_'+width,'搭子发起人'+width);await register(b.page,'buddy_reader_'+width,'报名同学'+width);
  await page.getByRole('button',{name:'发帖',exact:true}).click();await page.getByLabel('选择分区').selectOption('buddies');await page.getByRole('button',{name:'＋ 设置时间、地点和报名',exact:true}).click();
  assert(await page.getByRole('button',{name:'以昵称发布',exact:true}).isDisabled());assert.equal(await page.getByRole('button',{name:'＋ 添加投票',exact:true}).count(),0);assert(await page.getByLabel('选择分区').isDisabled());
  await page.getByLabel('想说的话').fill('下课去操场慢跑，按自己的节奏就好。');await page.getByLabel('搭子集合地点').fill('东操场入口');await page.getByLabel('招募人数').selectOption('1');
  const date=new Date(Date.now()+24*3600000+8*3600000).toISOString().slice(0,16);await page.getByLabel('搭子活动时间').fill(date);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'保存草稿并返回',exact:true}).click();await page.reload();await page.locator('.th-draft-resume').click();assert.equal(await page.getByLabel('搭子集合地点').inputValue(),'东操场入口');assert.equal(await page.getByLabel('搭子活动时间').inputValue(),date);checks.push(`${width}: buddy composer validates required fields, prevents poll/category conflict, and restores campus-time draft`);
  a.state.dropNextPost=true;await page.getByRole('button',{name:'以昵称发布',exact:true}).click();await page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();await page.getByRole('button',{name:'以昵称发布',exact:true}).click();await page.locator('.th-detail .th-buddy').waitFor();
  const pid=await page.locator('.th-detail').getAttribute('data-post-id');assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_posts WHERE author_id=(SELECT id FROM hyt_members WHERE username=$1)',['buddy_author_'+width])).rows[0].n,1);checks.push(`${width}: lost buddy publish response retries without duplicate meetup`);
  await b.page.getByRole('button',{name:'刷新树洞',exact:true}).click();const card=b.page.locator(`[data-post-id="${pid}"]`);await card.waitFor();
  b.state.failBuddy=true;await card.getByRole('button',{name:'一起去 · 报名',exact:true}).click();await b.page.getByRole('alert').filter({hasText:'连接失败'}).last().waitFor();assert((await card.innerText()).includes('0 / 1 人已报名'));
  b.state.dropBuddy=true;await card.getByRole('button',{name:'一起去 · 报名',exact:true}).click();await b.page.waitForFunction(()=>!document.querySelector('.th-buddy button')?.textContent.includes('处理中'));await card.getByRole('button',{name:'一起去 · 报名',exact:true}).click();await card.getByRole('button',{name:'已报名 · 退出',exact:true}).waitFor();assert((await card.innerText()).includes('1 / 1 人已报名'));assert.equal(await b.page.locator('.th-detail').count(),0);checks.push(`${width}: join failure leaves count intact; lost confirmation retries idempotently without opening detail`);
  await page.getByRole('button',{name:'查看报名',exact:true}).click();await page.locator('.th-buddy-roster-list strong').waitFor();assert.equal(await page.locator('.th-buddy-roster-list strong').innerText(),'报名同学'+width);assert(!(await page.locator('.th-buddy-roster').innerText()).includes('buddy_reader'));
  if(width===360){await page.setViewportSize({width,height:500});await page.waitForTimeout(400);await page.screenshot({path:path.join(output,'buddy-roster-short.png')});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.setViewportSize({width,height:844});}
  await page.getByRole('button',{name:'关闭报名名单',exact:true}).click();assert((await page.locator('.th-detail .th-buddy').innerText()).includes('1 / 1 人已报名'));checks.push(`${width}: host roster shows private nickname, refreshes count, and closes back to the same detail`);
  await card.locator('.th-post-body').click();await b.page.locator('.th-detail').waitFor();await b.page.getByRole('button',{name:'返回社区',exact:true}).click();await card.getByRole('button',{name:'已报名 · 退出',exact:true}).waitFor();await b.page.locator('.th-self').click();await b.page.getByRole('button',{name:/^我报名的/}).click();await card.waitFor();assert.equal(await b.page.locator('.th-post').count(),1);checks.push(`${width}: joined state survives detail return and private joined-feed navigation`);
  await page.getByRole('button',{name:'结束招募',exact:true}).click();await page.getByRole('button',{name:'重新开放',exact:true}).waitFor();await b.page.getByRole('button',{name:'刷新树洞',exact:true}).click();await b.page.waitForFunction(()=>document.querySelector('.th-buddy')?.textContent.includes('已结束招募'));await card.getByRole('button',{name:'已报名 · 退出',exact:true}).click();await b.page.waitForFunction(()=>document.querySelector('.th-buddy')?.textContent.includes('0 / 1 人已报名'));assert(await card.getByRole('button',{name:'已结束招募',exact:true}).isDisabled());checks.push(`${width}: closing recruitment stops new signup while allowing existing member cancellation`);
  await page.getByRole('button',{name:'重新开放',exact:true}).click();await page.getByRole('button',{name:'结束招募',exact:true}).waitFor();await b.page.getByRole('button',{name:'刷新树洞',exact:true}).click();await b.page.waitForFunction(()=>document.querySelectorAll('.th-post').length===0);await b.page.getByRole('button',{name:'查看全部',exact:true}).click();await card.waitFor();await card.getByRole('button',{name:'一起去 · 报名',exact:true}).waitFor();
  b.state.holdBuddy=true;await card.getByRole('button',{name:'一起去 · 报名',exact:true}).click();while(!b.state.releaseBuddy)await b.page.waitForTimeout(10);b.state.expireUnread=true;await b.page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await b.page.getByRole('heading',{name:'说说校园里的那些事'}).waitFor();b.state.releaseBuddy();b.state.releaseBuddy=null;await b.page.waitForTimeout(100);assert.equal(await b.page.locator('.th-buddy').count(),0);checks.push(`${width}: late signup response cannot restore an expired account`);
  await page.screenshot({path:path.join(output,`buddy-detail-${width}.png`),animations:'disabled'});
  a.state.legacyConfig=true;await page.reload();await page.locator('.th-self').click();assert.equal(await page.getByRole('button',{name:/^我报名的/}).count(),0);await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'发帖',exact:true}).click();await page.getByLabel('选择分区').selectOption('buddies');assert.equal(await page.getByRole('button',{name:'＋ 设置时间、地点和报名',exact:true}).count(),0);checks.push(`${width}: older backend hides buddy editing and joined entry while legacy posts remain readable`);
  assert.deepEqual(a.errors,[]);assert.deepEqual(b.errors,[]);await a.context.close();await b.context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({backend:'actual PostgreSQL (PGlite), HTTP service',bridge:'test-only native adapter',checks},null,2));
 console.log(JSON.stringify({passed:checks.length,output}));
}catch(error){if(active&&!active.isClosed())await active.screenshot({path:path.join(output,'failure.png')});throw error;}
finally{await browser.close();await new Promise(r=>server.close(r));await new Promise(r=>backend.close(r));await db.close();}
