import {createHash,createHmac} from 'node:crypto';
const sha=v=>createHash('sha256').update(v).digest('hex');
const mac=(key,v)=>createHmac('sha256',key).update(v).digest();
// Server-only SCF control plane. Credentials and provider responses are never logged.
export function createScf({env=process.env.CLOUDBASE_ENV_ID,key=process.env.CLOUDBASE_APIKEY,fetcher=fetch,now=Date.now}={}){
 let credentials,until=0,pending;
 return async(action,input={})=>{
  if(!env||!key)throw Error('scf_configuration');
  if(!credentials||now()>=until){
   if(!pending)pending=(async()=>{
    const response=await fetcher(`https://${env}.ap-shanghai.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({env}),signal:AbortSignal.timeout(10000)});
    const result=await response.json();if(result.code!==0||!result.data?.TmpSecretKey)throw Error('scf_credential_exchange');
    credentials=result.data;until=now()+240000;
   })().finally(()=>{pending=null});
   await pending;
  }
  const host='scf.tencentcloudapi.com',timestamp=Math.floor(now()/1000),date=new Date(timestamp*1000).toISOString().slice(0,10),scope=date+'/scf/tc3_request';
  const body=JSON.stringify({Stamp:'MINI_QCBASE',...input}),canonical=['POST','/','','content-type:application/json\nhost:'+host+'\n','content-type;host',sha(body)].join('\n');
  const signature=createHmac('sha256',mac(mac(mac('TC3'+credentials.TmpSecretKey,date),'scf'),'tc3_request')).update(['TC3-HMAC-SHA256',timestamp,scope,sha(canonical)].join('\n')).digest('hex');
  const response=await fetcher('https://'+host,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`TC3-HMAC-SHA256 Credential=${credentials.TmpSecretId}/${scope}, SignedHeaders=content-type;host, Signature=${signature}`,'X-TC-Action':action,'X-TC-Version':'2018-04-16','X-TC-Region':'ap-shanghai','X-TC-Timestamp':String(timestamp),'X-TC-Token':credentials.Token},body,signal:AbortSignal.timeout(20000)});
  const result=(await response.json()).Response;
  if(!response.ok||!result||result.Error)throw Object.assign(Error('scf_request_failed'),{code:result?.Error?.Code||String(response.status)});
  return result;
 };
}
