import {chromium} from 'playwright';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const browser=await chromium.launch({args:['--no-sandbox']}),checks=[];
try{
 for(const width of [360,390,430]){
  const context=await browser.newContext({viewport:{width,height:844},hasTouch:true});const page=await context.newPage();await page.goto(pathToFileURL(process.argv[2]).href);await page.locator('.th-post').first().waitFor();
  const four=page.locator('.th-post').filter({hasText:'第一次做校园项目'});assert.equal(await four.locator('.th-images button').count(),4);assert.equal(await four.locator('.th-images').evaluate(el=>getComputedStyle(el).gridTemplateColumns.split(' ').length),2);checks.push(`${width}: four images use a two by two grid`);
  const first=page.locator('.th-post').first();await first.getByRole('button',{name:'抱抱',exact:true}).tap();await page.waitForFunction(()=>document.querySelector('.th-responses button[aria-label="抱抱"]')?.getAttribute('aria-pressed')==='true');assert.equal(await page.locator('.th-detail').count(),0);await first.getByRole('button',{name:'抱抱',exact:true}).tap();await page.waitForFunction(()=>!document.querySelector('.th-responses button[aria-pressed="true"]'));checks.push(`${width}: real touch response selects and cancels without opening the post`);
  const cdp=await context.newCDPSession(page);
  async function swipe(from,to){await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[from]});for(let i=1;i<=8;i++){await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:from.x+(to.x-from.x)*i/8,y:from.y+(to.y-from.y)*i/8}]});await page.waitForTimeout(20);}await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await page.waitForTimeout(300);}
  await swipe({x:10,y:550},{x:10,y:270});assert.equal(await page.locator('.th-detail').count(),0);assert(await page.evaluate(()=>scrollY)>0);checks.push(`${width}: actual touch scrolling does not open a card`);
  await page.evaluate(()=>scrollTo(0,0));await page.locator('.th-post-body').first().tap();await page.locator('.th-detail').waitFor();await page.waitForTimeout(700);await swipe({x:8,y:240},{x:160,y:242});await page.locator('.th-post').first().waitFor();checks.push(`${width}: edge swipe returns from detail`);
  await page.getByRole('button',{name:'发帖',exact:true}).tap();const fixture=await readFile('public/art/campus-autumn.webp');await page.getByLabel('添加图片').setInputFiles([{name:'one.webp',mimeType:'image/webp',buffer:fixture},{name:'two.webp',mimeType:'image/webp',buffer:fixture}]);await page.locator('.th-draft-images>div').nth(1).waitFor();
  await page.getByRole('button',{name:'调整图片 1 顺序',exact:true}).tap();await page.getByRole('button',{name:'后移',exact:true}).tap();assert.equal(await page.getByRole('button',{name:'调整图片 2 顺序',exact:true}).getAttribute('aria-pressed'),'true');assert(await page.getByRole('button',{name:'后移',exact:true}).isDisabled());
  await page.getByRole('button',{name:'前移',exact:true}).tap();assert.equal(await page.getByRole('button',{name:'调整图片 1 顺序',exact:true}).getAttribute('aria-pressed'),'true');await page.getByRole('button',{name:'移除图片 2',exact:true}).tap();assert.equal(await page.locator('.th-draft-images>div').count(),1);checks.push(`${width}: selected image moves forward/back and remove preserves remaining image`);
  await page.getByLabel('想说的话').fill('图片排序后的草稿');await page.getByRole('button',{name:'返回社区',exact:true}).tap();await page.getByRole('button',{name:'保存草稿并返回',exact:true}).tap();await page.locator('.th-draft-resume').waitFor();await page.reload();await page.locator('.th-draft-resume').tap();assert.equal(await page.locator('.th-draft-images>div').count(),1);assert.equal(await page.getByLabel('想说的话').inputValue(),'图片排序后的草稿');checks.push(`${width}: reordered image draft survives reload`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await context.close();
 }
 await writeFile('/tmp/handan-community-v8-preview/touch-checks.json',JSON.stringify({passed:checks.length,checks},null,2));console.log(JSON.stringify({passed:checks.length}));
}finally{await browser.close();}
