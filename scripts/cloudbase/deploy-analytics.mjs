import {spawnSync} from 'node:child_process';
import {writeFileSync,chmodSync,unlinkSync} from 'node:fs';
import {createHmac} from 'node:crypto';
const envId='hanyuantong-d8gjzt1jh12370215',region='ap-shanghai',key=process.env.CLOUDBASE_API_KEY?.trim();
if(!key)throw Error('Missing CloudBase secret');
const r=await fetch(`https://${envId}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({env:envId})});
const b=await r.json();if(b.code!==0)throw Error('Credential exchange failed');const c=b.data;
const derive=label=>createHmac('sha256',key).update(label).digest('hex');
const salt=derive('hyt-analytics-ip-salt-v1');
const privateValues=[key,c.Token,c.TmpSecretKey,c.TmpSecretId,salt];
const redact=s=>privateValues.reduce((out,k)=>out.replaceAll(k,'[redacted]'),s);
const childEnv={...process.env,CLOUDBASE_API_KEY:'',TENCENTCLOUD_SECRETID:c.TmpSecretId,TENCENTCLOUD_SECRETKEY:c.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:c.Token};
function cli(args){const p=spawnSync('tcb',[...args,'-e',envId,'-r',region],{env:childEnv,encoding:'utf8',timeout:300000,maxBuffer:4*1024*1024});console.log(redact((p.stdout||'')+(p.stderr||'')));if(p.status!==0)throw Error('CloudBase command failed: '+args.slice(0,2).join(' '));return p.stdout}
const names=['hyt-analytics-canary','hyt-analytics'];
const config={envId,functionRoot:'cloudbase/functions',functions:names.map(name=>({name,type:'HTTP',runtime:'Nodejs20.19',timeout:240,memorySize:256,installDependency:false,public:true,gatewayPath:'/'+name,envVariables:{CLOUDBASE_ENV_ID:envId,CLOUDBASE_APIKEY:key,ANALYTICS_SALT:salt,ANALYTICS_BUCKET:'6861-hanyuantong-d8gjzt1jh12370215-1527874185'}}))};
const packages=spawnSync('npm',['ci','--prefix','cloudbase/functions/analytics','--omit=dev','--ignore-scripts'],{stdio:'inherit'});
if(packages.status!==0)throw Error('Cannot install legacy deletion dependency');
writeFileSync('cloudbaserc.json',JSON.stringify(config),{mode:0o600});chmodSync('cloudbase/functions/analytics/scf_bootstrap',0o755);
try{
 for(const name of names){
  cli(['fn','deploy',name,'--httpFn','--dir','cloudbase/functions/analytics','--force','--json']);
  const root='https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/'+name;
  for(const path of ['/health','/api/metrics/enroll','/api/metrics/record','/internal/flush']){
   const r=await fetch(root+path,{method:path==='/health'?'GET':'POST'});
   if(!r.ok||(await r.json()).collection!==false)throw Error('Collection retirement not verified for '+name);
  }
 }
 // Exact legacy schedule; leave all functions, historical data and unrelated triggers intact.
 cli(['fn','trigger','delete','hyt-analytics-hourly','hyt-hourly']);
}finally{unlinkSync('cloudbaserc.json')}
