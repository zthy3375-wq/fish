import {createHash,createHmac} from 'node:crypto';
const sha=s=>createHash('sha256').update(s).digest('hex'),hmac=(key,value)=>createHmac('sha256',key).update(value).digest();
export function bindSQL(query,parameters){return query.replace(/\$(\d+)/g,(_,n)=>{const value=parameters[Number(n)-1];if(value===undefined)throw Error('missing_sql_parameter');if(value===null)return 'NULL';return `convert_from(decode('${Buffer.from(String(value)).toString('base64')}','base64'),'UTF8')`})}
export function decodeRows(result){return (result.Rows||[]).map(row=>{const values=typeof row==='string'?JSON.parse(row):row;return Object.fromEntries(result.Columns.map((name,i)=>{const value=values[i];return [name,value!==null&&(result.ColumnTypes?.[i]==='jsonb'||result.ColumnTypes?.[i]==='json'||['totals','result'].includes(name))?JSON.parse(value):value]}))})}
export function createSqlClient({fetcher=fetch,now=Date.now,settings=()=>({env:process.env.CLOUDBASE_ENV_ID,key:process.env.CLOUDBASE_APIKEY})}={}){
 let cache;
 return async function sql(query,parameters=[]){
 const {env,key}=settings(),region='ap-shanghai',identity=env+':'+sha(String(key));
 if(cache?.identity!==identity)cache={identity,credential:null,validUntil:0,pending:null};
 const current=cache;
 if(!current.credential||now()>=current.validUntil){
  if(!current.pending)current.pending=(async()=>{
   const r=await fetcher(`https://${env}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({env}),signal:AbortSignal.timeout(8000)});
   const b=await r.json();if(b.code!==0||!b.data?.TmpSecretKey)throw Error('credential_exchange_failed');
   current.credential=b.data;current.validUntil=now()+240000;return b.data;
  })().finally(()=>{current.pending=null;});
  await current.pending;
 }
 const credential=current.credential;
 const host='tcb.tencentcloudapi.com',timestamp=Math.floor(now()/1000),date=new Date(timestamp*1000).toISOString().slice(0,10),scope=date+'/tcb/tc3_request';
 const body=JSON.stringify({EnvId:env,Sql:parameters.length?bindSQL(query,parameters):query});
 const canonical=['POST','/','','content-type:application/json\nhost:'+host+'\n','content-type;host',sha(body)].join('\n');
 const toSign=['TC3-HMAC-SHA256',timestamp,scope,sha(canonical)].join('\n');
 const signing=hmac(hmac(hmac('TC3'+credential.TmpSecretKey,date),'tcb'),'tc3_request');
 const signature=createHmac('sha256',signing).update(toSign).digest('hex');
 const r=await fetcher('https://'+host,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`TC3-HMAC-SHA256 Credential=${credential.TmpSecretId}/${scope}, SignedHeaders=content-type;host, Signature=${signature}`,'X-TC-Action':'ExecutePGSql','X-TC-Version':'2018-06-08','X-TC-Region':region,'X-TC-Timestamp':String(timestamp),'X-TC-Token':credential.Token},body,signal:AbortSignal.timeout(12000)});
 const b=(await r.json()).Response;if(!r.ok||!b||b.Error)throw Error('sql_'+String(b?.Error?.Code||r.status));return decodeRows(b);
 };
}
export const sql=createSqlClient();
