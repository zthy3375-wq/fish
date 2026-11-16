/** Record the real component preview with synthetic local content. */
import {chromium} from 'playwright';
import {mkdir,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const directory='/tmp/handan-community-v8-preview';await mkdir(directory,{recursive:true});
const browser=await chromium.launch({args:['--no-sandbox']});
const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,deviceScaleFactor:2,recordVideo:{dir:directory,size:{width:390,height:844}}});
const page=await context.newPage(),errors=[],requests=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(/^https?:/.test(r.url()))requests.push(r.url());});
page.setDefaultTimeout(10000);
try{
 await page.goto(pathToFileURL(process.argv[2]).href);await page.locator('.th-post').first().waitFor();await page.waitForTimeout(600);
 await page.screenshot({path:directory+'/feed.png'});
 // Native touch taps, rather than dispatching click handlers.
 const card=page.locator('.th-post').first();await card.locator('.th-post-body').tap();await page.locator('.th-comment-loading').waitFor();await page.locator('.th-comment').first().waitFor();await page.waitForTimeout(500);
 await page.screenshot({path:directory+'/detail.png'});await page.locator('.th-detail .th-images button').tap();await page.locator('.th-gallery').waitFor();await page.waitForTimeout(600);await page.getByRole('button',{name:'关闭大图'}).tap();await page.locator('.th-gallery').waitFor({state:'detached'});
 await page.locator('.th-detail-tabs').getByRole('button',{name:'评论',exact:true}).tap();await page.waitForTimeout(550);await page.screenshot({path:directory+'/comments.png'});
 await page.locator('.th-readbar').getByRole('button',{name:'点赞',exact:true}).tap();await page.waitForTimeout(300);
 await page.locator('.th-comment').first().getByRole('button',{name:'回复',exact:true}).tap();await page.getByLabel('你的回复',{exact:true}).fill('下次一起去看看，慢慢发现校园里的小美好。');await page.waitForTimeout(400);await page.screenshot({path:directory+'/reply.png'});await page.getByRole('button',{name:'发布回复',exact:true}).tap();await page.waitForTimeout(800);
 await page.getByRole('button',{name:'返回社区',exact:true}).tap();await page.locator('.th-post').first().waitFor();await page.waitForTimeout(450);
 await page.getByRole('button',{name:'发帖',exact:true}).tap();await page.getByLabel('帖子标题').fill('记录今天的小确幸');await page.getByLabel('想说的话').fill('早八路上遇到了很好看的阳光，想把这一刻分享给大家。');await page.getByRole('checkbox',{name:'匿名发布',exact:true}).check();await page.waitForTimeout(400);await page.screenshot({path:directory+'/compose.png'});
 await page.getByRole('button',{name:'匿名发布',exact:true}).tap();await page.locator('.th-detail').waitFor();await page.waitForTimeout(600);assert.equal(await page.locator('.th-detail h2').innerText(),'记录今天的小确幸');
 assert.deepEqual(errors,[]);assert.deepEqual(requests,[]);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 const video=page.video();await context.close();await writeFile(directory+'/recording.json',JSON.stringify({video:await video.path(),errors,externalRequests:requests,checks:['touch body opens cached detail','gallery','comments','reply','like','back','anonymous compose'],source:'real Vue components, offline synthetic adapter'},null,2));console.log(await video.path());
}catch(e){await page.screenshot({path:directory+'/failure.png'});console.error(errors);throw e;}finally{await browser.close();}
