import {spawnSync} from 'node:child_process';
import {writeFileSync,chmodSync,unlinkSync,readFileSync,existsSync} from 'node:fs';
import {catalog,BASE} from '../../cloudbase/functions/updates/core.mjs';
const envId='hanyuantong-d8gjzt1jh12370215',region='ap-shanghai';
const key=process.env.CLOUDBASE_API_KEY?.trim(),pgyer=process.env.PGYER_API_KEY?.trim();
if(!key)throw Error('Missing CLOUDBASE_API_KEY');
const releases=catalog(JSON.parse(readFileSync('cloudbase/functions/updates/releases.json','utf8')));
// A concurrent source-only deployment must not clear a candidate being published.
if(existsSync('releases/android-candidate.json')){
 const candidate=JSON.parse(readFileSync('releases/android-candidate.json','utf8'));
 if(!releases.releases.some(r=>r.versionCode===candidate.versionCode)){
  console.log('Candidate publication owns deployment until its verified catalog is committed');
  process.exit(0);
 }
}
if(releases.current&&!pgyer)throw Error('Cannot publish a release without PGYER_API_KEY');
const response=await fetch(`https://${envId}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({env:envId}),signal:AbortSignal.timeout(25000)});
const envelope=await response.json();if(envelope.code!==0)throw Error('CloudBase credential exchange failed');
const c=envelope.data,privateValues=[key,pgyer,c.Token,c.TmpSecretKey,c.TmpSecretId].filter(Boolean);
const redact=s=>privateValues.reduce((value,secret)=>value.replaceAll(secret,'[redacted]'),s);
const childEnv={...process.env,CLOUDBASE_API_KEY:'',PGYER_API_KEY:'',TENCENTCLOUD_SECRETID:c.TmpSecretId,TENCENTCLOUD_SECRETKEY:c.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:c.Token};
const config={envId,functionRoot:'cloudbase/functions',functions:[{name:'hyt-updates',type:'HTTP',runtime:'Nodejs20.19',timeout:25,memorySize:128,installDependency:false,public:true,gatewayPath:'/hyt-updates',envVariables:{...(pgyer?{PGYER_API_KEY:pgyer}:{})}}]};
writeFileSync('cloudbaserc.json',JSON.stringify(config),{mode:0o600});chmodSync('cloudbase/functions/updates/scf_bootstrap',0o755);
try{
 const run=spawnSync('tcb',['fn','deploy','hyt-updates','--httpFn','--dir','cloudbase/functions/updates','--force','--json','-e',envId,'-r',region],{env:childEnv,encoding:'utf8',timeout:300000,maxBuffer:4*1024*1024});
 console.log(redact((run.stdout||'')+(run.stderr||'')));if(run.status!==0)throw Error('Update service deployment failed');
}finally{unlinkSync('cloudbaserc.json')}
const health=await fetch(BASE+'/health',{signal:AbortSignal.timeout(30000)});const status=await health.json();if(!health.ok||!status.ok)throw Error('Update service health check failed');
console.log(JSON.stringify({service:'hyt-updates',providerConfigured:status.providerConfigured,releaseConfigured:status.releaseConfigured}));
const channel=await fetch(BASE+'/android/stable.json',{signal:AbortSignal.timeout(30000)});
if(channel.status!==(releases.current?200:503))throw Error('Unexpected channel readiness');
if(releases.current){const manifest=await channel.json();if(manifest.versionCode!==releases.current.versionCode||manifest.sha256!==releases.current.sha256)throw Error('Published manifest mismatch')}
console.log(releases.current?'Version channel verified':'Service deployed; release publication waits for verified Pgyer APK');
