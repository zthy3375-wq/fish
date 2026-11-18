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
  await p.goto('http://127.0.0.1:4192/#/profile');
  await p.getByRole('button',{name:/荣誉殿堂/}).click();
  await p.locator('[data-code=welcome].unlocked').waitFor();
  assert.equal(await p.locator('.cabinet-grid button').count(),25);
  await p.waitForFunction(()=>!document.querySelector('.unlock-toast'));
  await p.screenshot({path:output+'/global-'+width+'.png'});
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
