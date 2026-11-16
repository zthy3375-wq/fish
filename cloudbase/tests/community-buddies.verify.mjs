import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,a,b,c;const password='synthetic-buddy-password';
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const call=(u,action,body={})=>api.execute(action,body,u.sessionToken,'buddy-tests');
const definition=()=>({location:'操场南门',startsAt:new Date(Date.now()+86400000).toISOString(),capacity:2});
const post=(extra={})=>call(a,'posts.create',{body:'一起慢跑半小时',category:'buddies',anonymous:false,requestId:randomUUID(),buddy:definition(),...extra}).then(r=>r.post);
const join=(u,p,enabled=true)=>call(u,'buddies.join',{postId:p.id,enabled}).then(r=>r.post);
const close=(u,p,closed=true)=>call(u,'buddies.close',{postId:p.id,closed}).then(r=>r.post);
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({registrationEnabled:true,db:async(x,y,z)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[x,JSON.stringify(y),z])).rows[0].result});const reg=username=>api.execute('register',{username,nickname:username,password,agreed:true},'',username);a=await reg('buddy_host');b=await reg('buddy_member');c=await reg('buddy_other');});
afterEach(async()=>{await pg.exec("UPDATE hyt_members SET banned_until=NULL,role='member'; DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; DELETE FROM hyt_hidden_threads; TRUNCATE hyt_posts CASCADE;");});
after(async()=>pg.close());
test('buddy definition requires category, explicit campus time, location, capacity and text',async()=>{
 assert.equal(api.config().schema,8);assert.equal(api.config().buddiesEnabled,true);
 for(const extra of [{category:'daily'},{body:''},{buddy:{...definition(),capacity:0}},{buddy:{...definition(),capacity:21}},{buddy:{...definition(),capacity:2.5}},{buddy:{...definition(),location:' '}},{buddy:{...definition(),startsAt:'2026-12-01T10:00'}},{poll:{question:'混合',options:['一','二'],durationHours:24}}])await assert.rejects(post(extra),{code:'invalid_request'});
 for(const startsAt of [new Date(Date.now()-1000).toISOString(),new Date(Date.now()+91*86400000).toISOString()])await assert.rejects(post({buddy:{...definition(),startsAt}}),{code:'buddy_time'});
 const p=await post();assert.equal(p.buddy.capacity,2);assert.equal(p.buddy.count,0);assert.equal(p.buddy.joined,false);assert(!('participants' in p.buddy));
 const plain=await call(a,'posts.create',{body:'普通搭子帖',category:'buddies',anonymous:false,requestId:randomUUID()});assert.equal(plain.post.buddy,null);
});
test('publish retry is immutable and succeeds after time has passed without creating a second meetup',async()=>{
 const requestId=randomUUID(),buddy=definition(),p=await post({requestId,buddy});await pg.query("UPDATE hyt_buddies SET starts_at=now()-interval '1 hour' WHERE post_id=$1",[p.id]);
 assert.equal((await post({requestId,buddy})).id,p.id);await assert.rejects(post({requestId,buddy:{...buddy,capacity:3}}),{code:'request_conflict'});
 assert.equal((await pg.query('SELECT count(*)::int n FROM hyt_buddies')).rows[0].n,1);
});
test('signup and cancellation are idempotent; host excluded; current membership enters joined and participation feeds',async()=>{
 const p=await post();await assert.rejects(join(a,p),{code:'buddy_host'});
 const first=await join(b,p);assert.equal(first.buddy.count,1);assert(first.buddy.joined);assert(first.watching);
 assert.equal((await join(b,p)).buddy.version,first.buddy.version);
 for(const scope of ['joined','participated'])assert.equal((await call(b,'posts.list',{scope})).posts[0].id,p.id);
 assert.equal((await call(c,'posts.list',{scope:'joined'})).posts.length,0);
 const left=await join(b,p,false);assert.equal(left.buddy.count,0);assert(!left.buddy.joined);assert.equal((await join(b,p,false)).buddy.version,left.buddy.version);
 assert.equal((await call(b,'posts.list',{scope:'joined'})).posts.length,0);
});
test('competing requests cannot overbook the final slot and a vacancy can be filled',async()=>{
 const p=await post({buddy:{...definition(),capacity:1}});const results=await Promise.allSettled([join(b,p),join(c,p)]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'buddy_full');
 const winner=results[0].status==='fulfilled'?b:c,other=winner===b?c:b;await join(winner,p,false);assert.equal((await join(other,p)).buddy.count,1);
});
test('only host sees private roster; anonymous host and generic notices never expose account identities',async()=>{
 const p=await post({anonymous:true});await join(b,p);const publicPost=(await call(c,'posts.get',{postId:p.id})).post;
 assert(!('id' in publicPost.author));assert(!JSON.stringify(publicPost.buddy).includes(b.user.id));await assert.rejects(call(c,'buddies.members',{postId:p.id}),{code:'forbidden'});
 const roster=await call(a,'buddies.members',{postId:p.id});assert.deepEqual(roster.participants.map(x=>x.id),[b.user.id]);assert(!('username' in roster.participants[0]));
 const notices=(await call(a,'notifications.list',{filter:'replies'})).notifications;assert.equal(notices.length,1);assert.equal(notices[0].kind,'buddy');assert(!('id' in notices[0].actor));assert(!JSON.stringify(notices[0]).includes(b.user.nickname));
 await close(a,p);const inbox=(await call(b,'notifications.list')).notifications;assert.equal(inbox[0].kind,'buddy');assert(!JSON.stringify(inbox).includes(a.user.id));
});
test('close and reopen require host, preserve seats, aggregate notifications and stop at start time',async()=>{
 const p=await post();await join(b,p);await assert.rejects(close(c,p),{code:'forbidden'});const closed=await close(a,p);assert(closed.buddy.closed);assert.equal(closed.buddy.count,1);
 await assert.rejects(join(c,p),{code:'buddy_closed'});assert.equal((await join(b,p)).buddy.count,1);await close(a,p);assert.equal((await call(b,'notifications.list')).notifications.length,1);
 await close(a,p,false);assert.equal((await join(c,p)).buddy.count,2);await pg.query("UPDATE hyt_buddies SET starts_at=now()-interval '1 hour',closed=true WHERE post_id=$1",[p.id]);await assert.rejects(close(a,p,false),{code:'buddy_closed'});assert.equal((await join(b,p,false)).buddy.count,1);
});
test('mute and lock prevent new signup but preserve cancellation and host closing',async()=>{
 const p=await post();await pg.query("UPDATE hyt_members SET banned_until=now()+interval '1 hour' WHERE id=$1",[b.user.id]);await assert.rejects(join(b,p),{code:'account_muted'});
 await join(c,p);await pg.query('UPDATE hyt_posts SET locked=true WHERE id=$1',[p.id]);await assert.rejects(join(b,p),{code:'post_locked'});assert.equal((await join(c,p,false)).buddy.count,0);assert((await close(a,p)).buddy.closed);await assert.rejects(close(a,p,false),{code:'post_locked'});
});
test('blocking releases both directions and clearing a block never restores membership',async()=>{
 const p=await post();await join(b,p);await call(b,'blocks.set',{postId:p.id});assert.equal((await call(a,'buddies.members',{postId:p.id})).participants.length,0);await call(b,'blocks.clear');assert.equal((await call(b,'posts.get',{postId:p.id})).post.buddy.joined,false);
 const other=(await call(b,'posts.create',{body:'另一活动',category:'buddies',buddy:definition(),anonymous:false,requestId:randomUUID()})).post;await join(a,other);await call(a,'blocks.set',{postId:other.id});assert.equal((await call(b,'buddies.members',{postId:other.id})).participants.length,0);
});
test('hiding an anonymous meetup releases own seat; deleted or moderated content cannot be joined',async()=>{
 const p=await post({anonymous:true});await join(b,p);await call(b,'blocks.set',{postId:p.id});assert.equal((await call(a,'buddies.members',{postId:p.id})).participants.length,0);await assert.rejects(join(b,p),{code:'not_found'});
 await call(a,'posts.delete',{postId:p.id});await assert.rejects(join(c,p),{code:'not_found'});await assert.rejects(call(a,'buddies.members',{postId:p.id}),{code:'not_found'});
});
test('joining respects an explicit discussion opt-out and migration preserves registrations with private table grants',async()=>{
 const p=await post();await call(b,'threads.watch',{postId:p.id,enabled:false});assert.equal((await join(b,p)).watching,false);await pg.exec(schema);assert.equal((await call(b,'posts.get',{postId:p.id})).post.buddy.joined,true);
 const grants=(await pg.query("SELECT relname,relrowsecurity FROM pg_class WHERE relname IN ('hyt_buddies','hyt_buddy_members')")).rows;assert.equal(grants.length,2);assert(grants.every(x=>x.relrowsecurity));
});
test('notification aggregation does not duplicate on retries and real changes become unread again',async()=>{
 const p=await post();await join(b,p);let n=(await call(a,'notifications.list')).notifications[0];await call(a,'notifications.read',{ids:[n.id]});await join(b,p);assert.equal((await call(a,'notifications.unread')).unreadCount,0);
 await join(b,p,false);const rows=(await call(a,'notifications.list')).notifications;assert.equal(rows.length,1);assert.equal(rows[0].id,n.id);assert.equal(rows[0].readAt,null);
});
test('account deletion releases registrations and advances revisions without reviving stale counts',async()=>{
 const d=await api.execute('register',{username:'buddy_deleted',nickname:'即将注销',password,agreed:true},'','buddy-delete'),p=await post();const before=await join(d,p);await call(d,'account.delete',{password});const after=(await call(a,'posts.get',{postId:p.id})).post;assert.equal(after.buddy.count,0);assert(after.buddy.version>before.buddy.version);
});

test('public blocks never link anonymous hosts through changed membership or signup refusals',async()=>{
 const anon=await post({anonymous:true}),named=await post();const before=await join(b,anon);
 await call(b,'blocks.set',{postId:named.id});let current=(await call(b,'posts.get',{postId:anon.id})).post;
 assert.equal(current.buddy.joined,true);assert.equal(current.buddy.version,before.buddy.version);assert.equal(current.author.id,undefined);
 await join(b,anon,false);assert.equal((await join(b,anon)).buddy.joined,true);
 const other=(await call(b,'posts.create',{body:'公开日常',anonymous:false,requestId:randomUUID()})).post;
 await call(a,'blocks.set',{postId:other.id});current=(await call(b,'posts.get',{postId:anon.id})).post;assert.equal(current.buddy.joined,true);
 await join(b,anon,false);assert.equal((await join(b,anon)).buddy.joined,true);
 await call(b,'blocks.set',{postId:anon.id});assert.equal((await call(a,'buddies.members',{postId:anon.id})).participants.length,0);
});
