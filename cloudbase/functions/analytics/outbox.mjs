import {hash,day,features,validate} from './core.mjs';
export const PREFIX='hyt-analytics-v2/';
export const SNAPSHOT=PREFIX+'snapshot.json';
const marker=(id,th)=>PREFIX+'auth/'+hash(id+'|'+th)+'.json';
export function mergeEvents(events){
 const grouped=new Map();
 for(const e of events){
  if(validate('record',e.body,'a'.repeat(64),e.receivedAt)!==200||!/^[a-f0-9]{64}$/.test(e.tokenHash||''))throw Error('invalid_queued_event');
  const key=e.body.id+'|'+e.tokenHash+'|'+e.body.day;
  let v=grouped.get(key);
  if(!v){v={...e.body,features:{},tokenHash:e.tokenHash};grouped.set(key,v)}
  for(const f of features)v.features[f]=Math.max(v.features[f]||0,e.body.features[f]||0);
  if(e.body.versionCode>=v.versionCode){v.version=e.body.version;v.versionCode=e.body.versionCode}
 }
 return [...grouped.values()];
}
export class Outbox {
 constructor(store,sql,now=Date.now){this.store=store;this.sql=sql;this.now=now;this.flushing=null}
 async enroll(body,th,rateKey){
  const rows=await this.sql('SELECT public.hyt_metric($1,$2::uuid,$3,$4::jsonb,$5) AS result',['enroll',body.id,th,JSON.stringify(body),rateKey]);
  const r=rows[0]?.result;if(!r?.status)throw Error('database_response');
  if(r.status===200)await this.store.put(marker(body.id,th),{id:body.id,tokenHash:th});
  return r;
 }
 async record(body,th){
  const auth=await this.store.get(marker(body.id,th));
  if(!auth||auth.id!==body.id||auth.tokenHash!==th)return {status:401,ok:false};
  const key=PREFIX+'queue/'+hash(JSON.stringify([body.id,th,body.day,body.versionCode,body.features]))+'.json';
  await this.store.put(key,{body,tokenHash:th,receivedAt:this.now()},true);
  return {status:200,ok:true,queued:true};
 }
 async delete(body,th,rateKey){
  const rows=await this.sql('SELECT public.hyt_metric($1,$2::uuid,$3,$4::jsonb,$5) AS result',['delete',body.id,th,JSON.stringify(body),rateKey]);
  const r=rows[0]?.result;if(!r?.status)throw Error('database_response');
  if(r.status===200){await this.store.remove(marker(body.id,th));await this.snapshot()}
  return r;
 }
 async stats(){
  const report=await this.store.get(SNAPSHOT);
  if(!report)throw Error('snapshot_not_ready');
  // Midnight never presents yesterday's "today" count as today's.
  if(report.day!==day(this.now()))return {...report,stale:true,awaitingRefresh:true,totals:{...report.totals,today:null,newToday:null}};
  return {...report,stale:this.now()-report.generatedAt>75*60*1000};
 }
 async snapshot(){
  const rows=await this.sql(`SELECT jsonb_build_object(
   'totals',(SELECT jsonb_build_object('total',count(*),'today',count(*) FILTER(WHERE last_day=$1::date),'newToday',count(*) FILTER(WHERE first_day=$1::date),'weekly',count(*) FILTER(WHERE last_day>=$1::date-6)) FROM public.hyt_devices WHERE first_day IS NOT NULL),
   'trend',COALESCE((SELECT jsonb_agg(t ORDER BY t.day) FROM (SELECT day,count(*) AS active FROM public.hyt_daily WHERE day >= $1::date-29 GROUP BY day)t),'[]'::jsonb),
   'versions',COALESCE((SELECT jsonb_agg(v) FROM (SELECT version,count(*) AS count FROM public.hyt_devices WHERE last_day >= $1::date-29 GROUP BY version ORDER BY count DESC)v),'[]'::jsonb)) AS result`,[day(this.now())]);
  const result=rows[0]?.result;if(!result?.totals)throw Error('database_response');
  await this.store.put(SNAPSHOT,{...result,generatedAt:this.now(),day:day(this.now()),intervalMinutes:60});
 }
 async flush(){
  if(this.flushing)return this.flushing;
  this.flushing=this.runFlush().finally(()=>{this.flushing=null});return this.flushing;
 }
 async runFlush(){
  // Immutable queue objects remain until the transaction commits. Replay is max-merge, not addition.
  const keys=await this.store.list(PREFIX+'queue/',2000);
  if(!keys.length){const report=await this.store.get(SNAPSHOT);if(report?.day===day(this.now()))return {ok:true,processed:0,limitReached:false};}
  const entries=[];
  for(let i=0;i<keys.length;i+=16)entries.push(...await Promise.all(keys.slice(i,i+16).map(async key=>({key,event:await this.store.get(key)}))));
  const valid=entries.filter(e=>e.event);
  const groups=mergeEvents(valid.map(e=>e.event));
  for(let i=0;i<groups.length;i+=300){
   await this.sql(BATCH_SQL,[JSON.stringify(groups.slice(i,i+300))]);
  }
  await this.sql("WITH old_daily AS (DELETE FROM public.hyt_daily WHERE day<$1::date-89) DELETE FROM public.hyt_rate WHERE day<$1::date-2",[day(this.now())]);
  // Publish before acknowledging objects. A failed publication replays safely next hour.
  await this.snapshot();
  for(let i=0;i<valid.length;i+=16)await Promise.all(valid.slice(i,i+16).map(e=>this.store.remove(e.key)));
  return {ok:true,processed:valid.length,limitReached:keys.length===2000};
 }
}
export const BATCH_SQL=`WITH incoming AS (
 SELECT r.* FROM jsonb_to_recordset($1::jsonb) AS r(id uuid,"tokenHash" text,day date,version text,"versionCode" int,features jsonb)
), authenticated AS (
 SELECT r.* FROM incoming r JOIN public.hyt_devices d ON d.id=r.id AND d.token_hash=r."tokenHash" FOR UPDATE OF d
), daily AS (
 INSERT INTO public.hyt_daily(device,day,features) SELECT id,day,features FROM authenticated
 ON CONFLICT(device,day) DO UPDATE SET features=(SELECT jsonb_object_agg(k,greatest(coalesce((hyt_daily.features->>k)::int,0),coalesce((excluded.features->>k)::int,0))) FROM unnest(ARRAY['schedule','tasks','learning','shower','wallet','water','laundry','parcel','grades','map']) k)
 RETURNING device
), latest AS (
 SELECT id,min(day) AS first_day,max(day) AS last_day FROM authenticated GROUP BY id
), versioned AS (SELECT DISTINCT ON(id) id,version,"versionCode" FROM authenticated ORDER BY id,"versionCode" DESC)
 UPDATE public.hyt_devices d SET first_day=coalesce(d.first_day,l.first_day),last_day=greatest(d.last_day,l.last_day),
 version=CASE WHEN v."versionCode">=d.version_code THEN v.version ELSE d.version END,version_code=greatest(d.version_code,v."versionCode"),last_write=now()
 FROM latest l JOIN versioned v ON v.id=l.id WHERE d.id=l.id`;
