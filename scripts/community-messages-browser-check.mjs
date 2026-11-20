import {registerTestAccount as register} from './community-test-account.mjs';
/** Actual PostgreSQL + HTTP + UI integration; only the native bridge/storage is adapted. */
import {createServer as staticServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {chromium} from 'playwright';
import {createCommunity} from '../cloudbase/functions/community/core.mjs';
import {createServer} from '../cloudbase/functions/community/server.mjs';

const root=path.resolve('dist'),output='/tmp/handan-community-messages-v15-qa';await mkdir(output,{recursive:true});
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
  const {action,body}=options;if(action==='messages.send'&&state.failMessage){state.failMessage=false;return {error:'network_unavailable'};}if(action==='buddies.join'&&state.failBuddy){state.failBuddy=false;return {error:'network_unavailable'};}if(action==='polls.vote'&&state.failVote){state.failVote=false;return {error:'network_unavailable'};}if(action==='media.upload'&&body?.purpose==='comment'&&state.failCommentUpload){state.failCommentUpload=false;return {error:'network_unavailable'};}if(action==='follows.set'&&state.failFollow){state.failFollow=false;return {error:'network_unavailable'};}if(action==='follows.list'&&state.failFollowList){state.failFollowList=false;return {error:'network_unavailable'};}if(action==='posts.list'&&!body?.beforeId&&state.failNextFeed){state.failNextFeed=false;return {error:'network_unavailable'};}if(action==='notifications.unread'&&state.expireUnread){state.expireUnread=false;return {error:'session_expired'};}if(action==='media.upload'&&state.failAvatarUpload){state.failAvatarUpload=false;return {error:'network_unavailable'};}if(action==='responses.set'&&state.failResponse){state.failResponse=false;return {error:'network_unavailable'};}state.actions.push(action);state.requests.push({action,body});if(action==='posts.get'&&state.failNextDetail){state.failNextDetail=false;return {error:'network_unavailable'};}if(action==='posts.list'&&body?.beforeId&&state.failNextPage){state.failNextPage=false;return {error:'network_unavailable'};}if(action==='reactions.set'&&state.failNextReaction){state.failNextReaction=false;await new Promise(resolve=>state.releaseReaction=resolve);return {error:'network_unavailable'};}const headers={'Content-Type':'application/json'};
  if(state.token)headers.Authorization='Bearer '+state.token;
  const result=await fetch(endpoint+'/v1/'+action,{method:action==='config'?'GET':'POST',headers,...(action==='config'?{}:{body:JSON.stringify(action==='me'&&(state.legacyConfig||state.preBoardsConfig)?{}:body)})});
  const json=await result.json();if(action==='me'&&(state.legacyConfig||state.preBoardsConfig))delete json.config;if(action==='buddies.join'&&state.holdBuddy){state.holdBuddy=false;await new Promise(resolve=>state.releaseBuddy=resolve);}if(action==='buddies.join'&&state.dropBuddy){state.dropBuddy=false;return {error:'network_unavailable'};}if(action==='follows.set'&&state.holdFollow){state.holdFollow=false;await new Promise(resolve=>state.releaseFollow=resolve);}if(action==='avatar.set'&&state.holdAvatarSet){state.holdAvatarSet=false;await new Promise(resolve=>state.releaseAvatarSet=resolve);}if(action==='config'&&state.legacyConfig){delete json.responseKinds;delete json.messagesEnabled;delete json.socialEnabled;delete json.avatarsEnabled;delete json.responsesEnabled;delete json.discoveryEnabled;delete json.followingEnabled;delete json.buddiesEnabled;delete json.pollsEnabled;delete json.commentImagesEnabled;}if(action==='posts.get'&&state.holdNextDetail){state.holdNextDetail=false;await new Promise(resolve=>state.releaseDetail=resolve);}if(action==='posts.list'&&body?.beforeId&&state.holdNextPage){state.holdNextPage=false;await new Promise(resolve=>state.releasePage=resolve);}if(!result.ok)return {error:json.error};
  if(json.sessionToken){state.token=json.sessionToken;delete json.sessionToken;}
  if(action==='messages.send'&&state.dropMessage){state.dropMessage=false;return {error:'network_unavailable'};}if(action==='messages.list'&&state.holdMessages){state.holdMessages=false;await new Promise(resolve=>state.releaseMessages=resolve);}
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

try{
 for(const width of [360,390,430]){
  await db.exec('DELETE FROM hyt_community_rate');
  const a=await client(width),b=await client(width),page=a.page;active=page;
  await register(page,'dm_a_'+width,'私信同学甲'+width);await register(b.page,'dm_b_'+width,'私信同学乙'+width);
  await api.execute('follows.set',{memberId:a.state.token? (await api.execute('me',{},a.state.token)).user.id:'' ,enabled:true},b.state.token,'follow');
  await page.locator('.th-self').click();await page.getByLabel('我的粉丝列表',{exact:true}).waitFor();await page.waitForFunction(()=>document.querySelector('[aria-label="我的粉丝列表"] strong')?.textContent==='1');
  await page.screenshot({path:path.join(output,`own-profile-${width}.png`)});await page.getByLabel('我的粉丝列表',{exact:true}).click();await page.getByLabel('回关 私信同学乙'+width,{exact:true}).click();await page.getByLabel('取消关注 私信同学乙'+width,{exact:true}).waitFor();assert.equal(await page.locator('.th-person').count(),1);await page.screenshot({path:path.join(output,`followers-${width}.png`)});checks.push(`${width}: own profile displays actual fan count and follower list supports follow-back`);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.waitForFunction(()=>document.querySelector('[aria-label="我的关注列表"] strong')?.textContent==='1');await page.getByLabel('我的关注列表',{exact:true}).click();await page.getByLabel('查看 私信同学乙'+width+' 的主页',{exact:true}).click();await page.getByRole('button',{name:'发私信',exact:true}).click();await page.getByLabel('私信内容',{exact:true}).waitFor();await page.waitForFunction(()=>!document.querySelector('.dm-state'));
  a.state.dropMessage=true;await page.getByLabel('私信内容',{exact:true}).fill('合成私信 <script>不会执行</script>');await page.getByLabel('发送私信',{exact:true}).click();await page.getByLabel('重试发送私信',{exact:true}).waitFor();assert.equal(await page.getByLabel('私信内容',{exact:true}).inputValue(),'合成私信 <script>不会执行</script>');await page.getByLabel('重试发送私信',{exact:true}).click();await page.locator('.dm-message').waitFor();assert.equal(await page.locator('.dm-message').count(),1);assert.equal(await page.locator('.dm-message p').innerText(),'合成私信 <script>不会执行</script>');checks.push(`${width}: committed send with lost response retries idempotently and displays text literally`);
  await page.getByLabel('私信内容',{exact:true}).fill('尚未发出的文字');await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'发私信',exact:true}).click();await page.getByLabel('私信内容',{exact:true}).waitFor();assert.equal(await page.getByLabel('私信内容',{exact:true}).inputValue(),'尚未发出的文字');checks.push(`${width}: private draft survives returning to public profile and reopening the same conversation`);
  await b.page.getByLabel('互动消息',{exact:true}).click();await b.page.getByRole('button',{name:/^私信/}).click();await b.page.locator('.dm-thread').waitFor();assert.equal(await b.page.locator('.dm-thread b').innerText(),'1');await b.page.locator('.dm-thread').click();await b.page.locator('.dm-message').waitFor();await b.page.waitForFunction(()=>!document.querySelector('.dm-state'));
  await b.page.getByLabel('私信内容',{exact:true}).fill('收到啦');await b.page.getByLabel('发送私信',{exact:true}).click();await b.page.waitForFunction(()=>document.querySelectorAll('.dm-message').length===2);await page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await page.waitForFunction(()=>document.querySelectorAll('.dm-message').length===2);checks.push(`${width}: second account sees inbox unread count, reads and replies with application refresh`);
  const threadId=(await api.execute('messages.inbox',{},a.state.token)).conversations[0].id;
  await db.exec('DELETE FROM hyt_community_rate');
  for(let i=0;i<65;i++)await db.query("INSERT INTO hyt_dm_messages(thread_id,sender_id,body,request_id) VALUES($1,(SELECT high_id FROM hyt_dm_threads WHERE id=$1),$2,$3)",[threadId,'合成历史 '+i,crypto.randomUUID()]);
  await db.query('UPDATE hyt_dm_threads SET last_seq=(SELECT max(seq) FROM hyt_dm_messages WHERE thread_id=$1) WHERE id=$1',[threadId]);
  await page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await page.waitForFunction(()=>document.querySelectorAll('.dm-message').length===67);assert.equal(await page.locator('.dm-message').count(),67);checks.push(`${width}: incremental refresh drains multiple pages without skipping messages`);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'发私信',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.dm-message').length===30);await page.getByRole('button',{name:'查看更早消息',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.dm-message').length===60);await page.getByRole('button',{name:'查看更早消息',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('.dm-message').length===67);checks.push(`${width}: reopening conversation loads latest page and older-page actions retain the full history`);
  await page.setViewportSize({width,height:500});await page.waitForTimeout(150);const send=await page.getByLabel('发送私信',{exact:true}).boundingBox();assert(send.y>=0&&send.y+send.height<=500);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.screenshot({path:path.join(output,`chat-${width}.png`)});await page.setViewportSize({width,height:844});checks.push(`${width}: short viewport keeps composer and send button accessible without overflow`);
  await b.page.getByLabel('屏蔽私信对象',{exact:true}).click();await b.page.getByRole('button',{name:'确认屏蔽',exact:true}).click();await b.page.getByText('已屏蔽对方，双方私信与关注关系已隐藏。',{exact:true}).waitFor();assert(await b.page.getByLabel('私信内容',{exact:true}).isDisabled());await page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));await page.waitForFunction(()=>document.querySelector('.dm-composer textarea')?.disabled);checks.push(`${width}: block stops both directions and prevents composing after permission loss`);
  await b.page.getByRole('button',{name:'返回社区',exact:true}).click();await b.page.locator('.dm-empty').waitFor();assert.match(await b.page.locator('.dm-empty').innerText(),/还没有私信/);assert.equal(await b.page.locator('.dm-thread').count(),0);
  await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.getByRole('button',{name:'返回社区',exact:true}).click();await page.locator('.th-self').waitFor();a.state.legacyConfig=true;await page.reload();await page.locator('.th-self').click();assert.equal(await page.getByLabel('我的粉丝列表',{exact:true}).count(),0);assert.equal(await page.getByLabel('我的私信',{exact:true}).count(),0);checks.push(`${width}: old server capabilities hide unsupported fan stats and messaging controls`);
  assert.deepEqual(a.errors,[]);assert.deepEqual(b.errors,[]);await a.context.close();await b.context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({checks,passed:checks.length},null,2));console.log(JSON.stringify({passed:checks.length,output}));
}catch(error){if(active&&!active.isClosed())await active.screenshot({path:path.join(output,'failure.png')});throw error;}
finally{await browser.close();await new Promise(r=>server.close(r));await new Promise(r=>backend.close(r));await db.close();}
