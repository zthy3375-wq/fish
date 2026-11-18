import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
import path from 'node:path';
import {registerTestAccount} from './community-test-account.mjs';
import {developerBinding} from './cloudbase/bind-developer.mjs';

export async function checkHonors({client,db,api,baseline,output}){
 await mkdir(output,{recursive:true});
 for(const width of [360,390,430]){
  const {page,context,state,errors}=await client(width);
  try{
   const name='画廊同学'+width;
   await registerTestAccount(page,'gallery'+width,name);
   const call=(a,b={})=>api.execute(a,b,state.token,'gallery');
   const member=(await call('me')).user;
   if(!baseline){
    const ownerExists=(await db.query("select id from hyt_members where developer_since is not null")).rows[0];
    if(!ownerExists){
     await db.query("update hyt_members set role='moderator' where id=$1",[member.id]);
     await db.query("insert into hyt_moderation(moderator_id,action,reason) values($1,'grant_moderator','Initial moderator binding explicitly authorized by repository owner, 2026-11-16')",[member.id]);
     await db.exec(developerBinding(member.id));
    }
    await call('posts.create',{requestId:randomUUID(),body:'分享一张邯院的秋天',anonymous:false});
    if(!ownerExists)await call('honors.change',{operation:'grant',memberId:member.id,kind:'seed',reason:'参与社区内测',requestId:randomUUID()});
    await page.reload();await page.locator('.th-nav .th-self:not([disabled])').waitFor();
    await page.locator('.unlock-toast').first().waitFor();
    await page.waitForTimeout(450);await page.screenshot({path:path.join(output,'notice-'+width+'.png')});
    await page.waitForFunction(()=>!document.querySelector('.unlock-toast'),undefined,{timeout:12000});
    await page.getByRole('button',{name:/查看 .*的主页/}).first().click();
    const publicButton=page.locator('button.hon-hall-link');await publicButton.waitFor();
    await page.getByRole('button',{name:'返回社区',exact:true}).click();
   }
   await page.locator('.th-nav .th-self:not([disabled])').click();
   await page.locator('.th-profile').waitFor();await page.waitForTimeout(350);
   await page.screenshot({animations:'disabled',path:path.join(output,(baseline?'before-profile-':'after-profile-')+width+'.png')});
   if(baseline)continue;
   await page.locator('.th-profile-shortcuts button').filter({hasText:'荣誉殿堂'}).click();
   await page.locator('.hon-grid').waitFor();await page.getByRole('button',{name:'第一声',exact:true}).click();
   await page.getByRole('button',{name:/展示到主页/}).click();await page.getByRole('button',{name:/从主页取下/}).waitFor();
   await page.locator('.hon-page').screenshot({animations:'disabled',path:path.join(output,'hall-'+width+'.png')});
   assert.equal(await page.locator('.hon-grid button').count(),10);
   assert.equal(await page.locator('.hon-page').evaluate(el=>el.scrollWidth<=el.clientWidth+1),true);
   await page.getByRole('button',{name:'稀有',exact:true}).click();assert.equal(await page.locator('.hon-grid button').count(),4);
   await page.getByRole('button',{name:'已解锁',exact:true}).click();assert.equal(await page.locator('.hon-grid button').count(),2);
   await page.getByText('特别收藏 · 待开放',{exact:true}).click();await page.getByText('邯院传说',{exact:true}).waitFor();
   if(width===360){
    await page.locator('.hon-page').getByRole('button',{name:'开发者',exact:true}).click();
    await page.getByRole('dialog').waitFor();await page.getByRole('button',{name:'完成',exact:true}).click();
    await page.getByRole('button',{name:'返回社区',exact:true}).click();
    await page.getByRole('button',{name:/身份与荣誉管理/}).click();
    await page.getByRole('button',{name:/画廊同学360/}).click();await page.getByText('操作理由',{exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'admin-360.png')});
   }
   assert.deepEqual(errors,[]);
  }finally{await context.close();}
 }
 console.log(baseline?'Previous profile captured at 360, 390, 430px':'PASS phone gallery, profile, badge detail, live toast, showcase and moderator interface at 360, 390, 430px');
}
