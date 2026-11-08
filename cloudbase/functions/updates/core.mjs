export const ORIGIN='https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com';
export const BASE=ORIGIN+'/hyt-updates';
export function release(input){
 const {versionCode,versionName,minSupportedVersionCode,minSdk,sha256,sizeBytes,notes,buildKey}=input??{};
 if(!Number.isInteger(versionCode)||versionCode<1||versionCode>2147483647||!Number.isInteger(minSupportedVersionCode)||minSupportedVersionCode<1||minSupportedVersionCode>versionCode||!Number.isInteger(minSdk)||minSdk<23||minSdk>100||typeof versionName!=='string'||!versionName.trim()||versionName.length>40||!/^[a-f0-9]{64}$/.test(sha256??'')||!Number.isInteger(sizeBytes)||sizeBytes<1||sizeBytes>80*1024*1024||!Array.isArray(notes)||notes.length>20||notes.some(n=>typeof n!=='string'||n.length>500)||!/^[A-Za-z0-9]{8,64}$/.test(buildKey??''))throw Error('invalid_release');
 return {schema:1,versionCode,versionName,minSupportedVersionCode,minSdk,sha256,sizeBytes,notes,buildKey};
}
export function catalog(input){
 if(!Array.isArray(input?.releases))throw Error('invalid_catalog');
 const releases=input.releases.map(release);
 if(new Set(releases.map(r=>r.versionCode)).size!==releases.length)throw Error('duplicate_release');
 const current=releases.find(r=>r.versionCode===input.latest);
 if(input.latest!==null&&!current)throw Error('missing_latest');
 return {current,releases};
}
export function manifest(r){const {buildKey,...data}=release(r);return {...data,apkUrl:BASE+'/android/download/'+data.versionCode}}
export function publicDownloadUrl(raw){
 try{const u=new URL(raw);return u.protocol==='https:'&&(u.hostname==='pgyer.com'||u.hostname.endsWith('.pgyer.com'))&&(!u.port||u.port==='443')&&!u.username&&!u.password&&!u.hash&&![...u.searchParams.keys()].some(k=>/^(?:_api_key|api_key|buildpassword)$/i.test(k))}catch{return false}
}
export async function resolveDownload(r,key,fetcher=fetch){
 if(!key?.trim())throw Error('provider_not_configured');
 const url=new URL('https://www.pgyer.com/apiv2/app/install');
 url.search=new URLSearchParams({_api_key:key.trim(),buildKey:release(r).buildKey}).toString();
 const response=await fetcher(url,{redirect:'manual',headers:{'User-Agent':'Hanyuantong/Android (Linux; Android 13)'},signal:AbortSignal.timeout(15000)});
 const target=response.headers.get('location');
 // Never send the API-key-bearing install URL or unverified redirects to a device.
 if(![301,302,303,307,308].includes(response.status)||!target||!publicDownloadUrl(target)||target.includes(key.trim())){
  let host='none',code='unknown';
  try{const h=new URL(target).hostname;if(/^[a-z0-9.-]+$/i.test(h)&&!h.includes(key.trim()))host=h}catch{}
  try{const body=await response.json();if(Number.isInteger(body.code))code=String(body.code)}catch{}
  throw Error('provider_download_unavailable: HTTP '+response.status+' host '+host+' code '+code);
 }
 return target;
}
