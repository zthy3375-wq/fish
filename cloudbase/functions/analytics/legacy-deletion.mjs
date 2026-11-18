import {hash} from './core.mjs';
import {credentials} from './database.mjs';

const prefix='hyt-analytics-v2/';
let client;
async function store(){
 if(client)return client;
 const bucket=process.env.ANALYTICS_BUCKET;
 if(!/^[a-z0-9-]+-\d+$/.test(bucket||''))throw Error('legacy_bucket_unavailable');
 const {default:COS}=await import('cos-nodejs-sdk-v5');
 const cos=new COS({getAuthorization(_,cb){credentials().then(c=>cb({TmpSecretId:c.TmpSecretId,TmpSecretKey:c.TmpSecretKey,SecurityToken:c.Token,StartTime:Math.floor(Date.now()/1000)-30,ExpiredTime:Math.floor(Date.now()/1000)+180})).catch(()=>cb({}))}});
 const call=(method,fields)=>new Promise((resolve,reject)=>cos[method]({Bucket:bucket,Region:'ap-shanghai',...fields},(err,data)=>err?reject(err):resolve(data)));
 client={
  async get(key){try{const r=await call('getObject',{Key:key});return JSON.parse(String(r.Body))}catch(e){if(e.statusCode===404)return null;throw e}},
  remove:key=>call('deleteObject',{Key:key}),
  async page(marker){const r=await call('getBucket',{Prefix:prefix+'queue/',Marker:marker,MaxKeys:100});return {keys:(r.Contents??[]).map(x=>x.Key),next:String(r.IsTruncated)==='true'?r.NextMarker:null,truncated:String(r.IsTruncated)==='true'}}
 };
 return client;
}
export async function deleteLegacyObjects(id,tokenHash,adapter){
 const storage=adapter??await store();
 const marker=prefix+'auth/'+hash(id+'|'+tokenHash)+'.json';
 const auth=await storage.get(marker);
 if(!auth)return;
 if(auth.id!==id||auth.tokenHash!==tokenHash)throw Error('legacy_identity_mismatch');
 // Events were keyed by payload hash, not by device. Keep the owner marker until the last page succeeds.
 let cursor='';
 for(;;){
  const page=await storage.page(cursor);
  for(let i=0;i<page.keys.length;i+=8)await Promise.all(page.keys.slice(i,i+8).map(async key=>{
   if(!key.startsWith(prefix+'queue/'))throw Error('legacy_queue_key');
   const event=await storage.get(key);
   if(event?.body?.id===id&&event.tokenHash===tokenHash)await storage.remove(key);
  }));
  if(!page.truncated)break;
  if(!page.next||page.next<=cursor)throw Error('legacy_queue_cursor');
  cursor=page.next;
 }
 await storage.remove(marker);
}
