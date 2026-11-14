import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity,digest,hashPassword,verifyPassword} from '../functions/community/core.mjs';
import {createServer} from '../functions/community/server.mjs';

let pg,api,alice,bob,moderator;const pass='test-only-long-password';
const rpc=async(a,b,t)=> (await pg.query('SELECT public.hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t])).rows[0].result;
const execute=(a,b={},u=alice)=>api.execute(a,b,u?.sessionToken,'synthetic-'+randomUUID());
const post=(body,anonymous=true,u=alice)=>execute('posts.create',{body,anonymous,requestId:randomUUID()},u);
const comment=(postId,body,anonymous=true,u=bob)=>execute('comments.create',{postId,body,anonymous,requestId:randomUUID()},u);
before(async()=>{
 pg=new PGlite();await pg.exec(await readFile(new URL('../community-schema.sql',import.meta.url),'utf8'));
 api=createCommunity({db:rpc,registrationEnabled:true});
 alice=await api.execute('register',{username:'alice_test',nickname:'小金鱼',password:pass,agreed:true},'','a');
 bob=await api.execute('register',{username:'bob_test',nickname:'同学乙',password:pass,agreed:true},'','b');
 moderator=await api.execute('register',{username:'moderator_test',nickname:'管理员',password:pass,agreed:true},'','m');
 await pg.query("UPDATE public.hyt_members SET role='moderator' WHERE id=$1",[moderator.user.id]);
});
after(async()=>pg?.close());
test('password KDF is salted; database only holds hashed sessions and recovery codes',async()=>{
 const one=await hashPassword(pass),two=await hashPassword(pass);assert.notEqual(one,two);assert(await verifyPassword(pass,one));assert(!await verifyPassword('wrong',one));
 const db=await pg.query('SELECT password_hash,recovery_hash FROM public.hyt_members WHERE id=$1',[alice.user.id]);
 assert.notEqual(db.rows[0].password_hash,pass);assert.equal(db.rows[0].recovery_hash,digest(alice.recoveryCode));
 assert.equal((await pg.query('SELECT hash FROM public.hyt_sessions WHERE member_id=$1',[alice.user.id])).rows[0].hash,digest(alice.sessionToken));
});
test('independent app accounts reject incorrect passwords, duplicate names and client-selected roles',async()=>{
 await assert.rejects(execute('login',{username:'alice_test',password:'wrong-password'}),{code:'invalid_credentials'});
 await assert.rejects(execute('register',{username:'alice_test',nickname:'重复',password:pass,agreed:true}),{code:'username_unavailable'});
 const result=await execute('login',{username:'ALICE_TEST',password:pass,role:'moderator',id:moderator.user.id});assert.equal(result.user.id,alice.user.id);assert.equal(result.user.role,'member');
 await assert.rejects(execute('credentials',{username:'alice_test'}),{code:'not_found'});
 await assert.rejects(execute('session'),{code:'not_found'});
 await assert.rejects(execute('posts.list',{},null),{code:'session_expired'});
});
test('named posts use the app nickname and anonymous payloads contain no account identifiers',async()=>{
 const named=(await post('正常昵称发帖',false)).post;assert.equal(named.author.name,'小金鱼');
 const a=(await post('匿名一')).post,b=(await post('匿名二')).post;
 const read=(await execute('posts.get',{postId:a.id},bob)).post;
 for(const value of [alice.user.id,alice.user.username,alice.user.nickname,alice.sessionToken])assert(!JSON.stringify(read).includes(value));
 assert.notEqual(a.author.name,b.author.name);assert.equal(read.author.mine,false);assert.equal(a.author.mine,true);
 const c=(await comment(a.id,'楼主回复',false,alice)).comment;assert.equal(c.author.name,a.author.name);assert.equal(c.isOriginalPoster,true);assert.equal(c.author.anonymous,true);
 const hidden=(await comment(named.id,'昵称帖里匿名回复',true,alice)).comment;assert.equal(hidden.isOriginalPoster,false);
});
test('idempotent post/comment retries do not duplicate data and reject changed content',async()=>{
 const payload={body:'重试同一条帖子',anonymous:false,requestId:randomUUID()};
 const [a,b]=await Promise.all([execute('posts.create',payload),execute('posts.create',payload)]);assert.equal(a.post.id,b.post.id);
 await assert.rejects(execute('posts.create',{...payload,body:'改过的内容'}),{code:'request_conflict'});
 const body={postId:a.post.id,body:'同一评论',anonymous:true,requestId:randomUUID()};
 const c=await execute('comments.create',body,bob),d=await execute('comments.create',body,bob);assert.equal(c.comment.id,d.comment.id);
 const other=(await post('别的帖子')).post;await assert.rejects(execute('comments.create',{...body,postId:other.id},bob),{code:'request_conflict'});
 await assert.rejects(execute('comments.create',{...body,requestId:randomUUID(),postId:other.id,replyTo:c.comment.id},bob),{code:'reply_unavailable'});
});
test('ownership, reactions and thread deletion are enforced by PostgreSQL',async()=>{
 const p=(await post('权限测试')).post;await assert.rejects(execute('posts.delete',{postId:p.id},bob),{code:'forbidden'});
 let r=await execute('reactions.set',{postId:p.id,kind:'like',enabled:true},bob);assert.equal(r.post.likeCount,1);
 r=await execute('reactions.set',{postId:p.id,kind:'like',enabled:true},bob);assert.equal(r.post.likeCount,1);
 const c=(await comment(p.id,'将删除的评论')).comment;
 await execute('comments.delete',{postId:p.id,commentId:c.id},bob);
 assert.equal((await execute('posts.get',{postId:p.id})).comments[0].body,'这条评论已删除');
 await execute('posts.delete',{postId:p.id});await assert.rejects(execute('posts.get',{postId:p.id},bob),{code:'not_found'});
});
test('blocking anonymous content cannot reveal its author by hiding their named posts',async()=>{
 const anon=(await post('屏蔽匿名帖')).post,named=(await post('昵称保留',false)).post;
 await execute('blocks.set',{postId:anon.id},bob);
 await assert.rejects(execute('posts.get',{postId:anon.id},bob),{code:'not_found'});
 assert.equal((await execute('posts.get',{postId:named.id},bob)).post.author.name,alice.user.nickname);
 await execute('blocks.set',{postId:named.id},bob);
 const another=(await post('另一个匿名讨论')).post;
 assert.equal((await execute('posts.get',{postId:another.id},bob)).post.id,another.id);
});
test('reports are deduplicated and moderation requires a server-owned role',async()=>{
 const p=(await post('管理员处理',false,moderator)).post;
 await execute('reports.create',{postId:p.id,reason:'垃圾广告'},alice);await execute('reports.create',{postId:p.id,reason:'重复举报'},alice);
 await assert.rejects(execute('admin.reports',{},alice),{code:'forbidden'});
 const reports=(await execute('admin.reports',{},moderator)).reports;assert.equal(reports.length,1);
 await assert.rejects(execute('admin.resolve',{reportId:reports[0].id,decision:'remove',reason:'处理举报'},alice),{code:'forbidden'});
 await execute('admin.resolve',{reportId:reports[0].id,decision:'lock',reason:'讨论暂停'},moderator);
 await assert.rejects(comment(p.id,'锁帖以后'),{code:'post_locked'});
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM public.hyt_moderation')).rows[0].n,1);
});
test('registration gate and server-issued recovery revoke old sessions',async()=>{
 const closed=createCommunity({db:rpc});await assert.rejects(closed.execute('register',{username:'closed_name',nickname:'测试',password:pass,agreed:true},'','closed'),{code:'registration_closed'});
 const user=await execute('register',{username:'recover_test',nickname:'恢复测试',password:pass,agreed:true});
 await assert.rejects(execute('recover',{username:'recover_test',recoveryCode:'x'.repeat(43),password:pass}),{code:'invalid_credentials'});
 const reset=await execute('recover',{username:'recover_test',recoveryCode:user.recoveryCode,password:'new-password-long'});
 await assert.rejects(execute('me',{},user),{code:'session_expired'});assert.equal((await execute('me',{},reset)).user.id,user.user.id);
 await assert.rejects(execute('recover',{username:'recover_test',recoveryCode:user.recoveryCode,password:pass}),{code:'invalid_credentials'});
 await execute('account.delete',{password:'new-password-long'},reset);await assert.rejects(execute('me',{},reset),{code:'session_expired'});
});
test('rate limit is persistent and validates invalid input before SQL mutation',async()=>{
 for(let i=0;i<2;i++)assert.equal((await rpc('rate',{key:'test-rate',limit:2,seconds:60},'')).status,200);
 assert.equal((await rpc('rate',{key:'test-rate',limit:2,seconds:60},'')).status,429);
 for(const body of ['', 'x'.repeat(3001)])await assert.rejects(post(body),{code:'invalid_request'});
 await assert.rejects(execute('posts.create',{body:'文字',anonymous:'true',requestId:randomUUID()}),{code:'invalid_request'});
 await assert.rejects(execute('posts.list',{beforeId:randomUUID()}),{code:'invalid_request'});
});
test('HTTP boundary accepts JSON only, rejects arbitrary actions and never returns internal credentials',async()=>{
 const server=createServer(api,{allowedOrigins:['http://localhost']});await new Promise(r=>server.listen(0,'127.0.0.1',r));const root=`http://127.0.0.1:${server.address().port}`;
 try{
  let r=await fetch(root+'/v1/me',{method:'POST',headers:{Origin:'https://untrusted.invalid','Content-Type':'application/json'},body:'{}'});assert.equal(r.status,403);
  r=await fetch(root+'/v1/me',{method:'POST',body:'{}'});assert.equal(r.status,415);
  r=await fetch(root+'/v1/session',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+alice.sessionToken},body:'{}'});assert.equal(r.status,404);
  r=await fetch(root+'/v1/me',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+alice.sessionToken},body:'{}'});assert.equal(r.status,200);
  const b=await r.json();assert.equal(b.user.username,'alice_test');assert(!JSON.stringify(b).includes('password'));assert.equal(r.headers.get('cache-control'),'no-store');
 }finally{await new Promise(r=>server.close(r));}
});
