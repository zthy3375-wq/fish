import path from 'node:path';

export async function checkProfile(page,assert,{width,output}) {
 const profile=page.locator('.profile-page');
 const account=profile.locator('.school-connection');
 const summary=account.locator('.school-summary');
 assert(await summary.getAttribute('aria-expanded')==='false',`${width}: school account details collapsed by default`);
 assert(await account.evaluate(el=>el.getBoundingClientRect().height)<140,`${width}: school account stays compact`);
 assert(await profile.locator('.profile-academics .service-row').count()===4,`${width}: unified grades and study has one shortcut`);
 assert(await profile.locator('.school-module').first().isVisible()===false,`${width}: sync timestamps stay behind account details`);
 await summary.click();
 assert(await profile.getByRole('button',{name:'退出学校账号',exact:true}).isVisible(),`${width}: school logout remains accessible`);
 await summary.click();
 await page.locator('main').evaluate(el=>el.scrollTop=0);
 assert(await profile.locator('.avatar').innerText()===Array.from(await profile.locator('.profile-copy strong').innerText())[0],`${width}: avatar and visible identity agree`);
 await page.screenshot({path:path.join(output,`profile-top-${width}.png`)});
 const group=profile.getByRole('region',{name:'QQ 交流群',exact:true});
 await group.getByRole('button',{name:/加入 QQ 交流群/}).click();
 await group.getByRole('status').filter({hasText:'已请求打开 QQ'}).waitFor();
 await group.getByRole('button',{name:'复制群号',exact:true}).click();
 await group.getByRole('status').filter({hasText:'群号已复制'}).waitFor();
 assert(await page.evaluate(()=>window.__qqGroupCalls.join(',')==='open,copy'),`${width}: both overview actions call the matching native method once`);
 await page.getByRole('button',{name:'设置与帮助',exact:true}).click();
 await profile.locator('.profile-feedback>summary').click();
 await profile.getByRole('button',{name:/^导出并发送到 QQ/}).waitFor({state:'visible'});
 assert(await profile.getByRole('button',{name:/^导出并发送到 QQ/}).isVisible(),`${width}: feedback actions remain accessible on expansion`);
 await profile.locator('.profile-feedback>summary').click();
 assert(await profile.getByRole('region',{name:'QQ 交流群',exact:true}).count()===0,`${width}: settings contains no duplicate QQ entry`);
 await page.locator('main').evaluate(el=>el.scrollTop=el.scrollHeight);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${width}: profile has no horizontal overflow`);
 await page.screenshot({path:path.join(output,`profile-bottom-${width}.png`)});
 await page.getByRole('button',{name:'返回上一页',exact:true}).click();
 await profile.locator('.school-summary').waitFor();
}
