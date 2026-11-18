import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {timeAwardMigration} from './time-award-migration.mjs';
const env='hanyuantong-d8gjzt1jh12370215';
assert.equal(process.env.CLOUDBASE_ENV_ID,env);
assert.equal(process.env.GITHUB_REF,'refs/heads/ops/activate-time-awards-20261118');
process.env.CLOUDBASE_APIKEY=process.env.CLOUDBASE_API_KEY;
const previous=await readFile(process.argv[2],'utf8'),next=await readFile('cloudbase/community-schema.sql','utf8');
const url='https://'+env+'-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/';
async function request(action,body,token){
 const response=await fetch(url+action,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(25000)});
 return {status:response.status,body:await response.json()};
}
const config=(await request('config')).body;assert.equal(config.schema,12);assert.equal(config.simpleRegistration,true);
const username='honor_qa_'+randomBytes(8).toString('hex'),password=randomBytes(24).toString('base64url');
let uid;
try{
 const fixture=await request('register',{username,password,agreed:true});assert.equal(fixture.status,201,fixture.body.error||'create smoke fixture');
 uid=fixture.body.user.id;assert.match(uid,/^[a-f0-9-]{36}$/);const oldSession=fixture.body.sessionToken;assert.equal(fixture.body.user.role,'member');
 await sql(timeAwardMigration(previous,next));console.log('Time award functions updated transactionally; existing tables and grants preserved');
 execFileSync('python3',['scripts/cloudbase/update-community-code.py'],{stdio:'inherit'});
 let ready=false;for(let i=0;i<35;i++){
  const c=(await request('config').catch(()=>({body:{}}))).body;
  if(c.timeAwards&&c.honorsEnabled&&c.schema===12&&c.simpleRegistration){ready=true;break;}await delay(2500);
 }
 assert(ready,'community code activation');
 const entry=await request('me',{entry:true},oldSession);assert.equal(entry.status,200);assert.equal(entry.body.user.id,uid);assert(Array.isArray(entry.body.posts));
 const login=await request('login',{username,password});assert.equal(login.body.user.id,uid);
 const token=login.body.sessionToken;const cabinet=await request('honors.hall',{},token);assert.equal(cabinet.status,200);assert(cabinet.body.hall.awards.arrival);
 assert.equal(cabinet.body.hall.total,1);assert.equal(cabinet.body.hall.progress.days,0);assert.equal((await request('honors.wear',{honor:null,showcase:['month']},token)).status,400);assert.equal(cabinet.body.hall.badges.official,null);
 const wear=await request('honors.wear',{honor:null,showcase:['arrival']},token);assert.deepEqual(wear.body.hall.showcase,['arrival']);
 assert.equal((await request('honors.manage',{},token)).status,403);
 assert.equal((await request('honors.wear',{honor:'seed',showcase:['popular']},token)).status,400);
 console.log('PASS public HTTPS: original session, password login, combined feed, real award, showcase, member denial and locked selection denial');
}finally{
 if(uid){
  // Exactly this run's private fixture; foreign keys prevent deleting any member with unrelated content.
  await sql(`DO $clean$ DECLARE who uuid; BEGIN SELECT id INTO STRICT who FROM hyt_members WHERE id='${uid}'::uuid AND username='${username}' AND role='member' FOR UPDATE;
  IF to_regclass('public.hyt_awards') IS NOT NULL THEN EXECUTE 'DELETE FROM public.hyt_awards WHERE member_id='||quote_literal(who); END IF; DELETE FROM hyt_sessions WHERE member_id=who;
  DELETE FROM hyt_community_rate WHERE key='member:'||who; DELETE FROM hyt_members WHERE id=who; END $clean$;`);
  console.log('Disposable verification member removed. No user role was granted.');
 }
}
