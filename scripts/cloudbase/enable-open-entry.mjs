import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {randomBytes,randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {digest,hashPassword} from '../../cloudbase/functions/community/core.mjs';
import {entryQueryUpgrade} from './entry-query-upgrade.mjs';

const env='hanyuantong-d8gjzt1jh12370215';
assert.equal(process.env.CLOUDBASE_ENV_ID,env);
const origin='https://'+env+'-1527874185.ap-shanghai.app.tcloudbase.com';
process.env.CLOUDBASE_APIKEY=process.env.CLOUDBASE_API_KEY;
async function api(action,body={},token='') {
  const headers={'Content-Type':'application/json'};
  if(token)headers.Authorization='Bearer '+token;
  const res=await fetch(origin+'/hyt-community/v1/'+action,{headers,method:action==='config'?'GET':'POST',
    ...(action==='config'?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(20000)});
  const data=await res.json();
  if(!res.ok)throw Error(action+' '+res.status+' '+String(data.error||''));
  return data;
}
const original=execFileSync('git',['show','a897e2a956b2e5bc71a08f86260f74f2d6ead203:cloudbase/community-schema.sql'],{encoding:'utf8'});
const modified=await readFile('cloudbase/community-schema.sql','utf8');
const suffix=randomBytes(8).toString('hex');
const password=randomBytes(24).toString('base64url');
const existing='qa_'+suffix;
const newName='7邯院🐟'+suffix;
const fixtures=[];
async function cleanup() {
  for(const {id,username} of fixtures) {
    // No post, social edge or private message is created. Match both independent identifiers.
    const result=await sql(`WITH owned AS (SELECT id FROM public.hyt_members WHERE id=$1::uuid AND username=$2 AND role='member'),
      sessions AS (DELETE FROM public.hyt_sessions WHERE member_id IN (SELECT id FROM owned))
      DELETE FROM public.hyt_members WHERE id IN (SELECT id FROM owned) RETURNING id`,[id,username]);
    assert.equal(result.length,1,'Synthetic account cleanup');
  }
  console.log('Removed',fixtures.length,'disposable validation accounts with their sessions');
}
try {
  const config=await api('config');
  assert.equal(config.schema,10);
  const db=(action,b,t)=>sql('SELECT public.hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(b),t]).then(rows=>rows[0].result);
  const seed=await db('register',{username:existing,nickname:'验证账号',passwordHash:await hashPassword(password),recoveryHash:digest(randomUUID())},digest(randomUUID()));
  assert.equal(seed.status,201); fixtures.push({id:seed.user.id,username:existing});
  const oldLogin=await api('login',{username:existing,password});
  assert.equal(oldLogin.user.id,seed.user.id);
  const oldSession=oldLogin.sessionToken;
  await sql(entryQueryUpgrade(original,modified));
  console.log('Updated and verified the community feed query in-place; no table migration.');
  if(!config.simpleRegistration || config.requiresInvite || !config.combinedUnread) {
    execFileSync('python3',['scripts/cloudbase/update-community-code.py'],{stdio:'inherit'});
  }
  let ready=false;
  for(let i=0;i<25;i++){
    const c=await api('config').catch(()=>({}));
    if(c.schema===10&&c.registrationEnabled&&c.simpleRegistration&&c.requiresInvite===false&&c.combinedUnread){ready=true;break;}
    await delay(2500);
  }
  assert(ready,'Live open signup and entry capability');
  const result=await api('register',{username:newName,password,agreed:true});
  fixtures.push({id:result.user.id,username:newName});
  assert.equal(result.user.username,newName);
  assert.notEqual(result.user.nickname,newName);
  const freshLogin=await api('login',{username:newName,password});
  assert.equal(freshLogin.user.id,result.user.id);
  assert.equal((await api('login',{username:existing,password})).user.id,seed.user.id);
  const sessionEntry=await api('me',{entry:true},oldSession);
  assert.equal(sessionEntry.user.id,seed.user.id);
  assert(Array.isArray(sessionEntry.posts));
  const unread=await api('notifications.unread',{withMessages:true},freshLogin.sessionToken);
  assert.equal(typeof unread.unreadCount,'number');assert.equal(typeof unread.messageUnreadCount,'number');
  console.log('Live signup (digit + Chinese + emoji, no invite/nickname), new login, legacy login, existing session, combined unread: passed');
  const legacy=[],fast=[];
  for(let i=0;i<5;i++){
    const before=async()=>{const start=performance.now();await api('config');await api('me',{},oldSession);await api('posts.list',{},oldSession);legacy.push(Math.round(performance.now()-start));};
    const after=async()=>{const start=performance.now();const data=await api('me',{entry:true,boardTopics:true},oldSession);assert(data.config.simpleRegistration&&data.user.id===seed.user.id&&Array.isArray(data.posts));fast.push(Math.round(performance.now()-start));};
    if(i%2){await after();await before();}else{await before();await after();}
  }
  const median=xs=>[...xs].sort((a,b)=>a-b)[2];
  console.log('ENTRY_RESULT',JSON.stringify({pairs:5,oldRequests:3,newRequests:1,oldMedianMs:median(legacy),newMedianMs:median(fast)}));
  const stats=await fetch(origin+'/hyt-analytics/health').then(r=>r.json());
  assert.equal(stats.collection,false);
  console.log('Verified analytics collection=false');
} finally {await cleanup();}
