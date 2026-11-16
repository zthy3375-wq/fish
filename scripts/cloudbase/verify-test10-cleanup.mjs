// One-time verification of this run's disposable 4x4 media only.
import {createHash} from 'node:crypto';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {cloudMedia,cleanImage} from '../../cloudbase/functions/community/media.mjs';
import jpeg from '../../cloudbase/functions/community/node_modules/jpeg-js/index.js';
if(process.env.GITHUB_REF!=='refs/heads/chore/community-test10-cleanup-20261116')throw Error('Unexpected maintenance branch');
process.env.CLOUDBASE_ENV_ID='hanyuantong-d8gjzt1jh12370215';
process.env.CLOUDBASE_APIKEY=process.env.CLOUDBASE_API_KEY?.trim();
if(!process.env.CLOUDBASE_APIKEY)throw Error('Missing service credential');
const from='2026-11-16T06:13:30Z',to='2026-11-16T06:15:20Z';
const query="SELECT o.name FROM storage.objects o WHERE o.bucket_id='hyt-community' AND o.created_at >= $1::timestamptz AND o.created_at <= $2::timestamptz AND NOT EXISTS(SELECT 1 FROM public.hyt_media m WHERE m.object_key=o.name) ORDER BY o.name LIMIT 3";
const candidates=await sql(query,[from,to]);if(candidates.length>2)throw Error('Unexpected orphan count');
const fixture=jpeg.encode({width:4,height:4,data:Buffer.alloc(4*4*4,125)},75).data.toString('base64');
const hash=b=>createHash('sha256').update(b).digest('hex');
const allowed=new Set([hash(cleanImage(fixture).bytes),hash(cleanImage(fixture,true).bytes)]);
const media=cloudMedia();let removed=0;
for(const row of candidates){
 if(!/^[0-9a-f-]{36}\.jpg$/.test(row.name))throw Error('Unexpected object name');
 const response=await fetch(await media.url(row.name),{signal:AbortSignal.timeout(18000)});
 if(!response.ok||!allowed.has(hash(Buffer.from(await response.arrayBuffer()))))throw Error('Object differs from disposable test fixture');
 if((await sql('SELECT id FROM public.hyt_media WHERE object_key=$1',[row.name])).length)throw Error('Object became referenced');
 for(let attempt=0;attempt<3;attempt++){try{await media.remove(row.name);break;}catch(e){if(attempt===2)throw e;await new Promise(r=>setTimeout(r,2000));}}
 removed++;
}
const remaining=await sql(query,[from,to]);if(remaining.length)throw Error('Test media still present');
const accounts=await sql("SELECT count(*) AS count FROM public.hyt_members WHERE username LIKE 'smoke_%' AND created_at >= $1::timestamptz AND created_at <= $2::timestamptz",[from,to]);
if(Number(accounts[0].count)!==0)throw Error('Disposable identities still present');
console.log(JSON.stringify({scope:'test10-disposable-fixtures',candidates:candidates.length,removed,remaining:remaining.length,remainingTestAccounts:Number(accounts[0].count),referencedObjectsUntouched:true}));
