import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,chmodSync,unlinkSync} from 'node:fs';
import {createHmac,randomUUID,randomBytes} from 'node:crypto';
const envId='hanyuantong-d8gjzt1jh12370215',region='ap-shanghai',key=process.env.CLOUDBASE_API_KEY?.trim();
if(!key)throw Error('Missing CloudBase secret');
const r=await fetch(`https://${envId}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({env:envId})});
const b=await r.json();if(b.code!==0)throw Error('Credential exchange failed');const c=b.data;
const derive=label=>createHmac('sha256',key).update(label).digest('hex');
const adminHash=JSON.parse(readFileSync('cloudbase/admin-access.json','utf8')).tokenHash,salt=derive('hyt-analytics-ip-salt-v1');
const privateValues=[key,c.Token,c.TmpSecretKey,c.TmpSecretId,salt];
const redact=s=>privateValues.reduce((out,k)=>out.replaceAll(k,'[redacted]'),s);
const childEnv={...process.env,CLOUDBASE_API_KEY:'',TENCENTCLOUD_SECRETID:c.TmpSecretId,TENCENTCLOUD_SECRETKEY:c.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:c.Token};
function cli(args){const p=spawnSync('tcb',[...args,'-e',envId,'-r',region],{env:childEnv,encoding:'utf8',timeout:300000,maxBuffer:4*1024*1024});console.log(redact((p.stdout||'')+(p.stderr||'')));if(p.status!==0)throw Error('CloudBase command failed: '+args.slice(0,2).join(' '));return p.stdout}
const identityResponse=await fetch(`https://${envId}.api.tcloudbasegateway.com/v1/rdb/exec-pgsql`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({sql:'SELECT current_user AS role',parameters:[]})});
const identity=await identityResponse.json(),dbRole=identity[0]?.role;
if(!/^[a-zA-Z0-9_-]{1,120}$/.test(dbRole||'')||['anon','authenticated','public'].includes(dbRole))throw Error('Invalid backend database role');
console.log('Verified backend database role:',dbRole);
// Schema is kept in source control. Existing user rows are never reset.
for(const statement of readFileSync('cloudbase/schema.sql','utf8').split('-- statement').map(s=>s.trim()).filter(Boolean))cli(['db','execute','--sql',statement,'--json']);
// The REST SQL channel maps to a read-only role in this environment. Keep it read-only.
for(const table of ['hyt_devices','hyt_daily','hyt_rate'])cli(['db','execute','--sql',`DROP POLICY IF EXISTS hyt_backend ON public.${table}`,'--json']);
cli(['db','execute','--sql',`REVOKE ALL ON public.hyt_devices,public.hyt_daily,public.hyt_rate FROM "${dbRole}"`,'--json']);
cli(['db','execute','--sql',`REVOKE ALL ON FUNCTION public.hyt_metric(text,uuid,text,jsonb,text) FROM "${dbRole}"`,'--json']);
console.log('Analytics schema installed');
const config={envId,functionRoot:'cloudbase/functions',functions:[{name:'hyt-analytics',type:'HTTP',runtime:'Nodejs20.19',timeout:20,memorySize:128,installDependency:false,public:true,gatewayPath:'/hyt-analytics',envVariables:{CLOUDBASE_ENV_ID:envId,CLOUDBASE_APIKEY:key,ANALYTICS_ADMIN_TOKEN_HASH:adminHash,ANALYTICS_SALT:salt}}]};
writeFileSync('cloudbaserc.json',JSON.stringify(config),{mode:0o600});chmodSync('cloudbase/functions/analytics/scf_bootstrap',0o755);
try{cli(['fn','deploy','hyt-analytics','--httpFn','--dir','cloudbase/functions/analytics','--force','--json']);cli(['fn','detail','hyt-analytics','--json']);cli(['service','list']);}finally{unlinkSync('cloudbaserc.json')}

const probe=await fetch(`https://${envId}.api.tcloudbasegateway.com/v1/rdb/exec-pgsql`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({sql:'SELECT current_user AS role, $1::int AS value',parameters:[1]})});
console.log('SQL HTTP probe',probe.status,redact(await probe.text()));

const service='https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-analytics';
const health=await fetch(service+'/health');if(!(await health.json()).ok)throw Error('Health check failed');
const denied=await fetch(service+'/stats');if(denied.status!==403)throw Error('Statistics authorization check failed');
console.log('Health and protected statistics checks passed');

const uid=randomUUID(),testToken=randomBytes(32).toString('hex');
const call=async(action,payload)=>{const r=await fetch(service+'/api/metrics/'+action,{method:'POST',headers:{Authorization:'Bearer '+testToken,'Content-Type':'application/json'},body:JSON.stringify({id:uid,...payload})});const b=await r.json();console.log('Smoke check',action,r.status,b);return r.status;};
try{if(await call('enroll',{})!==200){throw Error('Enrollment smoke check failed')}}finally{await call('delete',{})}
