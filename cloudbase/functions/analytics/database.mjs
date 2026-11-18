import {createHash,createHmac} from 'node:crypto';
const sha=s=>createHash('sha256').update(s).digest('hex'),hmac=(key,value)=>createHmac('sha256',key).update(value).digest();
let credential,validUntil=0;
export function bindSQL(query,parameters){return query.replace(/\$(\d+)/g,(_,n)=>{const value=parameters[Number(n)-1];if(value===undefined)throw Error('missing_sql_parameter');if(value===null)return 'NULL';return `convert_from(decode('${Buffer.from(String(value)).toString('base64')}','base64'),'UTF8')`})}
export function decodeRows(result){return (result.Rows||[]).map(row=>{const values=typeof row==='string'?JSON.parse(row):row;return Object.fromEntries(result.Columns.map((name,i)=>{const value=values[i];return [name,value!==null&&(result.ColumnTypes?.[i]==='jsonb'||result.ColumnTypes?.[i]==='json'||['totals','result'].includes(name))?JSON.parse(value):value]}))})}
export async function credentials(){
 const env=process.env.CLOUDBASE_ENV_ID,region='ap-shanghai';
 if(!credential||Date.now()>validUntil){
  const r=await fetch(`https://${env}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${process.env.CLOUDBASE_APIKEY}`,'Content-Type':'application/json'},body:JSON.stringify({env}),signal:AbortSignal.timeout(8000)});
  const b=await r.json();if(b.code!==0||!b.data?.TmpSecretKey)throw Error('credential_exchange_failed');credential=b.data;validUntil=Date.now()+240000;
 }
 return credential;
}
export async function cloudApi(action,payload){
 const credential=await credentials(),region="ap-shanghai";
 const host='tcb.tencentcloudapi.com',timestamp=Math.floor(Date.now()/1000),date=new Date(timestamp*1000).toISOString().slice(0,10),scope=date+'/tcb/tc3_request';
 const body=JSON.stringify(payload);
 const canonical=['POST','/','','content-type:application/json\nhost:'+host+'\n','content-type;host',sha(body)].join('\n');
 const toSign=['TC3-HMAC-SHA256',timestamp,scope,sha(canonical)].join('\n');
 const signing=hmac(hmac(hmac('TC3'+credential.TmpSecretKey,date),'tcb'),'tc3_request');
 const signature=createHmac('sha256',signing).update(toSign).digest('hex');
 const r=await fetch('https://'+host,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`TC3-HMAC-SHA256 Credential=${credential.TmpSecretId}/${scope}, SignedHeaders=content-type;host, Signature=${signature}`,'X-TC-Action':action,'X-TC-Version':'2018-06-08','X-TC-Region':region,'X-TC-Timestamp':String(timestamp),'X-TC-Token':credential.Token},body,signal:AbortSignal.timeout(12000)});
 const b=(await r.json()).Response;if(!r.ok||!b||b.Error)throw Error('sql_'+String(b?.Error?.Code||r.status));return b;
}

export async function sql(query,parameters=[]){return decodeRows(await cloudApi("ExecutePGSql",{EnvId:process.env.CLOUDBASE_ENV_ID,Sql:bindSQL(query,parameters)}))}
