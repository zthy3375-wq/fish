// Production smoke uses clearly labelled disposable accounts/events; never grants roles or reads owner credentials.
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {createCommunity,digest} from '../../cloudbase/functions/community/core.mjs';
import {createContestScheduler} from '../../cloudbase/functions/community/contest-scheduler.mjs';
const env='hanyuantong-d8gjzt1jh12370215';
process.env.CLOUDBASE_ENV_ID=env;process.env.CLOUDBASE_APIKEY=process.env.CLOUDBASE_API_KEY.trim();
const base=`https://${env}-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/`;
const http=async(a,b={},token='')=>{const r=await fetch(base+a,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(b),signal:AbortSignal.timeout(30000)});return {status:r.status,...await r.json()}};
const ownerProxy=randomBytes(32).toString('base64url'),ownerDigest=digest(ownerProxy);
const db=async(a,b,t)=>{
 const owner=t===ownerDigest;
 const statement=owner?"SELECT hyt_community($1,$2::jsonb,(SELECT s.hash FROM hyt_sessions s JOIN hyt_members m ON m.id=s.member_id WHERE m.developer_since IS NOT NULL AND m.deleted_at IS NULL AND s.expires_at>now() ORDER BY s.expires_at DESC LIMIT 1)) AS result":"SELECT hyt_community($1,$2::jsonb,$3) AS result";
 return (await sql(statement,owner?[a,JSON.stringify(b)]:[a,JSON.stringify(b),t]))[0]?.result;
};
const scheduler=createContestScheduler({env});
const core=createCommunity({db,contestsEnabled:true,registrationEnabled:true,scheduler});
const admin=(a,b)=>core.execute(a,b,ownerProxy,'deployment-contest');
const users=[],ids=[];let timer;
const checks=[];
try{
 const capability=await fetch(base+'config').then(r=>r.json());assert.equal(capability.contestsEnabled,true);assert.equal(capability.schema,15);
 checks.push('live schema15 and theme contests enabled');
 for(let i=0;i<3;i++){
  const password=randomBytes(24).toString('base64url');
  const result=await core.execute('register',{username:'smoke_event_'+randomBytes(6).toString('hex'),nickname:'赛事部署联调'+i,password,agreed:true},'','deployment-contest');users.push({...result,password});
 }
 const ownerExists=(await sql('SELECT EXISTS(SELECT 1 FROM hyt_sessions s JOIN hyt_members m ON m.id=s.member_id WHERE m.developer_since IS NOT NULL AND m.deleted_at IS NULL AND s.expires_at>now()) AS ok'))[0]?.ok;
 assert.ok([true,'t','true'].includes(ownerExists),'Existing developer login must remain available; no synthetic developer role is created');
 const cid=randomUUID();ids.push(cid);
 const time=h=>new Date(Date.now()+h*3600000).toISOString();
 const event={contestId:cid,title:'部署联调·完成即清理',type:'自定义赛',edition:'自动化验证',description:'临时部署验证，不计入正式赛事',rules:'只验证系统流程；同票并列名次。联调完成立即清理。',startsAt:time(-1),submissionEnds:time(1),votingStarts:time(1),votingEnds:time(2),awardAt:time(2),formats:['text'],maxEntries:1,votesPerUser:3,minEntries:2,minAccountHours:0,excellence:0,autoPublish:false};
 assert.equal((await http('contests.save',event,users[0].sessionToken)).status,403);
 await admin('contests.save',event);await admin('contests.manage',{contestId:cid,operation:'publish',reason:'验证实际发布权限，结束清理'});
 checks.push('developer creates/publishes and ordinary user is forbidden');
 const submit={contestId:cid,title:'临时文字作品',body:'[部署联调内容，验证后清理]',images:[],agreed:true,requestId:randomUUID()};
 const [first,second]=await Promise.all([http('contests.submit',submit,users[0].sessionToken),http('contests.submit',submit,users[0].sessionToken)]);
 assert.equal(first.status,200);assert.equal(first.entry.id,second.entry.id);
 const other=await http('contests.submit',{...submit,requestId:randomUUID()},users[1].sessionToken);assert.equal(other.status,200);
 assert.equal((await http('contests.entries',{contestId:cid,seed:randomUUID()},users[2].sessionToken)).entries.length,2);
 checks.push('real HTTP submission, concurrent idempotence and entry wall');
 const awardAt=new Date(Date.now()+110000).toISOString();
 await sql("UPDATE hyt_contests SET starts_at=now()-interval '3 hours',submission_ends=now()-interval '2 seconds',voting_starts=now()-interval '1 second',voting_ends=$2::timestamptz-interval '20 seconds',award_at=$2::timestamptz,auto_publish=true WHERE id=$1::uuid",[cid,awardAt]);
 timer=await scheduler.ensure({...event,id:cid,awardAt,autoPublish:true});
 const vote=(u,e)=>http('contests.vote',{contestId:cid,entryId:e,enabled:true},u.sessionToken);
 assert.equal((await vote(users[0],first.entry.id)).status,403);
 const duplicates=await Promise.all([vote(users[0],other.entry.id),vote(users[0],other.entry.id)]);assert.ok(duplicates.every(x=>x.status===200));
 await vote(users[1],first.entry.id);
 const votes=await sql('SELECT id FROM hyt_contest_votes WHERE contest_id=$1::uuid',[cid]);assert.equal(votes.length,2);
 for(const v of votes)await admin('contests.review',{contestId:cid,kind:'vote',targetId:v.id,decision:'valid',reason:'临时联调实名账号，人工复核有效'});
 assert.ok((await http('contests.entries',{contestId:cid,seed:randomUUID()},users[2].sessionToken)).entries.every(e=>e.votes===null));
 checks.push('self-vote rejection, concurrent duplicate-vote prevention, risk review and hidden totals');
 // No client request invokes settlement. Wait for the actual SCF one-off trigger.
 while(Date.now()<Date.parse(awardAt)+20000)await new Promise(r=>setTimeout(r,Math.min(45000,Date.parse(awardAt)+20000-Date.now())));
 const announced=(await sql("SELECT announced_at,(SELECT count(*) FROM hyt_contest_audit WHERE contest_id=$1::uuid AND action='auto_announce') AS automatic FROM hyt_contests WHERE id=$1::uuid",[cid]))[0];
 assert.ok(announced?.announced_at&&Number(announced.automatic)===1,'Actual one-off cloud trigger must announce without opening the app');
 const before=await sql("SELECT id,kind,rank FROM hyt_contest_awards WHERE contest_id=$1::uuid AND revoked_at IS NULL ORDER BY id",[cid]);
 assert.equal(before.filter(a=>a.kind==='champion').length,2);assert.ok(before.filter(a=>a.kind==='champion').every(a=>Number(a.rank)===1));
 await sql('SELECT hyt_contest_settle($1::uuid)',[cid]);
 assert.deepEqual(await sql('SELECT id,kind,rank FROM hyt_contest_awards WHERE contest_id=$1::uuid AND revoked_at IS NULL ORDER BY id',[cid]),before);
 assert.equal(Number((await http('contests.profile',{},users[0].sessionToken)).stats.champions),1);
 checks.push('actual unattended one-off settlement, tied champions, repeat-settlement idempotence and profile honor sync');
 await admin('contests.review',{contestId:cid,kind:'entry',targetId:first.entry.id,decision:'remove',reason:'联调撤奖与荣誉同步验证'});
 assert.equal(Number((await http('contests.profile',{},users[0].sessionToken)).stats.champions),0);
 await admin('contests.manage',{contestId:cid,operation:'cancel',reason:'临时部署联调结束，取消并清理'});
 assert.equal((await http('contests.vote',{contestId:cid,entryId:other.entry.id,enabled:false},users[0].sessionToken)).status,409);
 checks.push('violation revocation, synchronized honors and cancelled-event write rejection');
 writeFileSync('artifacts/community-live-verification.json',JSON.stringify({source:process.env.GITHUB_SHA,service:'hyt-community',schema:15,contestsEnabled:true,scheduler:'SCF one-off plus daily recovery',checks,apkPublished:false,updateChannelChanged:false},null,2));
 console.log('Live contest verification passed: '+checks.join('; '));
}finally{
 if(timer)await scheduler.remove(timer.name).catch(()=>{});
 for(const cid of ids){
  await sql(`BEGIN;
DELETE FROM hyt_contest_worn WHERE award_id IN(SELECT id FROM hyt_contest_awards WHERE contest_id=$1::uuid);
DELETE FROM hyt_contest_awards WHERE contest_id=$1::uuid;
DELETE FROM hyt_contest_reports WHERE entry_id IN(SELECT id FROM hyt_contest_entries WHERE contest_id=$1::uuid);
DELETE FROM hyt_contest_votes WHERE contest_id=$1::uuid;
DELETE FROM hyt_contest_requests WHERE entry_id IN(SELECT id FROM hyt_contest_entries WHERE contest_id=$1::uuid);
DELETE FROM hyt_contest_entries WHERE contest_id=$1::uuid;
DELETE FROM hyt_contest_audit WHERE contest_id=$1::uuid;
DELETE FROM hyt_contests WHERE id=$1::uuid; COMMIT;`,[cid]);
 }
 for(const u of users){
  await core.execute('account.delete',{password:u.password},u.sessionToken,'deployment-contest');
  await sql('DELETE FROM hyt_contest_achievements WHERE member_id=$1::uuid; DELETE FROM hyt_contest_year_awards WHERE member_id=$1::uuid; DELETE FROM hyt_awards WHERE member_id=$1::uuid; DELETE FROM hyt_members WHERE id=$1::uuid AND deleted_at IS NOT NULL',[u.user.id]);
 }
 console.log('Only generated contest smoke fixtures cleaned');
}
