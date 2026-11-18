import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../functions/community/core.mjs';
import {developerBinding} from '../../scripts/cloudbase/bind-developer.mjs';
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
let db,api,owner,moderator,alice,bob,other;
const call=(u,a,b={})=>api.execute(a,b,u.sessionToken,'qa');
const reg=name=>api.execute('register',{username:name,nickname:name,password:'test-long-password',agreed:true,role:'developer',developer_since:'2001-01-01'},'',name);
const change=(actor,target,operation,more={})=>call(actor,'honors.change',{memberId:target.user.id,operation,reason:'验收操作',requestId:randomUUID(),...more});
const post=(u,text,anonymous=false)=>call(u,'posts.create',{body:text,requestId:randomUUID(),anonymous});
const comment=(u,p,body)=>call(u,'comments.create',{body,postId:p,requestId:randomUUID(),anonymous:false});
const hall=async(u,target=u)=>(await call(u,'honors.hall',{memberId:target.user.id})).hall;
const flag=(u,p,kind,enabled=true)=>call(u,'reactions.set',{postId:p,kind,enabled});
before(async()=>{db=new PGlite();await db.exec(schema);api=createCommunity({registrationEnabled:true,db:async(a,b,t)=>(await db.query('select hyt_community($1,$2,$3) as r',[a,b,t])).rows[0].r});
 const actors=[];for(const name of ['站长甲','审核乙','作者丙','同学丁','同学戊'])actors.push(await reg(name));
 [owner,moderator,alice,bob,other]=actors;});
after(()=>db.close());
test('developer must match unique original audit + stable ID, independent of rename; binding is idempotent',async()=>{
 assert.equal(owner.user.badges.official,null);
 await assert.rejects(db.exec(developerBinding(owner.user.id)));
 await db.query("update hyt_members set role='moderator' where id=$1",[owner.user.id]);
 await db.query("insert into hyt_moderation(moderator_id,action,reason) values($1,'grant_moderator','Initial moderator binding explicitly authorized by repository owner, 2026-11-16')",[owner.user.id]);
 await assert.rejects(db.exec(developerBinding(alice.user.id)));await db.exec(developerBinding(owner.user.id));await db.exec(developerBinding(owner.user.id));
 assert.equal((await call(owner,'me')).user.badges.official.code,'developer');
 await assert.rejects(db.query('update hyt_members set developer_since=now() where id=$1',[bob.user.id]));
 assert.equal((await db.query("select count(*)::int n from hyt_honor_history")).rows[0].n,1);
});
test('role forgery, undocumented unlock and cross-account writes cannot grant rights or awards',async()=>{
 assert.equal((await call(alice,'profile.update',{nickname:'站长甲',developer:true,role:'moderator'})).user.badges.official,null);
 await assert.rejects(call(alice,'honors.manage'),{code:'forbidden'});await assert.rejects(change(alice,alice,'appoint',{caps:['users']}),{code:'forbidden'});
 await assert.rejects(call(alice,'honors.unlock',{code:'popular'}),{code:'not_found'});
 await assert.rejects(call(alice,'honors.wear',{memberId:owner.user.id,honor:'seed',showcase:['popular']}),{code:'invalid_showcase'});
 assert.deepEqual((await hall(bob,alice)).awards,{});assert.equal((await hall(bob,alice)).progress,undefined);
});
test('scoped moderator cannot use either legacy or direct content API after restriction or dismissal',async()=>{
 await change(owner,moderator,'appoint',{caps:['recommend']});
 await assert.rejects(call(moderator,'admin.reports'),{code:'forbidden'});await assert.rejects(call(moderator,'admin.content'),{code:'forbidden'});
 await assert.rejects(call(moderator,'admin.resolve',{reportId:randomUUID(),reason:'违规内容',decision:'ban'}),{code:'forbidden'});
 await assert.rejects(change(moderator,bob,'mute'),{code:'forbidden'});await assert.rejects(change(moderator,alice,'grant',{kind:'creator'}),{code:'forbidden'});
 await assert.rejects(change(owner,alice,'grant',{kind:'creator'}),{code:'recommendation_required'});await change(moderator,alice,'recommend');
 await change(owner,alice,'grant',{kind:'creator'});await change(owner,moderator,'dismiss');await assert.rejects(change(moderator,bob,'recommend'),{code:'forbidden'});
});
test('grants, audit replay, revocation, anonymous projections and permanent seed',async()=>{
 const rid=randomUUID();await change(owner,alice,'grant',{kind:'seed',requestId:rid});await change(owner,alice,'grant',{kind:'seed',requestId:rid});
 assert.equal((await db.query('select count(*)::int n from hyt_honor_history where id=$1',[rid])).rows[0].n,1);
 await assert.rejects(change(owner,bob,'grant',{kind:'seed',requestId:rid}),{code:'request_conflict'});
 await assert.rejects(change(owner,alice,'revoke',{kind:'seed'}),{code:'permanent_honor'});
 await call(alice,'honors.wear',{honor:'creator',showcase:['arrival']});
 const anon=await post(alice,'匿名讨论',true);assert.equal(anon.post.author.badges,undefined);assert.equal(anon.post.author.id,undefined);
 const pub=await post(alice,'公开讨论');assert.equal(pub.post.author.badges.worn.code,'creator');
 assert.equal((await hall(bob,alice)).honors.length,2);assert.deepEqual(Object.keys((await hall(bob,alice)).awards),['arrival']);
 await change(owner,alice,'revoke',{kind:'creator'});assert.equal((await call(bob,'posts.get',{postId:pub.post.id})).post.author.badges.worn,null);
});
test('distinct discussions, duplicate text, withdrawn comments and post removal change live progress while awards persist',async()=>{
 const p=(await post(owner,'讨论一')).post.id,q=(await post(owner,'讨论二')).post.id;
 const c=await comment(bob,p,'真有意思');await comment(bob,p,'我的另一个观点');await comment(bob,q,'真有意思！');await comment(bob,q,'哈哈哈哈');
 assert.equal((await hall(bob)).progress.threads,1);await call(bob,'comments.delete',{postId:p,commentId:c.comment.id});
 assert.equal((await hall(bob)).progress.threads,2);await call(owner,'posts.delete',{postId:q});
 assert.equal((await hall(bob)).progress.threads,1);assert.ok((await hall(bob)).awards.hello);
});
test('self likes, repeated toggles and batches of new accounts do not inflate credit; one grant, private notices',async()=>{
 const p=(await post(other,'其他同学点赞')).post.id;
 await flag(other,p,'like');assert.equal((await hall(other)).progress.likes,0);
 await flag(alice,p,'like');await flag(alice,p,'like');await flag(bob,p,'like');assert.equal((await hall(other)).progress.likes,1);
 await flag(bob,p,'like',false);await flag(alice,p,'like',false);assert.equal((await hall(other)).progress.likes,0);assert.ok((await hall(other)).awards.liked);
 const repeated={requestId:randomUUID(),body:'幂等写入',anonymous:false};await call(other,'posts.create',repeated);await call(other,'posts.create',repeated);
 assert.equal((await hall(other)).progress.posts,2);assert.equal((await call(other,'notifications.unread')).unlocks.filter(x=>x==='liked').length,1);
 await call(other,'honors.ack',{codes:['liked']});assert.ok(!(await call(other,'notifications.unread')).unlocks.includes('liked'));
});
test('all eight thresholds, three-item display limit, duplicates and disappearing saved posts',async()=>{
 const u=await reg('目标用户'),reader=await reg('资深读者');await db.query("update hyt_members set created_at=now()-interval '2 days' where id=$1",[reader.user.id]);
 const posts=[];for(let i=0;i<30;i++){const p=(await post(i<5?u:owner,'校园故事 '+i)).post.id;posts.push(p);await db.query("update hyt_posts set created_at=now()-interval '2 days' where id=$1",[p]);if(i<20)await flag(u,p,'save');if(i<10)await comment(u,p,'校园讨论 '+i);}
 for(const p of posts.slice(0,5))await flag(reader,p,'like');
 for(let i=0;i<25;i++){const c=await comment(u,posts[i],'深入交流 '+i);await call(reader,'comments.like',{postId:posts[i],commentId:c.comment.id,enabled:true});}
 const h=await hall(u);assert.equal(h.total,8);assert.equal(h.progress.likes,30);assert.equal(h.progress.saves,20);
 await assert.rejects(call(u,'honors.wear',{honor:null,showcase:['arrival','hello','liked','sprout']}),{code:'invalid_request'});
 await call(u,'honors.wear',{honor:null,showcase:['collector','popular','hello']});assert.equal((await hall(reader,u)).showcase.length,3);
 await flag(u,posts[0],'save');await flag(u,posts[0],'save',false);await call(owner,'posts.delete',{postId:posts[6]});assert.equal((await hall(u)).progress.saves,18);assert.equal((await hall(u)).total,8);
});
test('lazy historic recovery is private, repeatable and does not replay fabricated notifications',async()=>{
 await db.query('delete from hyt_awards where member_id=$1',[alice.user.id]);await db.query('update hyt_members set awards_initialized=false where id=$1',[alice.user.id]);await db.exec(schema);
 await call(alice,'me',{entry:true});let h=await hall(alice);assert.ok(h.awards.arrival&&h.awards.firstpost);assert.deepEqual((await call(alice,'notifications.unread')).unlocks,[]);
 await call(alice,'me',{entry:true});assert.equal((await hall(alice)).total,h.total);
 await call(bob,'members.block',{memberId:alice.user.id});await assert.rejects(hall(alice,bob),{code:'not_found'});
});
