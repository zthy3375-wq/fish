import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,a,b;
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const call=(who,action,body={})=>api.execute(action,body,who.sessionToken,'discovery');
const post=(category='daily',extra={})=>call(a,'posts.create',{body:'合成发现帖子',category,anonymous:false,requestId:randomUUID(),...extra}).then(r=>r.post);
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({registrationEnabled:true,db:async(action,body,hash)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result});const register=username=>api.execute('register',{username,nickname:username,password:'synthetic-discovery-password',agreed:true},'',username);a=await register('discovery_author');b=await register('discovery_reader');});
afterEach(async()=>pg.exec('DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; TRUNCATE hyt_posts CASCADE;'));
after(async()=>pg.close());
test('campus section aggregates legacy study/help without changing their ids, category or anonymity',async()=>{
 const posts=await Promise.all(['daily','help','study','buddies'].map(category=>post(category,{anonymous:category==='study'})));
 const daily=(await call(b,'posts.list',{section:'daily'})).posts;
 assert.deepEqual(new Set(daily.map(p=>p.id)),new Set(posts.slice(0,3).map(p=>p.id)));
 assert.equal(daily.find(p=>p.category==='study').anonymous,true);
 assert.deepEqual((await call(b,'posts.list',{category:'daily'})).posts.map(p=>p.id),[posts[0].id]);
 assert.deepEqual((await call(b,'posts.list',{section:'daily',category:'study'})).posts.map(p=>p.id),[posts[2].id]);
 assert.equal((await call(b,'posts.list',{section:'treehole'})).posts.length,0);
});
test('interest tags filter together with search and personal collections',async()=>{
 const games=await post('entertainment',{interest:'games',body:'合成游戏讨论'}),music=await post('entertainment',{interest:'music',body:'合成音乐讨论'});
 await post('entertainment');await call(b,'reactions.set',{postId:games.id,kind:'save',enabled:true});
 for(const extra of [{},{query:'游戏'},{scope:'saved'},{scope:'author',memberId:a.user.id}])assert.deepEqual((await call(b,'posts.list',{section:'entertainment',interest:'games',...extra})).posts.map(p=>p.id),[games.id]);
 assert.equal((await call(b,'posts.list',{section:'entertainment',interest:'games',query:'音乐'})).posts.length,0);
 assert.equal((await call(b,'posts.get',{postId:music.id})).post.interest,'music');
 assert.equal((await call(b,'posts.list',{section:'entertainment'})).posts.length,3);
});
test('anonymous section requires anonymity; other sections retain optional identity',async()=>{
 await assert.rejects(post('treehole'),{code:'invalid_request'});
 const anon=await post('treehole',{anonymous:true});assert(anon.anonymous);assert(!('id' in anon.author));assert(!('avatar' in anon.author));
 const reply=(await call(b,'comments.create',{postId:anon.id,body:'树洞内回复',anonymous:false,requestId:randomUUID()})).comment;assert(reply.author.anonymous);assert(!('id' in reply.author));assert(!('avatar' in reply.author));
 const notice=(await call(a,'notifications.list')).notifications[0];assert(notice.actor.anonymous);assert(!('id' in notice.actor));
 const named=await post('entertainment',{interest:'photo'}),optional=await post('entertainment',{anonymous:true,interest:'photo'});
 assert(named.author.id);assert(!('id' in optional.author));
 const profile=(await call(b,'posts.list',{scope:'author',memberId:a.user.id})).posts;assert.deepEqual(profile.map(p=>p.id),[named.id]);
});
test('unknown tags, cross-section tags and malformed discovery filters are rejected',async()=>{
 for(const [category,extra] of [['entertainment',{interest:'unknown'}],['daily',{interest:'games'}],['unknown',{}],['treehole',{anonymous:true,interest:'games'}],['entertainment',{interest:[]}]] )await assert.rejects(post(category,extra),{code:'invalid_request'});
 for(const filter of [{section:'unknown'},{section:'daily',interest:'games'},{section:'entertainment',interest:'unknown'}])await assert.rejects(call(b,'posts.list',filter),{code:'invalid_request'});
});
test('publication retries compare tags and do not create duplicate posts or watches',async()=>{
 const requestId=randomUUID(),p=await post('entertainment',{interest:'games',requestId});
 assert.equal((await post('entertainment',{interest:'games',requestId})).id,p.id);
 await assert.rejects(post('entertainment',{interest:'music',requestId}),{code:'request_conflict'});
 assert.equal((await call(a,'posts.list',{scope:'watching'})).posts.length,1);
});
test('tag-filtered latest/hot pagination retains scope and visits each matching post once',async()=>{
 for(let i=0;i<52;i++)await pg.query("INSERT INTO hyt_posts(author_id,body,anonymous,request_id,category,interest,created_at) VALUES($1,$2,false,$3,'entertainment',$4,now()-($5||' seconds')::interval)",[a.user.id,'合成分页 '+i,randomUUID(),i%2?'games':'music',String(i)]);
 for(const sort of ['latest','hot']){let next={},ids=[];do{const r=await call(b,'posts.list',{section:'entertainment',interest:'games',sort,...next});assert(r.posts.every(p=>p.interest==='games'));ids.push(...r.posts.map(p=>p.id));next=r.next;}while(next);assert.equal(ids.length,26);assert.equal(new Set(ids).size,26);}
});
test('hidden and deleted content stays excluded from all new discovery filters',async()=>{
 const p=await post('entertainment',{interest:'games'});await call(b,'blocks.set',{postId:p.id});assert.equal((await call(b,'posts.list',{section:'entertainment',interest:'games'})).posts.length,0);
 await call(a,'posts.delete',{postId:p.id});assert.equal((await call(a,'posts.list',{section:'entertainment'})).posts.length,0);
});
test('repeat schema upgrade preserves legacy content, saved state and notification reads',async()=>{
 const p=await post('study',{anonymous:true});await call(b,'reactions.set',{postId:p.id,kind:'save',enabled:true});await call(b,'responses.set',{postId:p.id,kind:'useful'});
 const n=(await call(a,'notifications.list')).notifications[0];await call(a,'notifications.read',{ids:[n.id]});await pg.exec('ALTER TABLE hyt_posts DROP COLUMN interest');await pg.exec(schema);
 const saved=(await call(b,'posts.list',{section:'daily',scope:'saved'})).posts[0];assert.equal(saved.id,p.id);assert.equal(saved.category,'study');assert.equal(saved.interest,'');assert(saved.anonymous);assert((await call(a,'notifications.list')).notifications[0].readAt);
 assert.equal(api.config().schema,11);assert.equal(api.config().discoveryEnabled,true);
});
