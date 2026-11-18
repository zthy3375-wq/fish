import {chromium} from 'playwright';
import {preview} from 'vite';
import {mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const dir='/tmp/eggs29-ui';await mkdir(dir,{recursive:true});
const server=await preview({preview:{host:'127.0.0.1',port:4195,strictPort:true}});
const browser=await chromium.launch();
try{
 const ctx=await browser.newContext({viewport:{width:390,height:844},reducedMotion:'reduce',serviceWorkers:'block'});
 const p=await ctx.newPage();p.setDefaultTimeout(10000);
 const errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.clock.setFixedTime(new Date('2026-11-18T04:00:00Z'));
 await p.goto('http://127.0.0.1:4195');
 const btn=(name)=>p.getByRole('button',{name,exact:true});
 const nav=name=>p.getByRole('navigation',{name:'主导航'}).getByRole('button',{name,exact:true});
 const stamp=code=>p.waitForFunction(k=>!!JSON.parse(localStorage.getItem('hyt-collection-v1:device')||'{}').stamps?.[k],code);
 await stamp('welcome');
 // Set up a personal course on Monday, then trigger via actual calendar controls.
 await p.evaluate(()=>new Promise((resolve,reject)=>{
   const req=indexedDB.open('handan-campus',1);
   req.onsuccess=()=>{const db=req.result,tx=db.transaction('schedule','readwrite'),store=tx.objectStore('schedule'),key='handan-campus.schedule.v1',get=store.get(key);
    get.onsuccess=()=>{const value=get.result;value.mode='personal';value.courses=[{id:'local-class',semesterId:value.activeSemesterId,name:'校园测试课',teacher:'',color:'blue',notes:'',arrangements:[{id:'local-slot',start:'08:00',end:'08:45',startPeriod:1,endPeriod:1,timeMode:'period',day:1,room:'',startWeek:1,endWeek:18,rule:'all',customWeeks:[]}]}];store.put(value,key);};
    tx.oncomplete=()=>{db.close();resolve()};tx.onerror=()=>reject(tx.error);
   };req.onerror=()=>reject(req.error);
 }));
 await p.reload();
 const fish=btn('首页小金鱼');await fish.waitFor();
 for(let n=0;n<5;n++)await fish.click();
 await stamp('puff');await p.waitForFunction(()=>document.querySelector('.discovery-moment')?.textContent.includes('咕噜'));await p.screenshot({path:dir+'/mascot.png'});
 const box=await fish.boundingBox();await p.mouse.move(box.x+box.width/2,box.y+box.height/2);await p.mouse.down();await stamp('dream');await p.mouse.up();
 await nav('课表').click();const weeks=p.getByLabel('跳转教学周',{exact:true});assert(Number(await weeks.inputValue())>1);
 await weeks.selectOption('1');await btn('回到本周').click();await stamp('timewalk');
 await btn('日视图').click();await p.locator('.week-days button').last().click();await stamp('freeday');
 await nav('待办').click();const empty=btn('清单里的小鱼');await empty.waitFor();await p.getByLabel('搜索任务').fill('不存在的任务');assert.equal(await empty.count(),0);
 await p.getByLabel('搜索任务').fill('');await empty.click();await stamp('emptyfish');
 await nav('首页').click();await p.locator('.life-services').getByRole('button',{name:/校园平面图/}).click();await btn('水边的小金鱼').click();await stamp('mapfish');
 for(const [campus,pixels] of [['西',864],['东',709],['西',864]]){
   await btn(campus+'校区平面图').click();
   await p.waitForFunction(w=>document.querySelector('.leaflet-image-layer')?.naturalWidth===w,pixels);
   const image=p.locator('.leaflet-image-layer');const before=await image.evaluate(el=>el.getBoundingClientRect().width);
   await p.locator('.leaflet-control-zoom-in').click();
   await p.waitForFunction(w=>document.querySelector('.leaflet-image-layer').getBoundingClientRect().width>w,before);
   await btn('显示全图').click();
 }
 console.log('PASS repeated campus switches, zoom and fit bounds');await btn('关闭').click();
 await nav('我的').click();await btn('关于邯院通').click();
 const version=p.locator('.about-version');for(let n=0;n<7;n++)await version.click();await stamp('goldfish');
 await btn('更新日志').click();const pages=p.locator('.release-pages'),end=p.locator('.colophon');assert(await end.isDisabled());await pages.evaluate(e=>e.scrollTo(0,e.scrollHeight));await end.click();await stamp('lastline');await btn('关闭').click();
 await p.locator('.collection-entry').click();await btn('隐藏').click();assert.equal(await p.locator('.cabinet-grid .unlocked').count(),8);
 await p.locator('[data-code=dream]').click();await p.getByRole('dialog').getByText('嘘，它梦见了一片没有尽头的海。').waitFor();await p.keyboard.press('Escape');
 await p.waitForFunction(()=>!document.querySelector('.unlock-toast'),undefined,{timeout:50000});await p.screenshot({path:dir+'/all-eight.png'});
 assert.deepEqual(errors,[]);console.log('PASS all eight from actual controls, false empty filter, gesture ordering and details');await ctx.close();
}finally{await browser.close();await new Promise(r=>server.httpServer.close(r));}
