import path from 'node:path';

export async function checkProfile(page,assert,{width,output}) {
 const profile=page.locator('.profile-page');
 const account=profile.locator('.school-connection');
 const details=account.locator('.school-account-details');
 assert(await details.getAttribute('open')===null,`${width}: school account details collapsed by default`);
 assert(await account.evaluate(el=>el.getBoundingClientRect().height)<140,`${width}: school account stays compact`);
 assert(await profile.locator('.profile-academics .service-row').count()===3,`${width}: unified grades and study has one shortcut`);
 assert(await profile.locator('.school-module').first().isVisible()===false,`${width}: sync timestamps stay behind account details`);
 await profile.locator('.school-account-details>summary').click();
 assert(await profile.getByRole('button',{name:'退出学校账号',exact:true}).isVisible(),`${width}: school logout remains accessible`);
 await profile.locator('.school-account-details>summary').click();
 await page.locator('main').evaluate(el=>el.scrollTop=0);
 await page.screenshot({path:path.join(output,`profile-top-${width}.png`)});
 await profile.locator('.profile-feedback>summary').click();
 await profile.getByRole('button',{name:/^导出并发送到 QQ/}).waitFor({state:'visible'});
 assert(await profile.getByRole('button',{name:/^导出并发送到 QQ/}).isVisible(),`${width}: feedback actions remain accessible on expansion`);
 await profile.locator('.profile-feedback>summary').click();
 assert(await profile.getByRole('button',{name:'复制群号',exact:true}).count()===1,`${width}: group copy remains available`);
 await page.locator('main').evaluate(el=>el.scrollTop=el.scrollHeight);
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`${width}: profile has no horizontal overflow`);
 await page.screenshot({path:path.join(output,`profile-bottom-${width}.png`)});
 await page.locator('main').evaluate(el=>el.scrollTop=0);
}
