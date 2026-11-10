import {createHash,timingSafeEqual} from 'node:crypto';
export const features=['schedule','tasks','learning','shower','wallet','water','laundry','parcel','grades','map'];
export const hash=s=>createHash('sha256').update(s).digest('hex');
export const day=(now=Date.now())=>new Date(now+28800000).toISOString().slice(0,10);
export function validate(action,b,token,now=Date.now()){
 if(!['enroll','record','delete'].includes(action))return 404;
 if(!/^[a-f0-9]{64}$/.test(token||''))return 401;
 if(!b||Array.isArray(b)||typeof b!=='object'||!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(b.id||''))return 400;
 const allowed=action==='record'?['id','day','version','versionCode','features']:['id'];
 if(Object.keys(b).some(k=>!allowed.includes(k)))return 400;
 if(action==='record'){
  if(![day(now),day(now-86400000)].includes(b.day)||!/^\d{1,4}\.\d{1,4}\.\d{1,4}(?:-[A-Za-z0-9][A-Za-z0-9.-]{0,39})?$/.test(b.version||'')||!Number.isInteger(b.versionCode)||b.versionCode<102||b.versionCode>2147483647)return 400;
  if(!b.features||Array.isArray(b.features)||typeof b.features!=='object'||Object.entries(b.features).some(([k,v])=>!features.includes(k)||!Number.isInteger(v)||v<0||v>1000))return 400;
 }
 return 200;
}
export function authorized(value,expected){return !!expected&&typeof value==='string'&&timingSafeEqual(Buffer.from(hash(value)),Buffer.from(hash(expected)))}
export async function readBody(req){let n=0;const parts=[];for await(const part of req){n+=part.length;if(n>2048)throw Error('size');parts.push(part)}return JSON.parse(Buffer.concat(parts).toString())}
