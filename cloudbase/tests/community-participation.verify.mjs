import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import jpeg from '../functions/community/node_modules/jpeg-js/index.js';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,a,b;const objects=new Map();const password='synthetic-participation-password';
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const call=(who,action,body={})=>api.execute(action,body,who.sessionToken,'participation');
const post=(who=a,anonymous=false,extra={})=>call(who,'posts.create',{body:'合成帖子 '+randomUUID(),anonymous,requestId:randomUUID(),...extra}).then(r=>r.post);
const data=jpeg.encode({width:8,height:4,data:Buffer.alloc(8*4*4,200)},80).data.toString('base64');
const upload=(who=a,purpose='avatar',requestId=randomUUID())=>call(who,'media.upload',{data,purpose,requestId}).then(r=>r.image);
const rpc=async(action,body,hash)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result;
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({registrationEnabled:true,db:rpc,storage:{put:async(k,v)=>objects.set(k,v),url:async k=>'https://fixture.invalid/'+k,remove:async k=>objects.delete(k)}});const register=username=>api.execute('register',{username,nickname:username,password,agreed:true},'',username);a=await register('avatar_author');b=await register('response_reader');});
afterEach(async()=>{await pg.exec('UPDATE hyt_members SET avatar_id=NULL,banned_until=NULL; DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; TRUNCATE hyt_posts CASCADE;');objects.clear();});
after(async()=>pg.close());

test('avatar preview upload is bounded, metadata-free square and only becomes visible after confirmation',async()=>{
 const image=await upload();assert.equal(image.width,4);assert.equal(image.height,4);assert(!('key' in image));assert.equal((await call(a,'me')).user.avatar,null);
 const bytes=[...objects.values()][0];const decoded=jpeg.decode(bytes);assert.equal(decoded.width,decoded.height);
 const result=await call(a,'avatar.set',{imageId:image.id});assert.equal(result.user.avatar.id,image.id);assert(result.user.avatar.url.startsWith('https://fixture.invalid/'));
 const profile=(await call(b,'profile.get',{memberId:a.user.id})).profile;assert.equal(profile.avatar.id,image.id);assert(!JSON.stringify(profile).includes('key'));
 await assert.rejects(call(a,'avatar.set',{}),{code:'invalid_request'});
});
test('anonymous posts, replies and generic reaction notifications never include the personal avatar',async()=>{
 const image=await upload();await call(a,'avatar.set',{imageId:image.id});const named=await post(),anon=await post(a,true);
 assert.equal(named.author.avatar.id,image.id);assert(!('avatar' in anon.author));assert(!('id' in anon.author));
 const reply=(await call(a,'comments.create',{postId:anon.id,body:'匿名楼主回复',anonymous:false,requestId:randomUUID()})).comment;assert(!('avatar' in reply.author));
 const other=await post(b);await call(a,'responses.set',{postId:other.id,kind:'hug'});
 const n=(await call(b,'notifications.list')).notifications.find(n=>n.kind==='post_response');assert.equal(n.actor.name,'一位同学');assert(!JSON.stringify(n).includes(image.id));assert(!JSON.stringify(n).includes(a.user.id));
});
test('avatar ownership, purpose and ready-state cannot be bypassed, active images cannot be discarded',async()=>{
 const image=await upload();await assert.rejects(call(b,'avatar.set',{imageId:image.id}),{code:'image_unavailable'});
 const postImage=await upload(a,'post');await assert.rejects(call(a,'avatar.set',{imageId:postImage.id}),{code:'image_unavailable'});
 await assert.rejects(post(a,false,{images:[image.id]}),{code:'image_unavailable'});
 await call(a,'avatar.set',{imageId:image.id});await call(a,'media.discard',{imageId:image.id});assert.equal((await call(a,'me')).user.avatar.id,image.id);
 const unready=await upload();await pg.query('UPDATE hyt_media SET ready=false WHERE id=$1',[unready.id]);await assert.rejects(call(a,'avatar.set',{imageId:unready.id}),{code:'image_unavailable'});
});
test('replacement retries, removal and cleanup preserve active avatars older than seven days',async()=>{
 const first=await upload();await call(a,'avatar.set',{imageId:first.id});await pg.query("UPDATE hyt_media SET created_at=now()-interval '10 days' WHERE id=$1",[first.id]);
 assert.equal((await rpc('media.cleanup',{},'')).images.length,0);const next=await upload();await call(a,'avatar.set',{imageId:next.id});await call(a,'avatar.set',{imageId:next.id});
 assert.equal((await call(a,'me')).user.avatar.id,next.id);assert(!objects.has(first.id+'.jpg'));
 await call(a,'avatar.set',{imageId:null});await call(a,'avatar.set',{imageId:null});assert.equal((await call(a,'me')).user.avatar,null);assert(!objects.has(next.id+'.jpg'));
});
test('purpose is immutable across upload retries, failed storage never replaces the previous avatar',async()=>{
 const id=randomUUID(),first=await upload(a,'avatar',id);await call(a,'avatar.set',{imageId:first.id});
 await assert.rejects(upload(a,'post',id),{code:'request_conflict'});
 const broken=createCommunity({db:rpc,storage:{put:async()=>{throw Error('fixture offline');},url:async()=>''}});
 await assert.rejects(broken.execute('media.upload',{data,purpose:'avatar',requestId:randomUUID()},a.sessionToken));
 assert.equal((await call(a,'me')).user.avatar.id,first.id);
});
test('responses select, switch and cancel one choice per member, retries do not inflate counts',async()=>{
 const p=await post();let r;
 for(let i=0;i<2;i++)r=await call(b,'responses.set',{postId:p.id,kind:'same'});assert.deepEqual(r.post.responseCounts,{same:1});assert.equal(r.post.myResponse,'same');
 r=await call(b,'responses.set',{postId:p.id,kind:'hug'});assert.deepEqual(r.post.responseCounts,{hug:1});
 const other=(await call(a,'posts.get',{postId:p.id})).post;assert.equal(other.myResponse,null);assert.deepEqual(other.responseCounts,{hug:1});
 for(let i=0;i<2;i++)r=await call(b,'responses.set',{postId:p.id,kind:null});assert.deepEqual(r.post.responseCounts,{});assert.equal(r.post.myResponse,null);
 await assert.rejects(call(b,'responses.set',{postId:p.id,kind:'invalid'}),{code:'invalid_request'});
});
test('one generic notice tracks the current response without repeated unread alerts',async()=>{
 const p=await post();await call(b,'responses.set',{postId:p.id,kind:'same'});
 const n=(await call(a,'notifications.list',{filter:'likes'})).notifications[0];assert.equal(n.kind,'post_response');assert.equal(n.excerpt,'我也一样');
 await call(a,'notifications.read',{ids:[n.id]});await call(b,'responses.set',{postId:p.id,kind:'useful'});
 let rows=(await call(a,'notifications.list')).notifications;assert.equal(rows.length,1);assert.equal(rows[0].id,n.id);assert(rows[0].readAt);assert.equal(rows[0].excerpt,'有用');
 await call(b,'responses.set',{postId:p.id,kind:null});assert.equal((await call(a,'notifications.list')).notifications.length,0);
 await call(b,'responses.set',{postId:p.id,kind:'hug'});assert.equal((await call(a,'notifications.unread')).unreadCount,0);
 await call(a,'responses.set',{postId:p.id,kind:'hug'});assert.equal((await call(a,'notifications.list')).notifications.length,1);
});
test('blocked, deleted and muted content obey the existing access rules',async()=>{
 const p=await post();await call(b,'responses.set',{postId:p.id,kind:'hug'});
 const reply=(await call(b,'comments.create',{postId:p.id,body:'公开评论',anonymous:false,requestId:randomUUID()})).comment;
 await call(a,'blocks.set',{postId:p.id,commentId:reply.id});assert.equal((await call(a,'notifications.unread')).unreadCount,0);
 await pg.query("UPDATE hyt_members SET banned_until=now()+interval '1 day' WHERE id=$1",[b.user.id]);await assert.rejects(call(b,'responses.set',{postId:p.id,kind:'same'}),{code:'account_muted'});
 await pg.query('UPDATE hyt_members SET banned_until=NULL WHERE id=$1',[b.user.id]);await call(a,'posts.delete',{postId:p.id});await assert.rejects(call(b,'responses.set',{postId:p.id,kind:'same'}),{code:'not_found'});
});
test('repeat migration preserves old ids, avatar, response, read status and private table permissions',async()=>{
 const image=await upload();await call(a,'avatar.set',{imageId:image.id});const p=await post();await call(b,'responses.set',{postId:p.id,kind:'useful'});const n=(await call(a,'notifications.list')).notifications[0];await call(a,'notifications.read',{ids:[n.id]});
 await pg.exec(schema);assert.equal((await call(a,'me')).user.avatar.id,image.id);assert.equal((await call(b,'posts.get',{postId:p.id})).post.myResponse,'useful');assert((await call(a,'notifications.list')).notifications[0].readAt);
 await pg.exec('CREATE ROLE participation_client; SET ROLE participation_client;');await assert.rejects(pg.query('SELECT * FROM hyt_responses'));await assert.rejects(pg.query('SELECT hyt_avatar_json($1)',[a.user.id]));await pg.exec('RESET ROLE;');
 assert.equal(api.config().schema,4);assert.equal(api.config().responsesEnabled,true);assert.equal(createCommunity({db:rpc}).config().avatarsEnabled,false);
});
