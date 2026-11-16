import {test,before,after,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import jpeg from '../functions/community/node_modules/jpeg-js/index.js';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,a,b,c;const objects=new Map(),password='synthetic-poll-comment-password';
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const rpc=async(action,body,hash)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),hash])).rows[0].result;
const call=(who,action,body={})=>api.execute(action,body,who.sessionToken,'polls-comments');
const definition={question:'今晚吃什么？',options:['面条','米饭','饺子'],durationHours:24};
const post=(who=a,extra={})=>call(who,'posts.create',{body:'',anonymous:false,requestId:randomUUID(),poll:definition,...extra}).then(r=>r.post);
const comment=(who,p,extra={})=>call(who,'comments.create',{postId:p.id,body:'',anonymous:false,requestId:randomUUID(),...extra}).then(r=>r.comment);
const data=jpeg.encode({width:8,height:4,data:Buffer.alloc(8*4*4,180)},80).data.toString('base64');
const upload=(who=a,purpose='comment')=>call(who,'media.upload',{data,purpose,requestId:randomUUID()}).then(r=>r.image);
const vote=(who,p,optionId)=>call(who,'polls.vote',{postId:p.id,optionId}).then(r=>r.post);
const visible=r=>{assert(!JSON.stringify(r).includes('"key"'));assert(!JSON.stringify(r).includes('member_id'));};
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({registrationEnabled:true,db:rpc,storage:{put:async(k,v)=>objects.set(k,v),url:async k=>'https://fixture.invalid/'+k,remove:async k=>objects.delete(k)}});const reg=username=>api.execute('register',{username,nickname:username,password,agreed:true},'',username);a=await reg('poll_author');b=await reg('poll_reader');c=await reg('comment_reader');});
afterEach(async()=>{await pg.exec("UPDATE hyt_members SET banned_until=NULL,role='member'; DELETE FROM hyt_community_rate; DELETE FROM hyt_blocks; DELETE FROM hyt_hidden_threads; TRUNCATE hyt_posts CASCADE;");objects.clear();});
after(async()=>pg.close());
test('poll creation validates compact options and preserves plain-post compatibility and search',async()=>{
 const p=await post();assert.equal(p.body,'[投票] 今晚吃什么？');assert.equal(p.poll.options.length,3);assert.equal(p.poll.total,0);assert.equal(p.poll.myOptionId,null);assert.equal(p.poll.closed,false);assert.equal((await call(b,'posts.list',{query:'今晚吃什么'})).posts[0].id,p.id);
 const plain=await post(a,{poll:null,body:'普通帖子'});assert.equal(plain.poll,null);
 for(const poll of [{...definition,options:['一个']},{...definition,options:[' A ','a']},{...definition,options:Array(7).fill('选项')},{...definition,durationHours:0},{...definition,question:''},{...definition,options:['x'.repeat(41),'y']}])await assert.rejects(post(a,{poll}),{code:'invalid_request'});
});
test('one private vote per account supports idempotent select, change and cancel without notifications',async()=>{
 const p=await post();let r=await vote(b,p,'0');assert.equal(r.poll.total,1);assert.equal(r.poll.myOptionId,'0');assert.equal((await vote(b,p,'0')).poll.total,1);
 r=await vote(b,p,'2');assert.deepEqual(r.poll.options.map(x=>x.count),[0,0,1]);await vote(c,p,'1');r=await vote(b,p,null);assert.equal(r.poll.total,1);assert.equal(r.poll.myOptionId,null);assert.equal((await call(a,'notifications.list')).notifications.length,0);assert.equal((await call(b,'posts.get',{postId:p.id})).post.watching,false);visible(r);
});
test('anonymous polls expose aggregates and only the current viewer choice',async()=>{
 const p=await post(a,{anonymous:true});await vote(b,p,'1');const r=(await call(c,'posts.get',{postId:p.id})).post;assert.equal(r.poll.myOptionId,null);assert(!JSON.stringify(r).includes(a.user.id));assert(!JSON.stringify(r).includes(b.user.id));assert.equal(r.poll.total,1);visible(r);
 for(const optionId of ['6',1,undefined,{},'1 OR 1=1'])await assert.rejects(vote(c,p,optionId),{code:'invalid_request'});
 await assert.rejects(vote(c,p,'5'),{code:'invalid_request'});
});
test('closed, locked, blocked, hidden and muted polls enforce existing access boundaries',async()=>{
 const p=await post();await vote(b,p,'1');await pg.query('UPDATE hyt_polls SET closes_at=now()-interval \'1 second\' WHERE post_id=$1',[p.id]);await assert.rejects(vote(b,p,null),{code:'poll_closed'});assert.equal((await call(b,'posts.get',{postId:p.id})).post.poll.closed,true);
 await pg.query('UPDATE hyt_polls SET closes_at=now()+interval \'1 day\' WHERE post_id=$1',[p.id]);await pg.query('UPDATE hyt_posts SET locked=true WHERE id=$1',[p.id]);await assert.rejects(vote(c,p,'0'),{code:'post_locked'});await pg.query('UPDATE hyt_posts SET locked=false WHERE id=$1',[p.id]);
 await call(c,'blocks.set',{postId:p.id});await assert.rejects(vote(c,p,'0'),{code:'not_found'});await pg.query('UPDATE hyt_members SET banned_until=now()+interval \'1 hour\' WHERE id=$1',[b.user.id]);await assert.rejects(vote(b,p,'0'),{code:'account_muted'});
 const anon=await post(a,{anonymous:true});await call(c,'blocks.set',{postId:anon.id});await assert.rejects(vote(c,anon,'0'),{code:'not_found'});
});
test('poll publication retries preserve deadline and reject definition changes',async()=>{
 const requestId=randomUUID(),p=await post(a,{requestId});await vote(b,p,'0');const again=await post(a,{requestId});assert.equal(again.id,p.id);assert.equal(again.poll.closesAt,p.poll.closesAt);assert.equal(again.poll.total,1);
 await assert.rejects(post(a,{requestId,poll:{...definition,options:['新','旧']}}),{code:'request_conflict'});await assert.rejects(post(a,{requestId,poll:null}),{code:'invalid_request'});
});
test('schema reapplication retains votes and private access restrictions; account deletion removes votes',async()=>{
 const u=await api.execute('register',{username:'temporary_voter',nickname:'临时投票者',password,agreed:true},'','new');const p=await post();await vote(u,p,'2');await pg.exec(schema);assert.equal((await call(u,'posts.get',{postId:p.id})).post.poll.myOptionId,'2');await call(u,'account.delete',{password});assert.equal((await call(a,'posts.get',{postId:p.id})).post.poll.total,0);
 const rows=(await pg.query("SELECT relname,relrowsecurity FROM pg_class WHERE relname IN ('hyt_polls','hyt_poll_votes')")).rows;assert.equal(rows.length,2);assert(rows.every(x=>x.relrowsecurity));assert.equal(api.config().schema,7);assert.equal(api.config().pollsEnabled,true);
});
test('image-only root and nested comments sign only projected media in detail, context and like responses',async()=>{
 const p=await post(),image=await upload(b),root=await comment(b,p,{images:[image.id]});assert.equal(root.body,'[图片]');assert(root.images[0].url);visible(root);
 const next=await upload(c),reply=await comment(c,p,{images:[next.id],replyTo:root.id,anonymous:true});assert.equal(reply.author.anonymous,true);assert(!('id' in reply.author));
 const detail=await call(a,'posts.get',{postId:p.id,threaded:true});assert.equal(detail.post.images.length,0);assert(detail.comments[0].replies[0].images[0].url);visible(detail);
 const context=await call(a,'comments.context',{postId:p.id,commentId:reply.id});assert(context.context.images[0].url);assert(context.context.replies[0].images[0].url);visible(context);
 assert((await call(a,'comments.like',{postId:p.id,commentId:reply.id,enabled:true})).comment.images[0].url);assert.equal((await call(a,'notifications.list')).notifications[0].excerpt,'[图片]');
});
test('comment images enforce ownership, purpose, maximum count and single-comment binding',async()=>{
 const p=await post(),img=await upload(b),avatar=await upload(b,'avatar'),postImage=await upload(b,'post');
 for(const image of [avatar,postImage])await assert.rejects(comment(b,p,{images:[image.id]}),{code:'image_unavailable'});
 await assert.rejects(comment(a,p,{images:[img.id]}),{code:'image_unavailable'});await assert.rejects(comment(b,p,{images:[img.id,img.id]}),{code:'invalid_request'});
 await assert.rejects(comment(b,p,{images:Array.from({length:4},()=>randomUUID())}),{code:'invalid_request'});await assert.rejects(comment(b,p),{code:'invalid_request'});
 await comment(b,p,{images:[img.id]});await assert.rejects(comment(b,p,{images:[img.id]}),{code:'image_unavailable'});await call(b,'media.discard',{imageId:img.id});assert((await call(a,'media.url',{postId:p.id,imageId:img.id})).image.url);
});
test('comment retry is idempotent, validates unchanged attachments and never attaches comment images to post',async()=>{
 const p=await post(),img=await upload(b),requestId=randomUUID();const first=await comment(b,p,{images:[img.id],requestId});const second=await comment(b,p,{images:[img.id],requestId});assert.equal(first.id,second.id);await assert.rejects(comment(b,p,{images:[],body:'改动',requestId}),{code:'request_conflict'});
 await assert.rejects(post(b,{body:'图片',poll:null,images:[img.id]}),{code:'image_unavailable'});assert.equal((await call(a,'posts.get',{postId:p.id})).post.commentCount,1);
});
test('comment and post deletion hide images and revoke renewed image access',async()=>{
 const p=await post(),img=await upload(b),root=await comment(b,p,{images:[img.id]});await call(b,'comments.delete',{postId:p.id,commentId:root.id});const r=await call(a,'posts.get',{postId:p.id,threaded:true});assert.deepEqual(r.comments[0].images,[]);await assert.rejects(call(a,'media.url',{postId:p.id,imageId:img.id}),{code:'not_found'});assert.equal(objects.size,0);
 const next=await upload(b);await comment(b,p,{images:[next.id]});await call(a,'posts.delete',{postId:p.id});await assert.rejects(call(b,'media.url',{postId:p.id,imageId:next.id}),{code:'not_found'});assert.equal(objects.size,0);
});
test('blocking a root author denies nested media probing while anonymous hiding stays thread-scoped',async()=>{
 const p=await post(),root=await comment(b,p,{body:'根评论'}),img=await upload(c),reply=await comment(c,p,{images:[img.id],replyTo:root.id});await call(a,'blocks.set',{postId:p.id,commentId:root.id});await assert.rejects(call(a,'media.url',{postId:p.id,imageId:img.id}),{code:'not_found'});await assert.rejects(call(a,'comments.context',{postId:p.id,commentId:reply.id}),{code:'not_found'});
 await call(a,'blocks.clear');const anonymous=await comment(c,p,{body:'匿名',anonymous:true});await call(b,'blocks.set',{postId:p.id,commentId:anonymous.id});await assert.rejects(call(b,'media.url',{postId:p.id,imageId:img.id}),{code:'not_found'});
});
test('moderator removal revokes comment images without altering sibling replies',async()=>{
 const p=await post(),img=await upload(b),root=await comment(b,p,{images:[img.id]}),child=await comment(c,p,{body:'保留的回复',replyTo:root.id});await call(a,'reports.create',{postId:p.id,commentId:root.id,reason:'合成测试举报'});await pg.query("UPDATE hyt_members SET role='moderator' WHERE id=$1",[a.user.id]);const report=(await call(a,'admin.reports')).reports[0];await call(a,'admin.resolve',{reportId:report.id,decision:'remove',reason:'合成测试处理'});await assert.rejects(call(c,'media.url',{postId:p.id,imageId:img.id}),{code:'not_found'});assert.equal((await call(c,'comments.context',{postId:p.id,commentId:child.id})).context.replies[0].body,'保留的回复');assert.equal(objects.size,0);
});
