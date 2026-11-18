import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../functions/community/core.mjs';

let pg,api,a,b,c;
const password='synthetic-community-password';
const call=(who,action,body={})=>api.execute(action,body,who.sessionToken,'engagement');
const post=(who=a,anonymous=false)=>call(who,'posts.create',{body:'测试讨论 '+randomUUID(),anonymous,requestId:randomUUID()}).then(x=>x.post);
const reply=(who,p,replyTo=null,anonymous=false,requestId=randomUUID())=>call(who,'comments.create',{postId:p.id,body:'真实回复测试',replyTo,anonymous,requestId}).then(x=>x.comment);
const inbox=(who,filter='all')=>call(who,'notifications.list',{filter});
const notices=async(who,p)=>(await inbox(who)).notifications.filter(x=>x.postId===p.id);
before(async()=>{
 pg=new PGlite();const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');await pg.exec(schema);await pg.exec(schema);
 api=createCommunity({registrationEnabled:true,db:async(action,body,hash)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result});
 const register=name=>api.execute('register',{username:name,nickname:name,password,agreed:true},'',name);
 a=await register('notice_author');b=await register('notice_reader');c=await register('notice_watcher');
});
afterEach(async()=>{await pg.exec('DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; TRUNCATE hyt_posts CASCADE;');});
after(async()=>pg.close());

test('retries create one reply notice, self replies none, anonymous identity stays thread scoped',async()=>{
 const p=await post(a,true),requestId=randomUUID();
 await reply(b,p,null,true,requestId);await reply(b,p,null,true,requestId);
 const rows=await notices(a,p);assert.equal(rows.length,1);assert.equal(rows[0].kind,'post_reply');
 for(const secret of [b.user.id,b.user.nickname,b.user.username,b.sessionToken])assert(!JSON.stringify(rows).includes(secret));
 const child=await reply(a,p,rows[0].commentId,false);
 const received=await notices(b,p);assert.equal(received.length,1);assert.equal(received[0].kind,'reply');assert.equal(received[0].actor.name,child.author.name);
 assert.equal((await notices(a,p)).length,1);
});
test('watching is explicit, repeated replies do not resubscribe a muted discussion',async()=>{
 const p=await post();await call(c,'threads.watch',{postId:p.id,enabled:true});
 await reply(b,p);assert.equal((await notices(c,p))[0].kind,'thread_reply');
 assert((await call(c,'posts.list',{scope:'watching'})).posts.some(x=>x.id===p.id));
 await call(c,'threads.watch',{postId:p.id,enabled:false});assert.equal((await notices(c,p)).length,0);
 await reply(c,p);await reply(b,p);assert.equal((await notices(c,p)).length,0);
 assert(!(await call(c,'posts.list',{scope:'watching'})).posts.some(x=>x.id===p.id));
});
test('notification ids cannot mark another account read; reading is idempotent',async()=>{
 const p=await post();await reply(b,p);const item=(await notices(a,p))[0];
 await call(b,'notifications.read',{ids:[item.id]});assert.equal((await notices(a,p))[0].readAt,null);
 await call(a,'notifications.read',{ids:[item.id]});const read=(await notices(a,p))[0].readAt;assert(read);
 await call(a,'notifications.read',{ids:[item.id]});assert.equal((await notices(a,p))[0].readAt,read);
 assert.equal((await call(a,'notifications.unread')).unreadCount,0);
 await assert.rejects(call(a,'notifications.read',{ids:[]}),{code:'invalid_request'});
 await assert.rejects(call(a,'notifications.read',{ids:Array(51).fill(item.id)}),{code:'invalid_request'});
});
test('like retries and toggles never create a stream of new alerts or reveal anonymous likers',async()=>{
 const p=await post();const body={postId:p.id,kind:'like',enabled:true};
 await call(b,'reactions.set',body);await call(b,'reactions.set',body);
 const [item]=await notices(a,p);assert(item);assert.equal((await notices(a,p)).length,1);
 assert.equal(item.actor.name,'一位同学');assert(!JSON.stringify(item).includes(b.user.id));
 await call(a,'notifications.read',{ids:[item.id]});
 await call(b,'reactions.set',{...body,enabled:false});assert.equal((await notices(a,p)).length,0);
 await call(b,'reactions.set',body);assert.equal((await notices(a,p))[0].id,item.id);assert((await notices(a,p))[0].readAt);
 await call(a,'reactions.set',body);assert.equal((await notices(a,p)).length,1);
});
test('deleted, hidden and blocked content disappears from both previews and unread counts',async()=>{
 const p=await post();const first=await reply(b,p);assert.equal((await notices(a,p)).length,1);
 await call(a,'blocks.set',{postId:p.id,commentId:first.id});assert.equal((await notices(a,p)).length,0);
 assert.equal((await call(a,'notifications.unread')).unreadCount,0);
 await call(a,'blocks.clear');await call(b,'comments.delete',{postId:p.id,commentId:first.id});assert.equal((await notices(a,p)).length,0);
 await reply(b,p);await call(a,'posts.delete',{postId:p.id});assert.equal((await notices(a,p)).length,0);
});
test('thread context locates a late nested reply without leaking other threads or blocked roots',async()=>{
 const p=await post();const root=await reply(b,p);const nested=await reply(c,p,root.id,true);
 const context=await call(a,'comments.context',{postId:p.id,commentId:nested.id});
 assert.equal(context.focusCommentId,nested.id);assert.equal(context.context.id,root.id);assert.equal(context.context.replies[0].id,nested.id);
 assert(!JSON.stringify(context).includes(c.user.id));
 const other=await post();await assert.rejects(call(a,'comments.context',{postId:other.id,commentId:nested.id}),{code:'not_found'});
 await call(a,'blocks.set',{postId:p.id,commentId:root.id});
 await assert.rejects(call(a,'comments.context',{postId:p.id,commentId:nested.id}),{code:'not_found'});
 assert.equal((await notices(a,p)).length,0);
});
test('participated feed is private, ordered by recent conversation, and reading resets new-reply count',async()=>{
 const old=await post(),newer=await post();await reply(b,old);
 assert((await call(b,'posts.list',{scope:'participated'})).posts.some(x=>x.id===old.id));
 assert(!(await call(c,'posts.list',{scope:'participated'})).posts.some(x=>x.id===old.id));
 await call(b,'posts.get',{postId:old.id});await reply(c,old);
 const mine=await call(a,'posts.list',{scope:'participated'});assert.equal(mine.posts[0].id,old.id);assert(mine.posts.some(x=>x.id===newer.id));
 let joined=(await call(b,'posts.list',{scope:'participated'})).posts.find(x=>x.id===old.id);assert.equal(joined.newReplyCount,1);
 await call(b,'posts.get',{postId:old.id});joined=(await call(b,'posts.list',{scope:'participated'})).posts.find(x=>x.id===old.id);assert.equal(joined.newReplyCount,0);
});
test('public profiles omit login ids, anonymous posts, comments and private bookmarks',async()=>{
 const named=await post(),anonymous=await post(a,true);
 await call(a,'profile.update',{nickname:a.user.nickname,bio:'公开简介'});
 const profile=(await call(b,'profile.get',{memberId:a.user.id})).profile;
 assert.equal(profile.bio,'公开简介');assert(!('username' in profile));assert(!('bannedUntil' in profile));
 const rows=(await call(b,'posts.list',{scope:'author',memberId:a.user.id})).posts;assert(rows.some(x=>x.id===named.id));assert(!rows.some(x=>x.id===anonymous.id));
 assert(rows.every(x=>!x.anonymous));assert.equal(rows.find(x=>x.id===named.id).author.id,a.user.id);
 assert(!('id' in (await call(b,'posts.get',{postId:anonymous.id})).post.author));
 await call(b,'blocks.set',{postId:named.id});await assert.rejects(call(b,'profile.get',{memberId:a.user.id}),{code:'not_found'});
});
test('inbox cursor retains microseconds, filters are exclusive and paging has no duplicates',async()=>{
 const p=await post();
 for(let i=0;i<35;i++)await pg.query("INSERT INTO hyt_comments(post_id,author_id,body,anonymous,request_id,created_at) VALUES($1,$2,'分页回复',false,$3,'2026-11-01 00:00:00.123456+00'::timestamptz + $4::int * interval '1 microsecond') RETURNING *",[p.id,b.user.id,randomUUID(),i]).then(async r=>{await pg.query('SELECT hyt_notify_comment(c) FROM hyt_comments c WHERE c.id=$1',[r.rows[0].id]);});
 const first=await inbox(a,'replies'),second=await call(a,'notifications.list',{filter:'replies',...first.next});
 assert.equal(first.notifications.length,30);assert.equal(second.notifications.length,5);assert.equal(second.next,null);
 assert.equal(new Set([...first.notifications,...second.notifications].map(x=>x.id)).size,35);
 assert.equal((await inbox(a,'likes')).notifications.length,0);
});
test('schema reapplication preserves notification/read state and role restrictions cover new tables',async()=>{
 const p=await post();await reply(b,p);const item=(await notices(a,p))[0];await call(a,'notifications.read',{ids:[item.id]});
 await pg.exec(await readFile(new URL('../community-schema.sql',import.meta.url),'utf8'));
 assert((await notices(a,p))[0].readAt);
 const policies=await pg.query("SELECT relname,relrowsecurity FROM pg_class WHERE relname IN ('hyt_notifications','hyt_thread_watches','hyt_thread_visits')");assert(policies.rows.every(x=>x.relrowsecurity));
 await assert.rejects(api.execute('notifications.list',{},'','unauthenticated'),{code:'session_expired'});
});
