import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,a,b,c;
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const password='synthetic-following-password';
const call=(who,action,body={})=>api.execute(action,body,who.sessionToken,'following');
const post=(who,extra={})=>call(who,'posts.create',{body:'合成关注帖子',anonymous:false,requestId:randomUUID(),...extra}).then(r=>r.post);
const follow=(who,target,enabled=true)=>call(who,'follows.set',{memberId:target.user.id,enabled});
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({registrationEnabled:true,db:async(action,body,hash)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result});const register=username=>api.execute('register',{username,nickname:username,password,agreed:true},'',username);a=await register('follow_author');b=await register('follow_reader');c=await register('follow_other');});
afterEach(async()=>pg.exec('DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; DELETE FROM hyt_follows; TRUNCATE hyt_posts CASCADE;'));
after(async()=>pg.close());
test('following is idempotent, owned by the viewer, and projects no private account or follower graph',async()=>{
 assert((await follow(b,a)).profile.following);assert((await follow(b,a)).profile.following);
 assert.equal((await pg.query('SELECT count(*) AS n FROM hyt_follows')).rows[0].n,1);
 const profile=(await call(b,'profile.get',{memberId:a.user.id})).profile;assert(profile.following);assert(!('username' in profile));assert(!('followers' in profile));
 assert.equal((await call(c,'profile.get',{memberId:a.user.id})).profile.following,false);
 const list=(await call(b,'follows.list',{memberId:a.user.id})).following;assert.deepEqual(list.map(p=>p.id),[a.user.id]);assert(!('username' in list[0]));assert(!('postCount' in list[0]));
 assert.deepEqual((await call(a,'follows.list',{memberId:b.user.id})).following,[]);
 assert.equal((await follow(b,a,false)).profile.following,false);assert.equal((await follow(b,a,false)).profile.following,false);
 assert.deepEqual((await call(b,'notifications.list')).notifications,[]);
});
test('following feed contains only followed public posts and composes with sections, tags and search',async()=>{
 const named=await post(a,{category:'entertainment',interest:'games',body:'合成游戏讨论'});await post(a,{anonymous:true,category:'treehole'});await post(c);await follow(b,a);
 for(const filter of [{},{section:'entertainment',interest:'games',query:'游戏'}])assert.deepEqual((await call(b,'posts.list',{scope:'following',...filter})).posts.map(p=>p.id),[named.id]);
 assert.deepEqual((await call(b,'posts.list',{scope:'following',section:'treehole'})).posts,[]);
 assert.deepEqual((await call(c,'posts.list',{scope:'following',memberId:b.user.id})).posts,[]);
 await follow(b,a,false);assert.deepEqual((await call(b,'posts.list',{scope:'following'})).posts,[]);
});
test('named blocking removes both follow edges and unblocking never restores them',async()=>{
 const p=await post(a),q=await post(b);await follow(b,a);await follow(a,b);
 await call(b,'blocks.set',{postId:p.id});assert.equal((await pg.query('SELECT count(*) AS n FROM hyt_follows')).rows[0].n,0);
 assert.deepEqual((await call(a,'follows.list')).following,[]);assert.deepEqual((await call(b,'posts.list',{scope:'following'})).posts,[]);
 await assert.rejects(follow(b,a),{code:'not_found'});await assert.rejects(follow(a,b),{code:'not_found'});
 await call(b,'blocks.clear');assert.deepEqual((await call(a,'posts.list',{scope:'following'})).posts,[]);assert.equal((await call(a,'profile.get',{memberId:b.user.id})).profile.following,false);
 await follow(a,b);assert.deepEqual((await call(a,'posts.list',{scope:'following'})).posts.map(p=>p.id),[q.id]);
});
test('hiding an anonymous discussion does not reveal its author through follow state',async()=>{
 const named=await post(a),anon=await post(a,{anonymous:true});await follow(b,a);
 await call(b,'blocks.set',{postId:anon.id});assert((await call(b,'profile.get',{memberId:a.user.id})).profile.following);
 assert.deepEqual((await call(b,'posts.list',{scope:'following'})).posts.map(p=>p.id),[named.id]);
 const reply=(await call(a,'comments.create',{postId:named.id,body:'合成匿名回复',anonymous:true,requestId:randomUUID()})).comment;
 assert(reply.author.anonymous);assert(!('id' in reply.author));assert(!('following' in reply.author));
});
test('private following list paginates ties without duplicates and excludes blocked/deleted users',async()=>{
 const expected=[];for(let i=0;i<25;i++){const id=randomUUID();expected.push(id);await pg.query("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash) VALUES($1,$2,$2,'test','test')",[id,'page_'+id]);await pg.query("INSERT INTO hyt_follows(member_id,followed_id,created_at) VALUES($1,$2,'2026-01-01')",[b.user.id,id]);}
 let next={},ids=[];do{const r=await call(b,'follows.list',next);assert(r.following.length<=20);ids.push(...r.following.map(p=>p.id));next=r.next;}while(next);assert.equal(ids.length,25);assert.deepEqual(new Set(ids),new Set(expected));
 await pg.query('UPDATE hyt_members SET deleted_at=now() WHERE id=$1',[expected[0]]);await pg.query('INSERT INTO hyt_blocks VALUES($1,$2)',[expected[1],b.user.id]);
 next={};ids=[];do{const r=await call(b,'follows.list',next);ids.push(...r.following.map(p=>p.id));next=r.next;}while(next);assert.equal(ids.length,23);assert(!ids.includes(expected[0]));assert(!ids.includes(expected[1]));
});
test('following feed paginates latest and hot while hidden/deleted posts stay excluded',async()=>{
 await follow(b,a);for(let i=0;i<26;i++)await pg.query("INSERT INTO hyt_posts(author_id,body,anonymous,request_id,created_at) VALUES($1,$2,false,$3,now()-($4||' seconds')::interval)",[a.user.id,'合成分页 '+i,randomUUID(),String(i)]);
 for(const sort of ['latest','hot']){let next={},ids=[];do{const r=await call(b,'posts.list',{scope:'following',sort,...next});ids.push(...r.posts.map(p=>p.id));next=r.next;}while(next);assert.equal(ids.length,26);assert.equal(new Set(ids).size,26);}
 const first=(await call(b,'posts.list',{scope:'following'})).posts[0];await call(a,'posts.delete',{postId:first.id});assert(!(await call(b,'posts.list',{scope:'following'})).posts.some(p=>p.id===first.id));
});
test('account deletion clears incoming and outgoing follow edges',async()=>{
 const d=await api.execute('register',{username:'delete_'+randomUUID().slice(0,8),nickname:'合成注销',password,agreed:true},'','delete');await follow(b,d);await follow(d,a);await call(d,'account.delete',{password});
 assert.equal((await pg.query('SELECT count(*) AS n FROM hyt_follows WHERE member_id=$1 OR followed_id=$1',[d.user.id])).rows[0].n,0);assert.deepEqual((await call(b,'follows.list')).following,[]);await assert.rejects(follow(b,d),{code:'not_found'});
});
test('capability, argument validation and additive migration protect existing content and private edges',async()=>{
 const p=await post(a,{category:'study',anonymous:true});await follow(b,a);await call(b,'reactions.set',{postId:p.id,kind:'save',enabled:true});
 for(const payload of [{memberId:b.user.id,enabled:true},{memberId:a.user.id,enabled:'true'},{memberId:'匿名同学',enabled:true}])await assert.rejects(call(b,'follows.set',payload),{code:'invalid_request'});
 await assert.rejects(call(b,'follows.list',{beforeTime:'invalid',beforeId:a.user.id}),{code:'invalid_request'});
 await pg.exec("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF; END $$;");await pg.exec(schema);
 assert((await call(b,'profile.get',{memberId:a.user.id})).profile.following);assert.equal((await call(b,'posts.list',{scope:'saved'})).posts[0].id,p.id);
 assert.equal((await pg.query("SELECT has_table_privilege('anon','hyt_follows','SELECT') AS allowed")).rows[0].allowed,false);
 assert.equal(api.config().schema,12);assert.equal(api.config().followingEnabled,true);
});
