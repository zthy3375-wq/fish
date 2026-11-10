import {credentials} from './database.mjs';
export async function createStore(){
 const {default:COS}=await import('cos-nodejs-sdk-v5');
 const bucket=process.env.ANALYTICS_BUCKET;if(!/^[a-z0-9-]+-\d+$/.test(bucket||''))throw Error('storage_not_configured');
 const cos=new COS({getAuthorization(_options,cb){credentials().then(c=>cb({TmpSecretId:c.TmpSecretId,TmpSecretKey:c.TmpSecretKey,SecurityToken:c.Token,StartTime:Math.floor(Date.now()/1000)-30,ExpiredTime:Math.floor(Date.now()/1000)+180})).catch(()=>cb({}))}});
 const call=(method,args)=>new Promise((resolve,reject)=>cos[method]({Bucket:bucket,Region:'ap-shanghai',...args},(err,data)=>err?reject(err):resolve(data)));
 return {
  async get(key){try{const r=await call('getObject',{Key:key});return JSON.parse(String(r.Body))}catch(e){if(e.statusCode===404)return null;throw e}},
  async put(key,value,immutable=false){try{await call('putObject',{Key:key,Body:JSON.stringify(value),ContentType:'application/json',ACL:'private',...(immutable?{Headers:{'x-cos-forbid-overwrite':'true'}}:{})})}catch(e){if(!(immutable&&e.statusCode===409))throw e}},
  async remove(key){await call('deleteObject',{Key:key})},
  async list(prefix,limit){let marker='',keys=[];do{const r=await call('getBucket',{Prefix:prefix,Marker:marker,MaxKeys:Math.min(1000,limit-keys.length)});keys.push(...(r.Contents||[]).map(o=>o.Key));if(String(r.IsTruncated)!=='true')break;marker=r.NextMarker;if(!marker)throw Error('storage_pagination')}while(keys.length<limit);return keys}
 };
}
