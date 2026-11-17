/** Actual PostgreSQL + HTTP + UI integration; only the native bridge/storage is adapted. */
import {createServer as staticServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {chromium} from 'playwright';
import {createCommunity} from '../cloudbase/functions/community/core.mjs';
import {createServer} from '../cloudbase/functions/community/server.mjs';

const root=path.resolve('dist'),output='/tmp/handan-admin-center-qa';await mkdir(output,{recursive:true});
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
const redesignBaseline=process.env.COMMUNITY_REDESIGN_BASELINE==='1';
async function client(width){
 const context=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});
 const state={token:null,dropNextPost:false,failNextReaction:false,releaseReaction:null,breakNextImage:false,delayImage:false,publicResponses:[],actions:[],requests:[],holdNextPage:false,releasePage:null,failNextPage:false,holdNextDetail:false,releaseDetail:null,failNextDetail:false};
 await context.exposeBinding('__treeholeNative',async(_,options)=>{
  const {action,body}=options;if(action==='buddies.join'&&state.failBuddy){state.failBuddy=false;return {error:'network_unavailable'};}if(action==='polls.vote'&&state.failVote){state.failVote=false;return {error:'network_unavailable'};}if(action==='media.upload'&&body?.purpose==='comment'&&state.failCommentUpload){state.failCommentUpload=false;return {error:'network_unavailable'};}if(action==='follows.set'&&state.failFollow){state.failFollow=false;return {error:'network_unavailable'};}if(action==='follows.list'&&state.failFollowList){state.failFollowList=false;return {error:'network_unavailable'};}if(action==='posts.list'&&!body?.beforeId&&state.failNextFeed){state.failNextFeed=false;return {error:'network_unavailable'};}if(action==='notifications.unread'&&state.expireUnread){state.expireUnread=false;return {error:'session_expired'};}if(action==='media.upload'&&state.failAvatarUpload){state.failAvatarUpload=false;return {error:'network_unavailable'};}if(action==='responses.set'&&state.failResponse){state.failResponse=false;return {error:'network_unavailable'};}state.actions.push(action);state.requests.push({action,body});if(action==='posts.get'&&state.failNextDetail){state.failNextDetail=false;return {error:'network_unavailable'};}if(action==='posts.list'&&body?.beforeId&&state.failNextPage){state.failNextPage=false;return {error:'network_unavailable'};}if(action==='reactions.set'&&state.failNextReaction){state.failNextReaction=false;await new Promise(resolve=>state.releaseReaction=resolve);return {error:'network_unavailable'};}const headers={'Content-Type':'application/json'};
  if(state.token)headers.Authorization='Bearer '+state.token;
  const result=await fetch(endpoint+'/v1/'+action,{method:action==='config'?'GET':'POST',headers,...(action==='config'?{}:{body:JSON.stringify(body)})});
  const json=await result.json();if(action==='buddies.join'&&state.holdBuddy){state.holdBuddy=false;await new Promise(resolve=>state.releaseBuddy=resolve);}if(action==='buddies.join'&&state.dropBuddy){state.dropBuddy=false;return {error:'network_unavailable'};}if(action==='follows.set'&&state.holdFollow){state.holdFollow=false;await new Promise(resolve=>state.releaseFollow=resolve);}if(action==='avatar.set'&&state.holdAvatarSet){state.holdAvatarSet=false;await new Promise(resolve=>state.releaseAvatarSet=resolve);}if(action==='config'&&state.legacyConfig){delete json.moderationEnabled;delete json.responseKinds;delete json.messagesEnabled;delete json.socialEnabled;delete json.avatarsEnabled;delete json.responsesEnabled;delete json.discoveryEnabled;delete json.followingEnabled;delete json.buddiesEnabled;delete json.pollsEnabled;delete json.commentImagesEnabled;}if(action==='posts.get'&&state.holdNextDetail){state.holdNextDetail=false;await new Promise(resolve=>state.releaseDetail=resolve);}if(action==='posts.list'&&body?.beforeId&&state.holdNextPage){state.holdNextPage=false;await new Promise(resolve=>state.releasePage=resolve);}if(!result.ok)return {error:json.error};
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
 for(const width of [360,390,430]){
  const a=await client(width),page=a.page;await register(page,'admin_review_'+width,'社区管理员');
  await db.query("UPDATE hyt_members SET role='moderator' WHERE username=$1",['admin_review_'+width]);
  const subject=await api.execute('register',{username:'admin_subject_'+width,nickname:'测试同学',password:'synthetic-long-password',agreed:true},'','seed'+width);
  const call=(action,body)=>api.execute(action,body,subject.sessionToken,'seed'+width);
  const p=(await call('posts.create',{title:'图书馆讨论需要核实',body:'这是隔离测试内容，用于检查管理员能否看到完整上下文。',anonymous:true,requestId:crypto.randomUUID()})).post;
  const c=(await call('comments.create',{postId:p.id,body:'这是被举报评论，不能只看到一句举报理由。',anonymous:true,requestId:crypto.randomUUID()})).comment;
  await call('reports.create',{postId:p.id,commentId:c.id,reason:'举报人的判断，需要进一步核实'});
  await page.reload();await page.locator('.th-self').click();await page.getByRole('button',{name:process.env.ADMIN_BASELINE==='1'?'处理举报':'管理中心',exact:true}).click();
  await page.waitForFunction(()=>!document.querySelector('.th-screen-panel')?.getAnimations().some(a=>a.playState==='running'));
  if(process.env.ADMIN_BASELINE==='1'){
   await page.getByRole('heading',{name:'举报处理',exact:true}).waitFor();await page.screenshot({path:path.join(output,`admin-queue-${width}.png`),animations:'disabled'});await a.context.close();continue;
  }
  await page.getByRole('region',{name:'社区管理中心'}).waitFor();await page.getByRole('button',{name:/举报人的判断/}).waitFor();
  await page.screenshot({path:path.join(output,`admin-queue-${width}.png`),animations:'disabled'});
  await page.getByRole('button',{name:/举报人的判断/}).click();await page.getByText(c.body,{exact:true}).waitFor();assert.equal(await page.getByLabel('处理理由',{exact:true}).inputValue(),'');
  await page.getByLabel('选择操作',{exact:true}).selectOption('lock');await page.getByLabel('处理理由',{exact:true}).fill('核对帖子与评论后，暂停整篇回复');await page.getByRole('button',{name:'核对处理内容',exact:true}).click();assert.equal((await api.execute('admin.context',{postId:p.id},a.state.token,'assert')).post.locked,false);
  await page.screenshot({path:path.join(output,`admin-decision-${width}.png`),animations:'disabled'});await page.getByRole('button',{name:'确认执行',exact:true}).click();await page.getByText('处理已完成，操作记录已保存',{exact:true}).waitFor();assert.equal((await api.execute('admin.context',{postId:p.id},a.state.token,'assert')).post.locked,true);
  await page.getByRole('button',{name:'操作记录',exact:true}).click();await page.locator('.admin-record').filter({hasText:'核对帖子与评论后，暂停整篇回复'}).first().waitFor();await page.screenshot({path:path.join(output,`admin-history-${width}.png`),animations:'disabled'});
  await page.getByRole('button',{name:'内容管理',exact:true}).click();await page.getByLabel('搜索帖子内容').fill(p.title);await page.getByRole('button',{name:'搜索',exact:true}).click();await page.getByRole('button',{name:new RegExp(p.title)}).waitFor();await page.screenshot({path:path.join(output,`admin-content-${width}.png`),animations:'disabled'});
  await page.getByRole('button',{name:new RegExp(p.title)}).click();await page.getByLabel('选择操作',{exact:true}).selectOption('unlock');await page.getByLabel('处理理由',{exact:true}).fill('确认讨论可继续');await page.getByRole('button',{name:'核对处理内容',exact:true}).click();await page.getByRole('button',{name:'确认执行',exact:true}).click();await page.getByText('处理已完成，操作记录已保存',{exact:true}).waitFor();
  await page.locator('html').evaluate(el=>el.dataset.theme='dark');await page.screenshot({path:path.join(output,`admin-dark-${width}.png`),animations:'disabled'});await page.setViewportSize({width,height:520});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.screenshot({path:path.join(output,`admin-short-${width}.png`),animations:'disabled'});
  checks.push(`${width}: real report context, independent reason, two-step confirmation, lock/history/search/unlock, dark and short viewport`);assert.deepEqual(a.errors,[]);await a.context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({checks,synthetic:true,backend:'PGlite + HTTP',baseline:process.env.ADMIN_BASELINE==='1'},null,2));
 console.log(JSON.stringify({passed:checks.length,baseline:process.env.ADMIN_BASELINE==='1'}));
}catch(e){if(active&&!active.isClosed())await active.screenshot({path:path.join(output,'failure.png')});throw e}
finally{await browser.close();await new Promise(r=>server.close(r));await new Promise(r=>backend.close(r));await db.close()}
