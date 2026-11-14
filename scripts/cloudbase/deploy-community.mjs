// Deliberate private-test activation only; never publishes an APK or update manifest.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,chmodSync,unlinkSync} from 'node:fs';
import {createHmac,randomBytes,randomUUID} from 'node:crypto';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {createCommunity} from '../../cloudbase/functions/community/core.mjs';
const envId='hanyuantong-d8gjzt1jh12370215',region='ap-shanghai';
const base=`https://${envId}-1527874185.${region}.app.tcloudbase.com/hyt-community`;
const activation=JSON.parse(readFileSync('cloudbase/community-test-deploy.json','utf8'));
if(activation.mode!=='private-treehole-test'||activation.service!=='hyt-community'||activation.registration!=='invite'||!/^[0-9a-f]{64}$/.test(activation.inviteHash))throw Error('Invalid private-test activation');
if(process.env.GITHUB_REF&&process.env.GITHUB_REF!=='refs/heads/feature/treehole-accounts-20261114')throw Error('Unexpected deployment branch');
const key=process.env.CLOUDBASE_API_KEY?.trim();if(!key)throw Error('CloudBase deployment key unavailable');
const response=await fetch(`https://${envId}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({env:envId}),signal:AbortSignal.timeout(25000)});
const envelope=await response.json();if(envelope.code!==0)throw Error('CloudBase credential exchange failed');const credentials=envelope.data;
const rateSalt=createHmac('sha256',key).update('hyt-community-rate-v1').digest('hex');
const privateValues=[key,credentials.Token,credentials.TmpSecretKey,credentials.TmpSecretId,rateSalt].filter(Boolean);
const redact=s=>privateValues.reduce((value,secret)=>value.replaceAll(secret,'[redacted]'),s);
const childEnv={...process.env,CLOUDBASE_API_KEY:'',TENCENTCLOUD_SECRETID:credentials.TmpSecretId,TENCENTCLOUD_SECRETKEY:credentials.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:credentials.Token};
function cli(args){const r=spawnSync('tcb',[...args,'-e',envId,'-r',region],{env:childEnv,encoding:'utf8',timeout:300000,maxBuffer:4*1024*1024});if(r.status!==0){console.error(redact((r.stderr||'')+(r.stdout||'')));throw Error('CloudBase operation failed: '+args.slice(0,2).join(' '));}return r.stdout;}
// Identify the HTTP database role and explicitly deny its implicit table grants.
const identityResponse=await fetch(`https://${envId}.api.tcloudbasegateway.com/v1/rdb/exec-pgsql`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({sql:'SELECT current_user AS role',parameters:[]}),signal:AbortSignal.timeout(20000)});
const identity=await identityResponse.json(),dbRole=identity[0]?.role;
if(!/^[a-zA-Z0-9_-]{1,120}$/.test(dbRole||'')||['anon','authenticated','public'].includes(dbRole))throw Error('Unable to verify database role');
// One transaction, only hyt_ community objects. Existing analytics/academic rows are untouched.
const schema=readFileSync('cloudbase/community-schema.sql','utf8');
cli(['db','execute','--sql','BEGIN;\n'+schema+`\nDO $$ DECLARE obj record; BEGIN
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN
 ('hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_thread_aliases','hyt_reactions','hyt_blocks','hyt_hidden_threads','hyt_reports','hyt_moderation','hyt_community_rate') LOOP
 EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,'${dbRole}'); END LOOP;
 FOR obj IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('hyt_community','hyt_member_json','hyt_author_json','hyt_post_json','hyt_comment_json') LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.signature,'${dbRole}'); END LOOP; END $$;\nCOMMIT;`,'--json']);
console.log('Community schema installed with direct-client access denied');
const config={envId,functionRoot:'cloudbase/functions',functions:[{name:'hyt-community',type:'HTTP',runtime:'Nodejs20.19',timeout:30,memorySize:256,installDependency:false,public:true,gatewayPath:'/hyt-community',envVariables:{CLOUDBASE_ENV_ID:envId,CLOUDBASE_APIKEY:key,COMMUNITY_REGISTRATION:'open',COMMUNITY_INVITE_HASH:activation.inviteHash,COMMUNITY_RATE_SALT:rateSalt}}]};
writeFileSync('cloudbaserc.json',JSON.stringify(config),{mode:0o600});chmodSync('cloudbase/functions/community/scf_bootstrap',0o755);
try{cli(['fn','deploy','hyt-community','--httpFn','--dir','cloudbase/functions/community','--force','--json']);}finally{unlinkSync('cloudbaserc.json');}
const configuration=await fetch(base+'/v1/config',{signal:AbortSignal.timeout(30000)}).then(async r=>({ok:r.ok,value:await r.json()}));
if(!configuration.ok||!configuration.value.registrationEnabled||!configuration.value.requiresInvite)throw Error('Invite gate did not activate');
const http=async(action,body={},token='')=>{const r=await fetch(base+'/v1/'+action,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});return {status:r.status,body:await r.json()};};
if((await http('posts.list')).status!==401)throw Error('Anonymous read access unexpectedly enabled');
if((await http('credentials',{username:'test'})).status!==404)throw Error('Internal endpoint was exposed');
if((await http('register',{username:'invalid_invite_test',nickname:'测试',password:'invalid-invite-password',agreed:true,invite:'wrong'})).status!==403)throw Error('Registration gate failed');
// Create disposable accounts through the exact core with the privileged server adapter.
process.env.CLOUDBASE_ENV_ID=envId;process.env.CLOUDBASE_APIKEY=key;
const db=async(a,b,t)=>(await sql('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t]))[0]?.result;
const local=createCommunity({db,registrationEnabled:true,rateSalt});
const testAccounts=[];const testPosts=[];
try{
 for(let i=0;i<2;i++){
  const password=randomBytes(24).toString('base64url');const r=await local.execute('register',{username:'smoke_'+randomBytes(6).toString('hex'),nickname:'联调测试'+i,password,agreed:true},'','deployment');
  testAccounts.push({...r,password});
 }
 const [author,reader]=testAccounts;
 const created=await http('posts.create',{body:'[自动联调测试，完成即清理]',anonymous:true,requestId:randomUUID()},author.sessionToken);
 if(created.status!==201)throw Error('Live post creation failed');testPosts.push(created.body.post.id);
 const seen=await http('posts.get',{postId:created.body.post.id},reader.sessionToken);
 if(seen.status!==200||seen.body.post.author.mine||JSON.stringify(seen.body).includes(author.user.id)||JSON.stringify(seen.body).includes(author.user.nickname))throw Error('Live anonymity projection failed');
 if((await http('posts.delete',{postId:created.body.post.id},reader.sessionToken)).status!==403)throw Error('Live ownership enforcement failed');
 const commented=await http('comments.create',{postId:created.body.post.id,body:'[联调评论]',anonymous:false,requestId:randomUUID()},author.sessionToken);
 if(commented.status!==201||!commented.body.comment.author.anonymous)throw Error('Live anonymous-author reply failed');
 console.log('Live HTTP/PG checks passed: invite gate, login boundary, posts, cross-account anonymity, deletion ownership, comments');
}finally{
 for(const u of testAccounts){await local.execute('account.delete',{password:u.password},u.sessionToken,'deployment');}
 // Remove only these generated test identities/content, never real user rows.
 for(const pid of testPosts){await sql('DELETE FROM hyt_thread_aliases WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_comments WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_posts WHERE id=$1::uuid',[pid]);}
 for(const u of testAccounts)await sql('DELETE FROM hyt_members WHERE id=$1::uuid AND deleted_at IS NOT NULL',[u.user.id]);
}
console.log(JSON.stringify({service:'hyt-community',mode:'invite-only',apkPublished:false,updateChannelChanged:false}));
