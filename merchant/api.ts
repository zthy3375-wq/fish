import type {CommerceRequest} from '../src/services/commerce';

const production='https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community/v1/';
const endpoint=new URL(import.meta.env.VITE_COMMERCE_API||production);
if(!['https:','http:'].includes(endpoint.protocol)||endpoint.protocol==='http:'&&!['127.0.0.1','localhost'].includes(endpoint.hostname))throw new Error('invalid_endpoint');
let token='';
let sessionVersion=0;

async function send<T>(action:string,body:Record<string,unknown>,key=token):Promise<T>{
 const url=new URL(action,endpoint);
 const version=sessionVersion;
 let response:Response;
 try{
  response=await fetch(url,{method:'POST',redirect:'error',cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer',
   headers:{'Content-Type':'application/json',...(key?{Authorization:'Bearer '+key}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(25_000)});
 }catch{throw Error('network_unavailable');}
 const result=await response.json().catch(()=>null);
 if(!response.ok||!result)throw Error(result?.error||'temporarily_unavailable');
 if(version!==sessionVersion&&action!=='logout')throw Error('session_expired');
 return result as T;
}
export const request:CommerceRequest=(action,body={})=>send('commerce.'+action,{...body,platform:'web'});
export async function signIn(username:string,password:string,nickname?:string){
 const version=sessionVersion;
 const result=await send<{sessionToken:string}>(nickname?'register':'login',{username,password,...(nickname?{nickname,agreed:true}:{})},'');
 if(!/^[A-Za-z0-9_-]{43}$/.test(result.sessionToken)||version!==sessionVersion)throw Error('invalid_response');
 token=result.sessionToken;
}
export async function signOut(){
 const key=token;
 token='';sessionVersion++;
 if(key)await send('logout',{},key).catch(()=>{});
}
export async function upload(file:File,purpose:'shop'|'ad'|'qualification'|'contract'){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>18_000_000)throw Error('invalid_image');
 const source=URL.createObjectURL(file);
 try{
  const image=new Image();
  image.src=source;
  await image.decode();
  if(image.width*image.height>50_000_000)throw Error('invalid_image');
  const scale=Math.min(1,1440/Math.max(image.width,image.height));
  const canvas=document.createElement('canvas');
  canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));
  const context=canvas.getContext('2d');
  if(!context)throw Error('invalid_image');
  context.fillStyle='#fff';context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(image,0,0,canvas.width,canvas.height);
  const quality=(purpose==='qualification'||purpose==='contract') ? .88 : .79;
  let data=canvas.toDataURL('image/jpeg',quality).split(',')[1];
  if(data.length>1_500_000)data=canvas.toDataURL('image/jpeg',.67).split(',')[1];
  if(data.length>1_500_000)throw Error('invalid_image');
  return (await request<{id:string}>('media.upload',{id:crypto.randomUUID(),purpose,data})).id;
 }finally{URL.revokeObjectURL(source);}
}
export function chinaTime(local:string){return new Date(local+':00+08:00').toISOString();}
export function localTime(timestamp:string){
 return new Date(Date.parse(timestamp)+8*3600_000).toISOString().slice(0,16);
}
