import {spawnSync} from 'node:child_process';
const key=process.env.CLOUDBASE_API_KEY,envId=process.env.CLOUDBASE_ENV_ID;
if(!key?.trim()){console.error('CLOUDBASE_API_KEY secret is missing or empty');process.exit(1)}
if(envId!=='hanyuantong-d8gjzt1jh12370215')throw Error('Unexpected target environment');
console.log('Secret configured; checking target environment with read-only requests.');
// Never stream CLI output: login/SDK errors can contain credential material.
for(const region of ['ap-shanghai','ap-guangzhou']){
 let credential;
 try {
  const response=await fetch(`https://${envId}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${key.trim()}`},body:JSON.stringify({env:envId}),signal:AbortSignal.timeout(25000)});
  const body=await response.json();
  const code=String(body.code??body.error?.code??'unknown');
  console.log(JSON.stringify({region,httpStatus:response.status,exchangeCode:/^[A-Za-z0-9_.-]{1,80}$/.test(code)?code:'unrecognized'}));
  if(body.code!==0||!body.data?.TmpSecretId||!body.data?.TmpSecretKey||!body.data?.Token)continue;
  credential=body.data;
 }catch(e){console.log(JSON.stringify({region,transportError:e.name}));continue}
 const childEnv={...process.env,CLOUDBASE_API_KEY:'',TENCENTCLOUD_SECRETID:credential.TmpSecretId,TENCENTCLOUD_SECRETKEY:credential.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:credential.Token};
 const r=spawnSync('tcb',['env','list','--json','-e',envId,'-r',region],{env:childEnv,encoding:'utf8',timeout:90000,maxBuffer:2*1024*1024});
 const out=(r.stdout||'')+'\n'+(r.stderr||'');
 if(r.status===0&&out.includes(envId)){
  console.log(JSON.stringify({verified:true,envId,region}));process.exit(0);
 }
 const codes=[...new Set(out.match(/(?:AuthFailure|UnauthorizedOperation|ResourceNotFound|InvalidParameter|FailedOperation|UnsupportedOperation)(?:\.[A-Za-z]+)?/g)||[])];
 const known=['Invalid API Key','API Key 验证失败','密钥验证失败','没有权限','permission denied','invalid signature','token expired','登录失败','未登录','invalid api key'];
 console.log(JSON.stringify({region,exitCode:r.status,timedOut:r.error?.code==='ETIMEDOUT',codes,diagnostics:known.filter(s=>out.toLowerCase().includes(s.toLowerCase()))}));
}
console.error('Environment access not verified. No resources were created or modified.');process.exit(1);
