import http from 'node:http';
import {readFileSync} from 'node:fs';
const dashboard=readFileSync(new URL('./dashboard.html',import.meta.url),'utf8');
import {hash,day,validate,authorized,readBody} from './core.mjs';
const env=process.env.CLOUDBASE_ENV_ID;
const apiKey=process.env.CLOUDBASE_APIKEY;
export async function sql(query,parameters=[]){
 const r=await fetch(`https://${env}.api.tcloudbasegateway.com/v1/rdb/exec-pgsql`,{method:'POST',headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json'},body:JSON.stringify({sql:query,parameters}),signal:AbortSignal.timeout(12000)});
 let b;try{b=await r.json()}catch{throw Error('sql_non_json_'+r.status)}if(!r.ok||b.code){console.error('SQL request rejected',r.status,/^[A-Z0-9_]{1,80}$/.test(String(b.code))?b.code:'unknown');throw Error('sql_'+r.status+'_'+String(b.code||'unknown').replace(/[^A-Z0-9_]/gi,'').slice(0,60));}
 const rows=Array.isArray(b)?b:(b.rows||b.data?.rows||b.data||b.result?.rows);
 if(!Array.isArray(rows))throw Error('database_response');return rows;
}
function reply(res,code,b){res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(b))}
http.createServer(async(req,res)=>{
 try{
  const path=new URL(req.url,'https://localhost').pathname;
  if(path.endsWith('/health'))return reply(res,200,{ok:true,service:'hyt-analytics',revision:'1'});
  if(path.endsWith('/dashboard')&&req.method==='GET'){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});return res.end(dashboard)}
  if(path.endsWith('/stats')){
   if(!process.env.ANALYTICS_ADMIN_TOKEN_HASH||!authorized(hash(req.headers.authorization?.replace(/^Bearer /,'')||''),process.env.ANALYTICS_ADMIN_TOKEN_HASH))return reply(res,403,{error:'forbidden'});
   if(req.method!=='GET')return reply(res,405,{error:'method'});
   const rows=await sql(`SELECT jsonb_build_object('total',count(*),'today',count(*) FILTER(WHERE last_day=$1::date),'newToday',count(*) FILTER(WHERE first_day=$1::date),'weekly',count(*) FILTER(WHERE last_day>=$1::date-6)) AS totals FROM public.hyt_devices WHERE first_day IS NOT NULL`,[day()]);
   const trend=await sql('SELECT day,count(*) AS active FROM public.hyt_daily WHERE day >= $1::date-29 GROUP BY day ORDER BY day',[day()]);
   const versions=await sql('SELECT version,count(*) AS count FROM public.hyt_devices WHERE last_day >= $1::date-29 GROUP BY version ORDER BY count DESC',[day()]);
   return reply(res,200,{...rows[0],trend,versions});
  }
  if(req.method!=='POST')return reply(res,405,{error:'method'});
  if(!req.headers['content-type']?.startsWith('application/json'))return reply(res,415,{error:'content_type'});
  const action=path.split('/').pop(),token=req.headers.authorization?.replace(/^Bearer /,'');
  let b;try{b=await readBody(req)}catch{return reply(res,400,{error:'invalid_request'})}
  const status=validate(action,b,token);if(status!==200)return reply(res,status,{error:'invalid_request'});
  // The gateway supplies X-Real-IP. Never persist raw addresses or request bodies.
  const ip=String(req.headers['x-real-ip']||req.socket.remoteAddress||'unknown');
  const rows=await sql('SELECT public.hyt_metric($1,$2::uuid,$3,$4::jsonb,$5) AS result',[action,b.id,hash(token),JSON.stringify(b),hash(process.env.ANALYTICS_SALT+'|'+day()+'|'+ip)]);
  const result=rows[0]?.result;if(!result?.status)throw Error('database_response');const {status:code,...body}=result;reply(res,code,body);
 }catch(e){console.error('Analytics request failed', ['database_unavailable','database_response'].includes(e.message)?e.message:e.name, String(e.cause?.code||'').replace(/[^A-Z0-9_]/g,'').slice(0,60));reply(res,503,{error:'temporarily_unavailable',...(process.env.ANALYTICS_ADMIN_TOKEN_HASH&&authorized(hash(req.headers.authorization?.replace(/^Bearer /,'')||''),process.env.ANALYTICS_ADMIN_TOKEN_HASH)?{diagnostic:String(e.message).slice(0,160),cause:String(e.cause?.code||'')}:{} )})}
}).listen(9000,'0.0.0.0');
