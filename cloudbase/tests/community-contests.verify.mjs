import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import jpeg from '../functions/community/node_modules/jpeg-js/index.js';
import {createCommunity} from '../functions/community/core.mjs';
let pg,api,owner,users;
const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
const call=(u,a,b={})=>api.execute(a,b,u.sessionToken,'shared-campus-network');
const iso=hours=>new Date(Date.now()+hours*3600000).toISOString();
const config=(id=randomUUID())=>({contestId:id,title:'校园里的光',type:'摄影赛',edition:'第一届',description:'分享校园生活',rules:'原创作品；同票并列，下一名次连续排列。',startsAt:iso(-1),submissionEnds:iso(5),votingStarts:iso(5),votingEnds:iso(6),awardAt:iso(7),formats:['text','image','mixed'],maxEntries:1,votesPerUser:3,minEntries:5,minAccountHours:0,excellence:3,autoPublish:true});
const event=async(extra={})=>{const data={...config(),...extra};await call(owner,'contests.save',data);await call(owner,'contests.manage',{contestId:data.contestId,operation:'publish',reason:'发布已核对的测试规则'});return data.contestId;};
const submit=(who,id,extra={})=>call(who,'contests.submit',{contestId:id,entryId:null,requestId:randomUUID(),title:'校园一角',body:'记录一束校园里的光',images:[],agreed:true,...extra}).then(r=>r.entry);
const voting=id=>pg.query("UPDATE hyt_contests SET starts_at=now()-interval '3 hours',submission_ends=now()-interval '2 hours',voting_starts=now()-interval '1 hour',voting_ends=now()+interval '1 hour',award_at=now()+interval '2 hours' WHERE id=$1",[id]);
const ending=id=>pg.query("UPDATE hyt_contests SET starts_at=now()-interval '5 hours',submission_ends=now()-interval '4 hours',voting_starts=now()-interval '3 hours',voting_ends=now()-interval '2 hours',award_at=now()-interval '1 hour' WHERE id=$1",[id]);
const vote=(u,c,e,enabled=true)=>call(u,'contests.vote',{contestId:c,entryId:e.id,enabled});
before(async()=>{pg=new PGlite();await pg.exec(schema);api=createCommunity({contestsEnabled:true,registrationEnabled:true,db:async(a,b,t)=>(await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t])).rows[0].result,storage:{put:async()=>{},url:async k=>'https://fixture.invalid/'+k,remove:async()=>{}}});
 const reg=username=>api.execute('register',{username,password:'synthetic-contest-password',agreed:true},'',username);
 owner=await reg('owner');users=[];for(let i=0;i<9;i++)users.push(await reg('member'+i));
 await pg.query('UPDATE hyt_members SET developer_since=now() WHERE id=$1',[owner.user.id]);await pg.exec("UPDATE hyt_members SET created_at=now()-interval '30 days'");});
beforeEach(async()=>{await pg.exec('TRUNCATE hyt_contests CASCADE; DELETE FROM hyt_community_rate; TRUNCATE hyt_contest_themes CASCADE;');});
after(()=>pg.close());
test('developer authorizes real schedule, supports arbitrary type and preserves old account data on migration',async()=>{
 await assert.rejects(call(users[0],'contests.save',config()),{code:'forbidden'});
 const c=await event({type:'未来可扩展的比赛'});const r=await call(users[0],'contests.get',{contestId:c});assert.equal(r.contest.state,'submitting');assert.equal(r.contest.type,'未来可扩展的比赛');assert(r.serverTime);
 await pg.exec(schema);assert.equal((await call(users[0],'me')).user.id,users[0].user.id);assert.equal((await call(users[0],'contests.list')).contests.length,1);
});
test('submission quotas, retry, foreign posts, edit and withdrawal obey server stage',async()=>{
 const c=await event();const requestId=randomUUID();const e=await submit(users[0],c,{requestId});assert.equal((await submit(users[0],c,{requestId})).id,e.id);
 await assert.rejects(submit(users[0],c),{code:'contest_entry_limit'});
 await assert.rejects(submit(users[1],c,{postId:randomUUID()}),{code:'forbidden'});
 const revised=await submit(users[0],c,{entryId:e.id,title:'修订'});assert.equal(revised.title,'修订');
 await call(users[0],'contests.withdraw',{contestId:c,entryId:e.id});assert.equal((await call(users[1],'contests.entries',{contestId:c,seed:randomUUID()})).entries.length,0);
 await voting(c);await assert.rejects(submit(users[1],c),{code:'contest_closed'});await assert.rejects(call(users[0],'contests.withdraw',{contestId:c,entryId:e.id}),{code:'contest_closed'});
});
test('image submissions project signed images and orphan cleanup preserves attached uploads',async()=>{
 const c=await event();const data=jpeg.encode({width:4,height:4,data:Buffer.alloc(64,180)},80).data.toString('base64');const image=(await call(users[0],'media.upload',{data,requestId:randomUUID()})).image;
 const e=await submit(users[0],c,{images:[image.id],body:''});assert(e.images[0].url);assert.equal(e.body,'');
 await pg.exec("UPDATE hyt_media SET created_at=now()-interval '8 days'");await pg.query("SELECT hyt_community('media.cleanup','{}','')");
 const wall=await call(users[1],'contests.entries',{contestId:c,seed:randomUUID()});assert.equal(wall.entries[0].images[0].id,image.id);
});
test('concurrent retries consume one vote, quota is enforced and own works are rejected',async()=>{
 const c=await event();const entries=[];for(let i=0;i<5;i++)entries.push(await submit(users[i],c));await voting(c);
 await assert.rejects(vote(users[0],c,entries[0]),{code:'contest_self_vote'});
 await Promise.all(Array.from({length:8},()=>vote(users[8],c,entries[0])));assert.equal((await call(users[8],'contests.get',{contestId:c})).votesUsed,1);
 await vote(users[8],c,entries[1]);await vote(users[8],c,entries[2]);await assert.rejects(vote(users[8],c,entries[3]),{code:'contest_vote_limit'});
 await vote(users[8],c,entries[0],false);await vote(users[8],c,entries[3]);
 const wall=await call(users[7],'contests.entries',{contestId:c,seed:randomUUID()});assert(wall.entries.every(e=>e.votes===null));
});
test('fixed registration qualification, deadline equality, pause and cancellation are server enforced',async()=>{
 const c=await event({minAccountHours:72});const e=await submit(users[0],c);await voting(c);
 await pg.query('UPDATE hyt_members SET created_at=now() WHERE id=$1',[users[8].user.id]);await assert.rejects(vote(users[8],c,e),{code:'contest_ineligible'});await pg.query("UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",[users[8].user.id]);
 await call(owner,'contests.manage',{contestId:c,operation:'pause',reason:'暂停核查作品'});await assert.rejects(vote(users[8],c,e),{code:'contest_closed'});
 await call(owner,'contests.manage',{contestId:c,operation:'resume',reason:'核查完成恢复'});await vote(users[8],c,e);
 await ending(c);await assert.rejects(vote(users[8],c,e,false),{code:'contest_closed'});
 await call(owner,'contests.manage',{contestId:c,operation:'cancel',reason:'活动取消保留记录'});assert.equal((await call(users[0],'contests.get',{contestId:c})).contest.state,'cancelled');assert.equal((await call(users[0],'contests.profile')).stats.champions,0);
});
test('risk votes stop automatic publication, review exclusions update tally and all operations are audited',async()=>{
 const c=await event({minEntries:1});const e=await submit(users[0],c);await voting(c);await pg.query("UPDATE hyt_members SET created_at=now()-interval '2 days' WHERE id=$1",[users[8].user.id]);await vote(users[8],c,e);await ending(c);
 await pg.query('SELECT hyt_contest_tick()');assert.equal((await call(users[0],'contests.get',{contestId:c})).contest.state,'reviewing');
 const v=(await call(owner,'contests.admin',{contestId:c})).votes[0];assert.equal(v.risk,'young_account');
 await call(owner,'contests.review',{contestId:c,kind:'vote',targetId:v.id,decision:'exclude',reason:'核验为无效测试票'});
 await call(owner,'contests.manage',{contestId:c,operation:'announce',reason:'复核完成公布结果'});assert.equal((await call(users[0],'contests.profile')).stats.champions,0);assert((await call(owner,'contests.admin',{contestId:c})).audit.some(x=>x.reason==='核验为无效测试票'));
 await pg.query("UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",[users[8].user.id]);
});
test('dense ties, repeat settlement and award revocation synchronize profile and worn honor',async()=>{
 const c=await event({minEntries:2});const e=await submit(users[0],c),other=await submit(users[1],c);await voting(c);await vote(users[7],c,e);await vote(users[8],c,other);await ending(c);
 await pg.query('SELECT hyt_contest_tick()');await pg.query('SELECT hyt_contest_tick()');let profile=await call(users[0],'contests.profile');assert.equal(profile.stats.champions,1);assert.equal(profile.stats.participations,1);
 const badge=profile.awards.find(x=>x.kind==='champion');await call(users[0],'contests.wear',{awardId:badge.id});assert.equal((await call(users[1],'contests.profile',{memberId:users[0].user.id})).worn,badge.id);assert.equal((await call(users[1],'contests.profile')).stats.champions,1);
 await call(owner,'contests.review',{contestId:c,kind:'entry',targetId:e.id,decision:'remove',reason:'确认作品违规撤奖'});profile=await call(users[0],'contests.profile');assert.equal(profile.stats.champions,0);assert.equal(profile.worn,null);assert((await pg.query('SELECT revoked_at FROM hyt_contest_awards WHERE id=$1',[badge.id])).rows[0].revoked_at);
});
test('underfilled events issue participation only and theme proposals need developer approval',async()=>{
 const c=await event();const e=await submit(users[0],c);await voting(c);await vote(users[8],c,e);await ending(c);await pg.query('SELECT hyt_contest_tick()');const profile=await call(users[0],'contests.profile');assert.equal(profile.stats.champions,0);assert.equal(profile.stats.participations,1);
 await call(owner,'contests.manage',{contestId:c,operation:'solicitation',enabled:true,reason:'征集下一期主题'});
 const r=await call(users[0],'contests.suggest',{title:'食堂美食摄影',requestId:randomUUID()});const theme=r.themes[0];assert.equal((await call(users[1],'contests.themes')).themes.length,0);
 await call(owner,'contests.review',{contestId:c,kind:'theme',targetId:theme.id,decision:'approve',reason:'适合校园摄影比赛'});await call(users[1],'contests.themevote',{themeId:theme.id,enabled:true});assert.equal((await call(users[1],'contests.themes')).themes[0].votes,1);
});
test('replayed request conflicts on changed content and edit retries preserve the same revision',async()=>{
 const c=await event(),requestId=randomUUID();const e=await submit(users[0],c,{requestId});await assert.rejects(submit(users[0],c,{requestId,title:'改变重试内容'}),{code:'request_conflict'});
 const editRequest=randomUUID(),first=await submit(users[0],c,{entryId:e.id,requestId:editRequest,title:'正式修订'}),second=await submit(users[0],c,{entryId:e.id,requestId:editRequest,title:'正式修订'});assert.equal(first.version,second.version);
});
test('exact voting deadline rejects withdrawal and a not-yet-started vote cannot be cast',async()=>{
 const c=await event(),e=await submit(users[0],c);await assert.rejects(vote(users[8],c,e),{code:'contest_closed'});await voting(c);await vote(users[8],c,e);
 await pg.query('UPDATE hyt_contests SET voting_ends=clock_timestamp() WHERE id=$1',[c]);await assert.rejects(vote(users[8],c,e,false),{code:'contest_closed'});
});
test('annual ranking is archived once, revisions revoke stale annual honors and achievements retain original dates',async()=>{
 const c=await event({minEntries:1}),e=await submit(users[0],c);await voting(c);await vote(users[8],c,e);await ending(c);await pg.query('SELECT hyt_contest_tick()');
 const profile=await call(users[0],'contests.profile');assert(profile.achievements.some(a=>a.code==='first_champion'));
 const before=(await pg.query('SELECT unlocked_at FROM hyt_contest_achievements WHERE member_id=$1',[users[0].user.id])).rows[0].unlocked_at;
 await pg.query("UPDATE hyt_contest_awards SET awarded_at=now()-interval '1 year' WHERE contest_id=$1",[c]);await pg.query('SELECT hyt_contest_achievements_refresh($1)',[c]);await pg.query('SELECT hyt_contest_tick()');
 assert.equal((await call(users[0],'contests.profile')).annual.length,1);assert.equal((await pg.query('SELECT unlocked_at FROM hyt_contest_achievements WHERE member_id=$1',[users[0].user.id])).rows[0].unlocked_at.getTime(),before.getTime());
 await call(owner,'contests.manage',{contestId:c,operation:'cancel',reason:'确认年度作品违规'});await pg.query('SELECT hyt_contest_tick()');const after=await call(users[0],'contests.profile');assert.deepEqual(after.annual,[]);assert.deepEqual(after.achievements,[]);
});
test('duplicate theme merge deduplicates supporters and preserves a moderation snapshot',async()=>{
 const c=await event();await call(owner,'contests.manage',{contestId:c,operation:'solicitation',enabled:true,reason:'征集主题'});
 const first=(await call(users[0],'contests.suggest',{title:'校园日出摄影',requestId:randomUUID()})).themes[0];const second=(await call(users[1],'contests.suggest',{title:'拍校园的日出',requestId:randomUUID()})).themes[0];
 for(const theme of [first,second]){await call(owner,'contests.review',{contestId:c,kind:'theme',targetId:theme.id,decision:'approve',reason:'主题符合活动要求'});await call(users[8],'contests.themevote',{themeId:theme.id,enabled:true});}
 await call(owner,'contests.review',{contestId:c,kind:'merge',targetId:second.id,mergeId:first.id,decision:'approve',reason:'合并相同摄影主题'});assert.equal((await call(users[8],'contests.themes')).themes[0].votes,1);
 const log=(await pg.query("SELECT snapshot FROM hyt_contest_audit WHERE action='merge:approve'")).rows[0];assert.equal(log.snapshot.title,'拍校园的日出');
});
test('community account deletion removes competition content and retracts confirmed votes',async()=>{
 const temp=await api.execute('register',{username:'temporary_contest_user',password:'synthetic-contest-password',agreed:true},'','temporary');await pg.query("UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",[temp.user.id]);
 const c=await event({minEntries:1}),e=await submit(users[0],c);await submit(temp,c);await voting(c);await vote(temp,c,e);await ending(c);await pg.query('SELECT hyt_contest_tick()');
 await call(temp,'account.delete',{password:'synthetic-contest-password'});assert.equal((await call(users[0],'contests.profile')).stats.champions,0);const wall=await call(users[1],'contests.entries',{contestId:c,seed:randomUUID()});assert.equal(wall.entries.length,1);assert.equal(wall.entries[0].votes,0);
});
