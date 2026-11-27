import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {once} from 'node:events';
import path from 'node:path';
import {chromium} from 'playwright';
import {fixture} from '../cloudbase/tests/fixtures/commerce.mjs';

const f=await fixture();
const browser=await chromium.launch({args:['--no-sandbox'],executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||undefined});
const web=spawn(process.execPath,['node_modules/vite/bin/vite.js','--config','merchant/vite.config.ts','--host','127.0.0.1','--port','4173','--strictPort'],{
 env:{...process.env,VITE_COMMERCE_API:f.base},stdio:['ignore','pipe','inherit'],
});
const root=path.resolve('dist');
const staticServer=createServer(async(req,res)=>{
 try{
  const route=new URL(req.url,'http://localhost').pathname;
  const name=path.resolve(root,'.'+(route==='/'?'/index.html':route));
  if(!name.startsWith(root+'/'))throw Error('outside assets');
  const mime={'.js':'text/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp'};
  res.setHeader('Content-Type',mime[path.extname(name)]||'application/octet-stream');res.end(await readFile(name));
 }catch{res.writeHead(404);res.end();}
});
staticServer.listen(0,'127.0.0.1');await once(staticServer,'listening');
const appOrigin='http://127.0.0.1:'+staticServer.address().port;
const webOrigin='http://127.0.0.1:4173';

async function signIn(page,username){
 await page.goto(webOrigin);
 await page.getByLabel('账号',{exact:true}).fill(username);
 await page.getByLabel('密码',{exact:true}).fill(f.password);
 await page.getByRole('button',{name:'登录',exact:true}).click();
}
async function ready(locator){await locator.waitFor({state:'visible'});}
async function bridge(context){
 await context.exposeBinding('__commerceNative',async(_,action,body)=>{
  if(!action.startsWith('commerce.'))return {};
  const result=await f.call(action.slice(9),body,'student');
  if(result.status!==200)return {error:result.error};
  return result;
 });
 await context.addInitScript(()=>{
  const methods={Treehole:['request','cachedHall','journalRead','journalWrite'],Preferences:['get','set','remove'],
   App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
  window.androidBridge={};
  window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:'promise'}))})),
   nativePromise:async(plugin,method,body)=>{
    if(plugin==='Treehole'&&method==='request'){
     const result=await window.__commerceNative(body.action,body.body);
     if(result.error)throw Error(result.error);
     return result;
    }
    if(plugin==='Preferences'&&method==='get')return {value:null};
    return {};
   }};
 });
}

try{
 await Promise.race([new Promise(resolve=>web.stdout.on('data',chunk=>{if(String(chunk).includes('127.0.0.1:4173'))resolve();})),once(web,'exit').then(()=>{throw Error('merchant server stopped');})]);
 const {shop}=await f.enroll('merchant');
 const offer=(await f.okay('merchant.offer',{id:randomUUID(),title:'到店专属券',terms:'学生到店使用',quota:3,
  startsAt:new Date(Date.now()-60_000).toISOString(),endsAt:new Date(Date.now()+86400_000).toISOString()},'merchant')).id;
 const ad=await f.submitAd('merchant');
 const start=new Date(Date.now()-15*60_000).toISOString(),end=new Date(Date.now()+7200_000).toISOString();
 const contract=(await f.okay('admin.contract',{shopId:shop,plan:'home',kind:'trial',placements:['home','banner','category'],startsAt:start,reference:'浏览器验收试用合同'},'owner')).id;
 for(const placement of ['home','banner','category'])await f.okay('admin.schedule',{adId:ad,contractId:contract,placement,startsAt:start,endsAt:end},'owner');

 const admin=await browser.newPage({viewport:{width:1260,height:900}});
 await signIn(admin,'owner');
 await ready(admin.getByRole('heading',{name:'商家审核'}));
 await admin.getByRole('button',{name:'定价与权限'}).click();
 await admin.getByLabel('开启广告展示').check();
 await admin.getByLabel('操作说明',{exact:true}).last().fill('仅用于隔离浏览器验收');
 await admin.getByRole('button',{name:'保存开关'}).click();
 await ready(admin.getByText('操作已保存'));
 await f.okay('admin.student',{id:f.users.student.id,enabled:true,reason:'隔离学生资格核验'},'owner');
 const source=await browser.newContext({viewport:{width:390,height:844},serviceWorkers:'block'});
 await bridge(source);
 const app=await source.newPage();
 await app.goto(appOrigin);
 await ready(app.getByText('广告',{exact:true}));
 await app.getByRole('button',{name:/校园周边 门店与学生优惠/}).click();
 const panel=app.getByRole('dialog',{name:'校园周边'});
 await ready(panel.getByRole('heading',{name:'校园周边'}));
 await panel.getByRole('button',{name:/隔离门店 merchant/}).click();
 await ready(panel.getByRole('heading',{name:'隔离门店 merchant'}));
 await panel.getByRole('button',{name:'收藏门店'}).click();
 await ready(panel.getByRole('button',{name:'已收藏'}));
 await panel.getByRole('button',{name:'领取',exact:true}).click();
 await panel.getByRole('button',{name:'查看刚领取的优惠券'}).click();
 await ready(panel.getByRole('img',{name:'到店核销二维码'}));
 const wallet=(await f.okay('wallet',{},'student')).items;
 assert.equal(wallet[0].title,'到店专属券');
 assert.equal((await f.okay('claim',{id:offer},'student')).id,wallet[0].id);
 const code=wallet[0].code;

 const merchant=await browser.newPage({viewport:{width:390,height:844}});
 await signIn(merchant,'merchant');
 await ready(merchant.getByRole('heading',{name:'门店资料'}));
 assert.ok(await merchant.evaluate(()=>document.documentElement.scrollWidth <= innerWidth));
 await merchant.getByRole('button',{name:'核销台',exact:true}).click();
 const qr=await panel.getByRole('img',{name:'到店核销二维码'}).getAttribute('src');
 await merchant.evaluate(async source=>{
  const photo=new Image();photo.src=source;await photo.decode();
  const canvas=document.createElement('canvas');canvas.width=320;canvas.height=320;
  const ctx=canvas.getContext('2d');
  const draw=()=>{ctx.fillStyle='white';ctx.fillRect(0,0,320,320);ctx.drawImage(photo,40,40,240,240);};
  draw();const stream=canvas.captureStream(8);
  const timer=setInterval(draw,100);
  setTimeout(()=>clearInterval(timer),12000);
  Object.defineProperty(navigator.mediaDevices,'getUserMedia',{value:async()=>stream});
 },qr);
 await merchant.getByRole('button',{name:'扫码填入'}).click();
 await merchant.waitForFunction(expected=>document.querySelector('input[inputmode=numeric]')?.value===expected,code);
 await merchant.getByRole('button',{name:'确认核销'}).click();
 await ready(merchant.getByText(/已核销「到店专属券」/));
 await merchant.getByLabel('12 位核销码').fill(code);
 await merchant.getByRole('button',{name:'确认核销'}).click();
 await ready(merchant.getByText('这张优惠券已经核销'));
 assert.equal((await f.okay('coupon',{id:wallet[0].id},'student')).coupon.state,'used');
 await merchant.getByRole('button',{name:'推广报告'}).click();
 await ready(merchant.getByRole('heading',{name:'近 30 天推广统计'}));
 await admin.getByRole('button',{name:'广告排期'}).click();
 await ready(admin.getByRole('heading',{name:'商家福利 · 首页广告'}));
 await admin.getByRole('button',{name:'定价与权限'}).click();
 await admin.getByLabel('开启广告展示').uncheck();
 await admin.getByLabel('操作说明',{exact:true}).last().fill('关闭隔离验证广告');
 await admin.getByRole('button',{name:'保存开关'}).click();
 await ready(admin.getByText('操作已保存'));
 await app.reload();
 await ready(app.getByRole('button',{name:/校园周边 门店与学生优惠/}));
 assert.equal(await app.getByText('广告',{exact:true}).count(),0);
 console.log('Browser integration passed: Android web layer 390 px, merchant mobile 390 px, commercial management 1260 px, QR camera-frame decoding, real PostgreSQL and HTTP.');
}finally{
 await browser.close();web.kill();
 staticServer.close();await once(staticServer,'close');
 await f.close();
}
