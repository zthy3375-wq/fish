/** Actual PostgreSQL + HTTP + UI integration; only the native bridge/storage is adapted. */
import {createServer as staticServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {chromium} from 'playwright';
import {createCommunity} from '../cloudbase/functions/community/core.mjs';
import {createServer} from '../cloudbase/functions/community/server.mjs';

const root=path.resolve('dist'),output='/tmp/handan-treehole-qa';await mkdir(output,{recursive:true});
const db=new PGlite();await db.exec(await readFile('cloudbase/community-schema.sql','utf8'));
const api=createCommunity({registrationEnabled:true,db:async(a,b,t)=>(await db.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t])).rows[0].result});
const backend=createServer(api);await new Promise(r=>backend.listen(0,'127.0.0.1',r));
const endpoint=`http://127.0.0.1:${backend.address().port}`;
const server=staticServer(async(req,res)=>{try{
 const name=new URL(req.url,'http://localhost').pathname;const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));
 if(!file.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.webp':'image/webp'})[path.extname(file)]||'application/octet-stream');res.end(await readFile(file));
}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}/#/community`;
const browser=await chromium.launch({args:['--no-sandbox'],executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||undefined});
const checks=[];let active;
async function client(width){
 const context=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});
 const state={token:null,dropNextPost:false,publicResponses:[]};
 await context.exposeBinding('__treeholeNative',async(_,options)=>{
  const {action,body}=options;const headers={'Content-Type':'application/json'};
  if(state.token)headers.Authorization='Bearer '+state.token;
  const result=await fetch(endpoint+'/v1/'+action,{method:action==='config'?'GET':'POST',headers,...(action==='config'?{}:{body:JSON.stringify(body)})});
  const json=await result.json();if(!result.ok)return {error:json.error};
  if(json.sessionToken){state.token=json.sessionToken;delete json.sessionToken;}
  if(action==='logout'||action==='account.delete')state.token=null;
  if(action.startsWith('posts.')||action.startsWith('comments.'))state.publicResponses.push(json);
  if(action==='posts.create'&&state.dropNextPost){state.dropNextPost=false;return {error:'network_unavailable'};}
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
 await page.getByRole('button',{name:'我已保存恢复码'}).click();await page.getByRole('heading',{name:'邯院树洞',exact:true}).waitFor();
}
try{
 for(const width of [360,390,430]){
  const a=await client(width);await register(a.page,'author_'+width,'测试同学甲');
  await a.page.getByRole('button',{name:'发帖',exact:true}).click();await a.page.getByLabel('想说的话').fill('今天图书馆靠窗的位置很安静。下课后，给自己一点慢下来的时间。');
  await a.page.getByRole('checkbox',{name:'匿名发布',exact:true}).check();a.state.dropNextPost=true;
  await a.page.getByRole('button',{name:'匿名发布',exact:true}).click();await a.page.getByRole('alert').filter({hasText:'连接失败'}).waitFor();
  assert.equal(await a.page.getByLabel('想说的话').inputValue(),'今天图书馆靠窗的位置很安静。下课后，给自己一点慢下来的时间。');
  await a.page.getByRole('button',{name:'匿名发布',exact:true}).click();await a.page.getByRole('heading',{name:'聊一聊',exact:true}).waitFor();
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_posts')).rows[0].n,(checks.length/7)+1);
  checks.push(`${width}: lost response preserves draft and retry creates one post`);
  const locked=a.page.getByRole('checkbox',{name:'保持楼主匿名身份'});assert(await locked.isChecked());assert(await locked.isDisabled());
  await a.page.getByLabel('你的回复',{exact:true}).fill('这是楼主自己的回复。');await a.page.getByRole('button',{name:'发布回复',exact:true}).click();await a.page.getByText('这是楼主自己的回复。',{exact:true}).waitFor();
  assert.equal(await a.page.locator('.th-comment strong em').first().innerText(),'楼主');checks.push(`${width}: anonymous author replies retain alias`);
  await a.page.getByRole('button',{name:'返回树洞',exact:true}).click();await a.page.getByRole('heading',{name:'邯院树洞',exact:true}).waitFor();
  await a.page.screenshot({path:path.join(output,`treehole-feed-${width}.png`),animations:'disabled'});
  assert.equal(await a.page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);checks.push(`${width}: compact feed has no horizontal overflow`);
  const b=await client(width);await register(b.page,'reader_'+width,'测试同学乙');
  await b.page.locator('.th-post-body').first().click();await b.page.getByRole('heading',{name:'聊一聊',exact:true}).waitFor();
  const viewer=b.state.publicResponses.at(-1);assert(!JSON.stringify(viewer).includes('测试同学甲'));assert(!JSON.stringify(viewer).includes('author_'+width));
  assert.equal(await b.page.getByRole('checkbox',{name:'匿名回复',exact:true}).isDisabled(),false);checks.push(`${width}: second account sees anonymous projections without account identity`);
  await b.page.getByLabel('你的回复',{exact:true}).fill('今天也要好好休息呀。');await b.page.getByRole('button',{name:'发布回复',exact:true}).click();await b.page.getByText('今天也要好好休息呀。',{exact:true}).waitFor();
  await b.page.getByRole('button',{name:'帖子操作'}).click();await b.page.getByRole('button',{name:'举报',exact:true}).click();
  await b.page.getByLabel('原因',{exact:true}).fill('人工测试举报');await b.page.getByRole('button',{name:'提交举报',exact:true}).click();await b.page.getByText('举报已提交，管理员会查看处理',{exact:true}).waitFor();checks.push(`${width}: named comments and reporting work across accounts`);
  await b.page.getByRole('button',{name:'返回树洞',exact:true}).click();await b.page.getByRole('button',{name:'测试同学乙',exact:true}).click();
  await b.page.getByRole('button',{name:'退出邯院通账号',exact:true}).click();await b.page.getByRole('button',{name:'确认',exact:true}).click();await b.page.getByRole('heading',{name:'说说校园里的那些事'}).waitFor();
  assert.equal(b.state.token,null);assert.equal(await b.page.locator('.th-post').count(),0);checks.push(`${width}: logout clears content and session`);
  await a.page.getByRole('button',{name:'发帖',exact:true}).click();await a.page.getByLabel('想说的话').fill('还没写完的草稿');await a.page.getByRole('button',{name:'返回树洞',exact:true}).click();
  await a.page.getByRole('heading',{name:'放弃还没发布的文字？'}).waitFor();await a.page.getByRole('button',{name:'继续编辑',exact:true}).click();assert.equal(await a.page.getByLabel('想说的话').inputValue(),'还没写完的草稿');checks.push(`${width}: back navigation protects unpublished text`);
  assert.deepEqual(a.errors,[]);assert.deepEqual(b.errors,[]);
  await a.context.close();await b.context.close();
 }
 await writeFile(path.join(output,'checks.json'),JSON.stringify({backend:'actual PostgreSQL (PGlite), HTTP service',bridge:'test-only native adapter',checks},null,2));
 console.log(JSON.stringify({passed:checks.length,output}));
}catch(error){if(active&&!active.isClosed())await active.screenshot({path:path.join(output,'failure.png')});throw error;}
finally{await browser.close();await new Promise(r=>server.close(r));await new Promise(r=>backend.close(r));await db.close();}
