import jpeg from 'jpeg-js';

export const MAX_IMAGE_BYTES=1_200_000;
let decoding=false;
export function cleanImage(base64,avatar=false){
 if(decoding)throw Object.assign(Error('too_many_requests'),{status:429,code:'too_many_requests'});
 decoding=true;
 try{
  const bytes=Buffer.from(base64,'base64');
  if(bytes.length>MAX_IMAGE_BYTES||bytes.length<4||bytes[0]!==255||bytes[1]!==216)throw Error();
  const decoded=jpeg.decode(bytes,{useTArray:true,maxResolutionInMP:4,maxMemoryUsageInMB:96,tolerantDecoding:false});
  if(decoded.width>2000||decoded.height>2000||decoded.width*decoded.height>4_000_000)throw Error();
  // Deliberately pass pixels only: EXIF, comments, original filenames and metadata never survive.
  let pixels=decoded;
  if(avatar){
   const size=Math.min(512,decoded.width,decoded.height),side=Math.min(decoded.width,decoded.height),left=(decoded.width-side)/2,top=(decoded.height-side)/2;
   const data=new Uint8Array(size*size*4);
   for(let y=0;y<size;y++)for(let x=0;x<size;x++){const src=(Math.min(decoded.height-1,Math.floor(top+(y+.5)*side/size))*decoded.width+Math.min(decoded.width-1,Math.floor(left+(x+.5)*side/size)))*4;data.set(decoded.data.subarray(src,src+4),(y*size+x)*4);}
   pixels={data,width:size,height:size};
  }
  const output=jpeg.encode({data:pixels.data,width:pixels.width,height:pixels.height},78).data;
  if(output.length>MAX_IMAGE_BYTES)throw Error();
  return {bytes:Buffer.from(output),width:pixels.width,height:pixels.height};
 }catch(e){if(e.code)throw e;throw Object.assign(Error('invalid_image'),{status:400,code:'invalid_image'});}
 finally{decoding=false;}
}
const BUCKET='hyt-community';
export function cloudMedia({env=process.env.CLOUDBASE_ENV_ID,key=process.env.CLOUDBASE_APIKEY,fetcher=fetch,now=Date.now}={}){
 const origin=`https://${env}.api.tcloudbasegateway.com`;
 async function request(path,{method='POST',body,headers={}}={}){
  const r=await fetcher(origin+'/v1/storages/'+path,{method,headers:{Authorization:'Bearer '+key,...headers},body,signal:AbortSignal.timeout(18000),redirect:'error'});
  if(!r.ok){if(method==='DELETE'&&r.status===404)return {};throw Error('media_storage_'+r.status);}
  const raw=await r.text();return raw?JSON.parse(raw):{};
 }
 const signed=new Map();
 const objectPath=id=>BUCKET+'/'+encodeURIComponent(id);
 return {
  async put(id,bytes){signed.delete(id);await request('object/'+objectPath(id),{headers:{'Content-Type':'image/jpeg','Cache-Control':'private, max-age=600','x-upsert':'true','x-robots-tag':'noindex'},body:bytes});},
  async url(id){const r=await request('object/sign/'+objectPath(id),{headers:{'Content-Type':'application/json'},body:JSON.stringify({expiresIn:600})});
   if(typeof r.signedURL!=='string')throw Error('media_url_missing');const url=new URL(r.signedURL,origin);if(url.protocol!=='https:'||url.origin!==origin)throw Error('media_url_invalid');return url.href;},
  async urls(ids,{fresh=false}={}){
   // Callers supply only object keys returned by the current viewer's permission-filtered SQL.
   const result=new Map(),missing=new Set(),started=now();
   for(const id of ids){
    const hit=signed.get(id);
    if(!fresh&&hit&&hit.until>started)result.set(id,hit.url);else missing.add(id);
   }
   if(!missing.size)return result;
   const rows=await request('object/sign/'+BUCKET,{headers:{'Content-Type':'application/json'},body:JSON.stringify({paths:[...missing],expiresIn:600})});
   if(!Array.isArray(rows))throw Error('media_url_missing');
   for(const row of rows){
    if(!missing.has(row.path)||row.error||!row.signedURL)continue;
    const url=new URL(row.signedURL,origin);
    if(url.protocol!=='https:'||url.origin!==origin)continue;
    result.set(row.path,url.href);
    signed.delete(row.path);signed.set(row.path,{url:url.href,until:started+240000});
    if(signed.size>512)signed.delete(signed.keys().next().value);
   }
   return result;
  },
  async remove(id){signed.delete(id);await request('object/'+objectPath(id),{method:'DELETE'});},
  async ensureBucket(){
   const r=await fetcher(origin+'/v1/storages/bucket/'+BUCKET,{headers:{Authorization:'Bearer '+key},signal:AbortSignal.timeout(18000)});
   if(r.ok){const b=await r.json();if(b.public===true)throw Error('community_bucket_must_be_private');return;}
   if(r.status!==404)throw Error('media_bucket_'+r.status);
   await request('bucket/',{headers:{'Content-Type':'application/json'},body:JSON.stringify({id:BUCKET,name:BUCKET,public:false,file_size_limit:MAX_IMAGE_BYTES,allowed_mime_types:['image/jpeg']})});
  }
 };
}
