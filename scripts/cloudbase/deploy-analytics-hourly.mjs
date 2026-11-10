import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,unlinkSync,chmodSync,mkdirSync,mkdtempSync} from 'node:fs';
import {createHmac,randomUUID,randomBytes} from 'node:crypto';
import {credentials,cloudApi,sql} from '../../cloudbase/functions/analytics/database.mjs';
import {createStore} from '../../cloudbase/functions/analytics/storage.mjs';
import {Outbox,PREFIX,SNAPSHOT} from '../../cloudbase/functions/analytics/outbox.mjs';
import {hash,day} from '../../cloudbase/functions/analytics/core.mjs';
const envId='hanyuantong-d8gjzt1jh12370215',region='ap-shanghai',key=process.env.CLOUDBASE_API_KEY?.trim();
if(!key)throw Error('Missing backend deployment credential');
process.env.CLOUDBASE_ENV_ID=envId;process.env.CLOUDBASE_APIKEY=key;
const c=await credentials();
// Target bucket and region supplied by the owner from the environment console.
const bucket='6861-hanyuantong-d8gjzt1jh12370215-1527874185';
process.env.ANALYTICS_BUCKET=bucket;
const batchToken=createHmac('sha256',key).update('hyt-analytics-hourly-batch-v2').digest('hex');
const salt=createHmac('sha256',key).update('hyt-analytics-ip-salt-v1').digest('hex');
const sensitive=[key,c.Token,c.TmpSecretKey,c.TmpSecretId,batchToken,salt];
const redact=s=>sensitive.reduce((v,k)=>v.replaceAll(k,'[redacted]'),s);
process.on('uncaughtException',error=>{console.error('Deployment stopped:',redact(String(error.code||error.message).slice(0,300)));process.exit(1)});
process.on('unhandledRejection',error=>{console.error('Deployment stopped:',redact(String(error?.code||error?.message||'request_failed').slice(0,300)));process.exit(1)});
const cliEnv={...process.env,CLOUDBASE_API_KEY:'',TENCENTCLOUD_SECRETID:c.TmpSecretId,TENCENTCLOUD_SECRETKEY:c.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:c.Token};
function cli(args){const r=spawnSync('tcb',[...args,'-e',envId,'-r',region],{env:cliEnv,encoding:'utf8',timeout:600000,maxBuffer:4*1024*1024});console.log(redact((r.stdout||'')+(r.stderr||'')));if(r.status!==0)throw Error('CloudBase command failed: '+args.slice(0,2).join(' '))}
const store=await createStore(),outbox=new Outbox(store,sql);
// Check private, durable object storage before changing the running service.
const probeKey=PREFIX+'probe/'+randomUUID()+'.json';await store.put(probeKey,{probe:true},true);if(!(await store.get(probeKey))?.probe)throw Error('Object roundtrip failed');
const publicRead=await fetch('https://'+bucket+'.cos.'+region+'.myqcloud.com/'+probeKey,{signal:AbortSignal.timeout(15000)});if(publicRead.status!==403)throw Error('Object is not private');await store.remove(probeKey);
const devices=await sql('SELECT id,token_hash FROM public.hyt_devices LIMIT 10001');if(devices.length>10000)throw Error('Registry migration exceeds audited size');
for(let i=0;i<devices.length;i+=16)await Promise.all(devices.slice(i,i+16).map(d=>store.put(PREFIX+'auth/'+hash(d.id+'|'+d.token_hash)+'.json',{id:d.id,tokenHash:d.token_hash})));
await outbox.snapshot();console.log('Private registry and snapshot initialized; devices:',devices.length);
const adminHash=JSON.parse(readFileSync('cloudbase/admin-access.json','utf8')).tokenHash;
const origin='https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com';
const common={CLOUDBASE_ENV_ID:envId,CLOUDBASE_APIKEY:key,ANALYTICS_ADMIN_TOKEN_HASH:adminHash,ANALYTICS_SALT:salt,ANALYTICS_BUCKET:bucket,ANALYTICS_BATCH_TOKEN_HASH:hash(batchToken)};
const config={envId,functionRoot:'cloudbase/functions',functions:[{name:'hyt-analytics-canary',type:'HTTP',runtime:'Nodejs20.19',timeout:240,memorySize:256,installDependency:false,public:true,gatewayPath:'/hyt-analytics-canary',envVariables:common},{name:'hyt-analytics',type:'HTTP',runtime:'Nodejs20.19',timeout:240,memorySize:256,installDependency:false,public:true,gatewayPath:'/hyt-analytics',envVariables:common},{name:'hyt-analytics-hourly',type:'Event',runtime:'Nodejs20.19',handler:'index.main',timeout:280,memorySize:128,installDependency:false,triggers:[{name:'hyt-hourly',type:'timer',config:'0 0 * * * * *'}],envVariables:{ANALYTICS_FLUSH_URL:origin+'/hyt-analytics/internal/flush',ANALYTICS_BATCH_TOKEN:batchToken}}]};
writeFileSync('cloudbaserc.json',JSON.stringify(config),{mode:0o600});chmodSync('cloudbase/functions/analytics/scf_bootstrap',0o755);
async function call(base,path,body,token){const r=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{'X-Hyt-Token':token}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(250000)});const text=await r.text();let data;try{data=JSON.parse(text)}catch{throw Error('Non-JSON service response: '+r.status)}return {status:r.status,data}}
async function smoke(base){
 const ready=await call(base,'/health');if(ready.status!==200)throw Error('Canary readiness: '+ready.status+' '+(ready.data.cause||ready.data.error));
 const id=randomUUID(),token=randomBytes(32).toString('hex');
 try{
  const enrollment=await call(base,'/api/metrics/enroll',{id},token);if(enrollment.status!==200)throw Error('Enrollment failed: '+enrollment.status+' '+enrollment.data.error);
  const recorded=await call(base,'/api/metrics/record',{id,day:day(),version:'1.2.1-test.5',versionCode:138,features:{parcel:2}},token);
  if(recorded.status!==200||!recorded.data.queued)throw Error('Durable queue acceptance failed');
  const flush=await fetch(base+'/internal/flush',{method:'POST',headers:{'X-Hyt-Batch-Token':batchToken},signal:AbortSignal.timeout(250000)});if(!flush.ok)throw Error('Aggregation failed: '+flush.status);
  const rows=await sql('SELECT features FROM public.hyt_daily WHERE device=$1::uuid',[id]);if(rows[0]?.features?.parcel!==2)throw Error('Aggregated counter mismatch');
  if((await call(base,'/stats')).status!==403)throw Error('Statistics exposed');
 }finally{const r=await call(base,'/api/metrics/delete',{id},token);if(r.status!==200){const cleanup=await outbox.delete({id},hash(token),'smoke-cleanup');if(cleanup.status!==200)throw Error('Smoke record cleanup failed')}}
}
const codeOnlyResume=true;
if(codeOnlyResume){const diff=spawnSync('git',['diff','093c45fe43d2814aa02dd094c08d3e144c41334f','--','cloudbase/functions/analytics','cloudbase/functions/analytics-timer'],{encoding:'utf8'});if(diff.status!==0||diff.stdout.trim())throw Error('Canary-verified code changed; full verification required')}
let productionTouched=false;
try{
 if(!codeOnlyResume)cli(['fn','deploy','hyt-analytics-canary','--httpFn','--dir','cloudbase/functions/analytics','--force','--json']);
 await smoke(origin+'/hyt-analytics-canary');
 // Timer is deployed first; the old service rejects its private route until cutover.
 if(!codeOnlyResume){cli(['fn','deploy','hyt-analytics-hourly','--dir','cloudbase/functions/analytics-timer','--force','--json']);cli(['fn','trigger','create','hyt-analytics-hourly']);}
 productionTouched=true;
 cli(['fn','code','update','hyt-analytics','--dir','cloudbase/functions/analytics','--yes','--json']);await smoke(origin+'/hyt-analytics');
 console.log('Hourly trigger configured; privileged manual invocation is not required for cutover');
 console.log('Hourly analytics deployed and verified; APK update channel untouched');
}catch(error){
 if(productionTouched){
  const dir=mkdtempSync('/tmp/hyt-analytics-rollback-');
  for(const name of ['server.mjs','core.mjs','database.mjs','dashboard.html','package.json','scf_bootstrap']){
   const r=spawnSync('git',['show','b46ac3ebd6b69677d5c5fcfc0ab10872f2f04751:cloudbase/functions/analytics/'+name],{encoding:'utf8'});
   if(r.status!==0)throw Error('Rollback source unavailable');writeFileSync(dir+'/'+name,r.stdout);
  }
  chmodSync(dir+'/scf_bootstrap',0o755);
  cli(['fn','deploy','hyt-analytics','--httpFn','--dir',dir,'--force','--json']);
  console.log('Previous statistics service restored; durable queue retained');
 }
 throw error;
}finally{unlinkSync('cloudbaserc.json')}

