import {mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {registerTestAccount} from './community-test-account.mjs';
import {developerBinding} from './cloudbase/bind-developer.mjs';
export async function checkHonors({client,db,api,baseline}){
 const out='/tmp/eggs29-ui';await mkdir(out,{recursive:true});const {page,context,state}=await client(360);
 try{
 const name='邯院校园里认真记录生活的小金鱼';await registerTestAccount(page,'bylinefixture',name);
 const call=(a,b={})=>api.execute(a,b,state.token,'bylinefixture');const id=(await call('me')).user.id;
 await db.query("update hyt_members set role='moderator' where id=$1",[id]);await db.query("insert into hyt_moderation(moderator_id,action,reason) values($1,'grant_moderator','Initial moderator binding explicitly authorized by repository owner, 2026-11-16')",[id]);await db.exec(developerBinding(id));
 await call('honors.change',{operation:'grant',memberId:id,kind:'seed',reason:'隔离测试',requestId:randomUUID()});await call('honors.wear',{honor:'seed',showcase:[]});
 const post=(await call('posts.create',{requestId:randomUUID(),body:'雨后在西区拍到了晚霞。',anonymous:false})).post;
 const add=(body,extra={})=>call('comments.create',{postId:post.id,body,anonymous:false,requestId:randomUUID(),...extra});
 const root=(await add('图书馆这边也看到了。')).comment;await add('今天的颜色确实很特别。',{replyTo:root.id});await add('我也在校园里散步。',{anonymous:true});
 await page.reload();const card=page.locator('[data-post-id="'+post.id+'"]').first();await card.waitFor();
 const label=baseline?'before':'after';
 for(const width of [320,360,430]){
  await page.setViewportSize({width,height:844});await card.locator('.hyt-badge').first().waitFor();assert.equal(await card.locator('.hyt-badge').count(),2);
  if(!baseline){assert.equal(await card.locator('.th-owner').count(),0);assert.equal(await card.locator('.honor-byline .hyt-badge').count(),2);assert(await card.locator('.hyt-badge').first().evaluate(e=>getComputedStyle(e).backgroundColor==='rgba(0, 0, 0, 0)'));assert(await card.evaluate(e=>e.scrollWidth<=e.clientWidth+1));}
  await card.screenshot({path:out+'/'+label+'-post-'+width+'.png'});
 }
 await page.setViewportSize({width:360,height:844});await card.locator('.th-post-body').click();await page.locator('.th-detail').waitFor();
 await page.locator('.th-nested-reply').first().waitFor();
 if(!baseline){
  const comment=page.locator('.th-comment').filter({has:page.locator('.th-comment-body',{hasText:'图书馆这边也看到了。'})});
  assert.equal(await comment.locator('header .hyt-badge').count(),2);assert.equal(await comment.locator('.th-nested-byline .hyt-badge').count(),2);
  assert.equal(await page.locator('.th-comment').filter({has:page.locator('.th-comment-body',{hasText:'我也在校园里散步。'})}).locator('.hyt-badge').count(),0);
 }
 const thread=page.locator('.th-comment').filter({has:page.locator('.th-comment-body',{hasText:'图书馆这边也看到了。'})});
 await thread.screenshot({path:out+'/'+label+'-thread.png'});
 if(!baseline){
 await page.evaluate(()=>document.documentElement.dataset.theme='dark');await thread.screenshot({path:out+'/after-thread-dark.png'});
 await thread.locator('header').getByRole('button',{name:'种子用户'}).click();await page.getByRole('dialog',{name:'种子用户'}).getByText(/获得日期/).waitFor();
 }console.log('PASS identical long nickname, fallback avatar, public and anonymous comments at 320/360/430px: '+label);
 }finally{await context.close();}
}
