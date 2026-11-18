import {chromium} from '@playwright/test';
import {preview} from 'vite';
import {mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const output='/tmp/hyt-honors-ui';
await mkdir(output,{recursive:true});
const server=await preview({preview:{host:'127.0.0.1',port:4192,strictPort:true}});
const browser=await chromium.launch();
try{
 for(const width of [360,390,430]){
  const ctx=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block',reducedMotion:'reduce'});
  const p=await ctx.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
  await p.goto('http://127.0.0.1:4192/');
  for(const name of ['趣智校园','胖乖生活','校园平面图']){
   await p.locator('.life-services').getByRole('button',{name:new RegExp(name)}).click();
   if(name==='校园平面图')await p.waitForFunction(()=>document.querySelector('.leaflet-image-layer')?.naturalWidth>0);
   else await p.getByRole('heading',{name,exact:true}).waitFor();
   await p.getByRole('button',{name:'关闭',exact:true}).click();
  }
  await p.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'我的',exact:true}).click();
  await p.getByRole('button',{name:/荣誉殿堂/}).click();
  await p.locator('[data-code=welcome].unlocked').waitFor();
  assert.equal(await p.locator('.cabinet-grid button').count(),25);
  await p.locator('[data-code=life].unlocked').waitFor();
  await p.waitForFunction(()=>!document.querySelector('.unlock-toast'),undefined,{timeout:30000});
  await p.screenshot({path:output+'/global-'+width+'.png'});
  // Android queues the old dialog's close event until the next frame.
  // Reopen immediately and deliver that stale event while the second medal is on screen.
  await p.locator('[data-code=welcome]').click();
  await p.evaluate(()=>{
   document.querySelector('.detail-close').click();
   document.querySelector('[data-code=bath]').click();
  });
  await p.getByRole('dialog').getByRole('heading',{name:'洗去疲惫'}).waitFor();
  await p.locator('dialog.collect-detail').dispatchEvent('close');
  await p.getByRole('dialog').getByRole('button',{name:/展示到我的页面/}).waitFor();
  await p.keyboard.press('Escape');
  await p.getByRole('button',{name:'隐藏',exact:true}).click();
  await p.getByRole('button',{name:/未知奇遇/}).click();
  assert.equal(await p.getByRole('dialog').getByText('获取条件').count(),0);
  await p.keyboard.press('Escape');
  await p.getByRole('button',{name:'初识',exact:true}).click();
  await p.locator('[data-code=welcome]').click();await p.getByRole('button',{name:/展示到我的页面/}).click();
  await p.getByRole('button',{name:/取下/}).waitFor();await p.screenshot({path:output+'/global-detail-'+width+'.png'});
  await p.keyboard.press('Escape');await p.getByRole('button',{name:'返回上一页'}).click();
  await p.locator('.private-shelf').waitFor();
  await p.reload();await p.locator('.private-shelf').waitFor();
  await p.getByRole('button',{name:/荣誉殿堂/}).click();await ctx.setOffline(true);await p.locator('[data-code=welcome].unlocked').waitFor();
  assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.deepEqual(errors,[]);
  await ctx.close();
 }
 console.log('PASS collection, independent profile entry, hidden details, pin persistence and offline display at 360/390/430px');
}finally{await browser.close();await new Promise(r=>server.httpServer.close(r));}
