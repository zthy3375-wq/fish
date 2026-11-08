import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {release,resolveDownload,publicDownloadUrl} from '../../cloudbase/functions/updates/core.mjs';
const key=process.env.PGYER_API_KEY?.trim();
if(!key)throw Error('Missing PGYER_API_KEY');
const candidate=JSON.parse(readFileSync('releases/android-candidate.json','utf8'));
if(candidate.ready===false){console.log('Candidate awaits rebuilt APK');process.exit(0)}
release({...candidate,buildKey:'validation'});
const existing=JSON.parse(readFileSync('cloudbase/functions/updates/releases.json','utf8')).releases.find(r=>r.versionCode===candidate.versionCode);
if(existing){
 if(existing.sha256!==candidate.sha256)throw Error('Version code already belongs to different APK');
 console.log('Candidate already published; skipping upload');
 process.exit(0);
}
if(candidate.sourceUrl!==`https://hanyuantong-updates.dewydahlia.chatgpt.site/android/Hanyuantong-v${candidate.versionName}.apk`)throw Error('Unexpected APK source');
const sha=b=>createHash('sha256').update(b).digest('hex');
const source=await fetch(candidate.sourceUrl,{redirect:'error',signal:AbortSignal.timeout(60000)});
if(!source.ok)throw Error('APK source unavailable');
const bytes=Buffer.from(await source.arrayBuffer());
if(bytes.length!==candidate.sizeBytes||sha(bytes)!==candidate.sha256)throw Error('Source APK checksum mismatch');
async function api(path,params={},method='POST'){
 const form=new URLSearchParams({_api_key:key,...params});
 const url='https://www.pgyer.com/apiv2/app/'+path;
 const response=await fetch(method==='GET'?url+'?'+form:url,{method,redirect:'error',...(method==='POST'?{body:form}:{}),signal:AbortSignal.timeout(45000)});
 if(!response.ok)throw Error('Pgyer API HTTP '+response.status);
 return response.json();
}
let verified;
if(candidate.buildKey){verified=release(candidate)}else{
const token=await api('getCOSToken',{buildType:'android',buildUpdateDescription:candidate.notes.join('\n')});
if(token.code!==0)throw Error('Pgyer upload authorization code '+token.code);
const upload=token.data,endpoint=new URL(upload.endpoint);
if(endpoint.protocol!=='https:'||!endpoint.hostname.endsWith('.myqcloud.com')||endpoint.username||endpoint.password)throw Error('Untrusted upload endpoint');
const form=new FormData();
for(const [name,value] of Object.entries(upload.params))form.set(name,String(value));
form.set('file',new Blob([bytes],{type:'application/vnd.android.package-archive'}),`Hanyuantong-${candidate.versionName}.apk`);
const sent=await fetch(endpoint,{method:'POST',body:form,redirect:'error',signal:AbortSignal.timeout(120000)});
if(sent.status!==204)throw Error('Pgyer upload HTTP '+sent.status);
let info;
for(let i=0;i<60;i++){
 const result=await api('buildInfo',{buildKey:upload.key},'GET');
 if(result.code===0){info=result.data;break}
 if(result.code!==1247)throw Error('Pgyer build code '+result.code);
 await new Promise(resolve=>setTimeout(resolve,5000));
}
if(!info)throw Error('Pgyer publishing timed out');
if(info.buildIdentifier!=='org.handancampus.app'||Number(info.buildVersionNo)!==candidate.versionCode||info.buildVersion!==candidate.versionName||Number(info.buildFileSize)!==candidate.sizeBytes)throw Error('Published APK metadata mismatch');
verified=release({...candidate,buildKey:info.buildKey});
mkdirSync('release-evidence',{recursive:true});
writeFileSync('release-evidence/upload.json',JSON.stringify({release:verified,shortcut:info.buildShortcutUrl},null,2)+'\n');
console.log(JSON.stringify({uploaded:true,versionCode:verified.versionCode,buildKey:verified.buildKey}));
}
mkdirSync('release-evidence',{recursive:true});
let url=await resolveDownload(verified,key),download;
for(let i=0;i<6;i++){
 if(!publicDownloadUrl(url)||url.includes(key))throw Error('Untrusted APK redirect');
 download=await fetch(url,{redirect:'manual',headers:{'User-Agent':'Hanyuantong/Android (Linux; Android 13)'},signal:AbortSignal.timeout(60000)});
 if(download.status===200)break;
 if(![301,302,303,307,308].includes(download.status))throw Error('APK download HTTP '+download.status);
 url=new URL(download.headers.get('location'),url).href;
}
if(download?.status!==200)throw Error('APK redirect limit');
const downloaded=Buffer.from(await download.arrayBuffer());
if(downloaded.length!==candidate.sizeBytes||sha(downloaded)!==candidate.sha256)throw Error('Pgyer APK checksum mismatch');
const catalog=JSON.parse(readFileSync('cloudbase/functions/updates/releases.json','utf8'));
catalog.latest=verified.versionCode;
catalog.releases=[...catalog.releases.filter(r=>r.versionCode!==verified.versionCode),verified];
writeFileSync('cloudbase/functions/updates/releases.json',JSON.stringify(catalog,null,2)+'\n');
writeFileSync('release-evidence/releases.json',JSON.stringify(catalog,null,2)+'\n');
console.log('Pgyer APK bytes and checksum verified; release ready for Tencent deployment');
