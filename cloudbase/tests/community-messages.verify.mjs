import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,a,b,c;
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const password='synthetic-messages-password';
const call=(who,action,body={})=>api.execute(action,body,who.sessionToken,'messages');
const open=(who,other)=>call(who,'messages.open',{memberId:other.user.id}).then(r=>r.conversation);
const send=(who,t,body='合成私信',requestId=randomUUID())=>call(who,'messages.send',{conversationId:t.id,body,requestId});
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({registrationEnabled:true,db:async(action,body,hash)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result});const reg=username=>api.execute('register',{username,nickname:username,password,agreed:true},'',username);a=await reg('message_alice');b=await reg('message_bob');c=await reg('message_other');});
afterEach(async()=>pg.exec('DELETE FROM hyt_dm_reads; DELETE FROM hyt_dm_messages; DELETE FROM hyt_dm_threads; DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; DELETE FROM hyt_follows; UPDATE hyt_members SET banned_until=NULL;'));
after(async()=>pg.close());
test('follower stats/lists belong to the caller and permit follow-back without leaking account names',async()=>{
 await call(b,'follows.set',{memberId:a.user.id,enabled:true});
 assert.deepEqual((await call(a,'follows.stats',{memberId:b.user.id})).social,{followingCount:0,followerCount:1});
 let rows=(await call(a,'followers.list',{memberId:b.user.id})).followers;assert.equal(rows[0].id,b.user.id);assert.equal(rows[0].following,false);assert(!JSON.stringify(rows).includes('username'));
 await call(a,'follows.set',{memberId:b.user.id,enabled:true});assert.equal((await call(a,'followers.list')).followers[0].following,true);
 await call(a,'members.block',{memberId:b.user.id});assert.deepEqual((await call(a,'follows.stats')).social,{followingCount:0,followerCount:0});assert.deepEqual((await call(b,'followers.list')).followers,[]);
});
test('canonical pair opens once in either direction and empty conversations do not clutter inbox',async()=>{
 const x=await open(a,b),y=await open(b,a);assert.equal(x.id,y.id);assert.equal(x.member.id,b.user.id);assert.equal(y.member.id,a.user.id);
 assert.deepEqual((await call(a,'messages.inbox')).conversations,[]);await assert.rejects(open(a,a),{code:'invalid_request'});
});
test('only two participants read, send and acknowledge a conversation',async()=>{
 const t=await open(a,b),sent=await send(a,t);assert.equal(sent.message.mine,true);
 for(const action of ['messages.list','messages.read','messages.send'])await assert.rejects(call(c,action,{conversationId:t.id,throughSeq:sent.message.seq,body:'越权',requestId:randomUUID()}),{code:'conversation_unavailable'});
 const list=await call(b,'messages.list',{conversationId:t.id});assert.equal(list.messages[0].mine,false);assert.equal(list.messages[0].requestId,null);assert(!JSON.stringify(list).includes('username'));assert(!JSON.stringify(list).includes('sender_id'));
});
test('send retries are idempotent, content conflicts are rejected, and failed sends do not create extra messages',async()=>{
 const t=await open(a,b),id=randomUUID(),x=await send(a,t,'同一条',id),y=await send(a,t,'同一条',id);assert.equal(x.message.id,y.message.id);
 await assert.rejects(send(a,t,'改过内容',id),{code:'request_conflict'});const other=await open(a,c);await assert.rejects(send(a,other,'同一条',id),{code:'request_conflict'});
 assert.equal((await call(b,'messages.list',{conversationId:t.id})).messages.length,1);
});
test('unread acknowledgement is monotonic and stops at delivered sequence, preserving newer messages',async()=>{
 const t=await open(a,b),one=await send(a,t,'第一条'),two=await send(a,t,'第二条');
 assert.equal((await call(b,'messages.unread')).messageUnreadCount,2);assert.equal((await call(a,'messages.unread')).messageUnreadCount,0);
 await call(b,'messages.read',{conversationId:t.id,throughSeq:one.message.seq});assert.equal((await call(b,'messages.unread')).messageUnreadCount,1);
 await call(b,'messages.read',{conversationId:t.id,throughSeq:two.message.seq});await call(b,'messages.read',{conversationId:t.id,throughSeq:one.message.seq});assert.equal((await call(b,'messages.unread')).messageUnreadCount,0);
 await assert.rejects(call(b,'messages.read',{conversationId:t.id,throughSeq:'9999999'}),{code:'invalid_request'});
});
test('message history pages are disjoint and preserve older pages while returning each page in reading order',async()=>{
 const t=await open(a,b);for(let i=0;i<65;i++)await pg.query('INSERT INTO hyt_dm_messages(thread_id,sender_id,body,request_id) VALUES($1,$2,$3,$4)',[t.id,a.user.id,'历史 '+i,randomUUID()]);
 let next={},ids=[];do{const r=await call(b,'messages.list',{conversationId:t.id,...next});assert(r.messages.length<=30);assert(r.messages.every((m,i)=>!i||BigInt(m.seq)>BigInt(r.messages[i-1].seq)));ids.push(...r.messages.map(x=>x.id));next=r.next;}while(next);assert.equal(ids.length,65);assert.equal(new Set(ids).size,65);
});
test('inbox paginates by stable message sequence with no duplicate conversations',async()=>{
 for(let i=0;i<24;i++){const id=randomUUID();await pg.query("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash) VALUES($1,$2,'合成同学','test','test')",[id,'m_'+id]);const t=(await call(a,'messages.open',{memberId:id})).conversation;await pg.query("INSERT INTO hyt_dm_messages(thread_id,sender_id,body,request_id) VALUES($1,$2,'合成分页',$3)",[t.id,id,randomUUID()]);await pg.query('UPDATE hyt_dm_threads SET last_seq=(SELECT max(seq) FROM hyt_dm_messages WHERE thread_id=$1) WHERE id=$1',[t.id]);}
 let next={},ids=[];do{const r=await call(a,'messages.inbox',next);ids.push(...r.conversations.map(x=>x.id));next=r.next;}while(next);assert.equal(ids.length,24);assert.equal(new Set(ids).size,24);assert.equal((await call(a,'messages.unread')).messageUnreadCount,24);
});
test('blocking hides the thread and unread counts in both directions and stops future sends',async()=>{
 const t=await open(a,b);await send(a,t);await call(b,'members.block',{memberId:a.user.id});
 for(const who of [a,b]){assert.equal((await call(who,'messages.unread')).messageUnreadCount,0);assert.deepEqual((await call(who,'messages.inbox')).conversations,[]);await assert.rejects(call(who,'messages.list',{conversationId:t.id}),{code:'conversation_unavailable'});}
 await assert.rejects(send(a,t),{code:'conversation_unavailable'});await assert.rejects(open(a,b),{code:'conversation_unavailable'});
 await call(b,'blocks.clear');assert.equal((await call(b,'messages.inbox')).conversations.length,1);
});
test('hiding an anonymous discussion cannot reveal its author through private messages or follower counts',async()=>{
 const p=(await call(a,'posts.create',{body:'匿名合成',anonymous:true,requestId:randomUUID()})).post,t=await open(a,b);await send(a,t);await call(b,'follows.set',{memberId:a.user.id,enabled:true});
 assert(!p.author.id);await call(b,'blocks.set',{postId:p.id});assert.equal((await call(b,'messages.inbox')).conversations.length,1);assert.equal((await call(b,'follows.stats')).social.followingCount,1);
});
test('muted accounts can read but cannot send; authenticated message rate is bounded',async()=>{
 const t=await open(a,b);await pg.query("UPDATE hyt_members SET banned_until=now()+interval '1 day' WHERE id=$1",[a.user.id]);await assert.rejects(send(a,t),{code:'account_muted'});assert.deepEqual((await call(a,'messages.list',{conversationId:t.id})).messages,[]);await pg.query('UPDATE hyt_members SET banned_until=NULL WHERE id=$1',[a.user.id]);
 for(let i=0;i<20;i++)await send(a,t);await assert.rejects(send(a,t),{code:'posting_too_fast'});
});
test('deleting an account clears private messages, receipts and conversations',async()=>{
 const d=await api.execute('register',{username:'dm_delete',nickname:'合成注销',password,agreed:true},'','delete'),t=await open(a,d),sent=await send(a,t);await call(d,'messages.read',{conversationId:t.id,throughSeq:sent.message.seq});await call(d,'account.delete',{password});assert.equal((await pg.query('SELECT count(*) AS n FROM hyt_dm_messages')).rows[0].n,0);assert.deepEqual((await call(a,'messages.inbox')).conversations,[]);
});
test('strict arguments, additive migration and role permissions protect message data',async()=>{
 const t=await open(a,b);await send(a,t);
 for(const body of ['', 'x'.repeat(1001),'<\u0000>'])await assert.rejects(send(a,t,body),{code:'invalid_request'});
 for(const beforeSeq of ['-1','0',1,'1 OR 1=1','9999999999999999999999'])await assert.rejects(call(a,'messages.list',{conversationId:t.id,beforeSeq}),{code:'invalid_request'});
 await pg.exec("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF; END $$;");await pg.exec(schema);assert.equal((await call(b,'messages.list',{conversationId:t.id})).messages.length,1);
 for(const table of ['hyt_dm_messages','hyt_dm_threads','hyt_dm_reads'])assert.equal((await pg.query("SELECT has_table_privilege('anon',$1,'SELECT') AS allowed",[table])).rows[0].allowed,false);
 assert(api.config().messagesEnabled&&api.config().socialEnabled);assert.equal(api.config().schema,10);
});

test('own follower list paginates equal timestamps without duplicates and never accepts another owner',async()=>{
 const ids=[];for(let i=0;i<24;i++){const id=randomUUID();ids.push(id);await pg.query("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash) VALUES($1,$2,'合成粉丝','test','test')",[id,'fan_'+id]);await pg.query("INSERT INTO hyt_follows(member_id,followed_id,created_at) VALUES($1,$2,'2026-01-01')",[id,a.user.id]);}
 let next={},found=[];do{const r=await call(a,'followers.list',{...next,memberId:b.user.id});found.push(...r.followers.map(x=>x.id));next=r.next;}while(next);assert.equal(found.length,24);assert.deepEqual(new Set(found),new Set(ids));assert.equal((await call(a,'follows.stats')).social.followerCount,24);assert.deepEqual((await call(b,'followers.list',{memberId:a.user.id})).followers,[]);
});
