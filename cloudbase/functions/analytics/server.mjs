import http from 'node:http';
import {readFileSync} from 'node:fs';
const dashboard=readFileSync(new URL('./dashboard.html',import.meta.url),'utf8');
import {hash,day,validate,authorized,readBody} from './core.mjs';
import {sql} from './database.mjs';
import {createStore} from './storage.mjs';
import {Outbox} from './outbox.mjs';
const outboxReady=createStore().then(store=>new Outbox(store,sql));
// Observe initialization failures without acknowledging any metric before durable storage is ready.
outboxReady.catch(()=>{});
function reply(res,code,b){res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(b))}
http.createServer(async(req,res)=>{
 try{
  const path=new URL(req.url,'https://localhost').pathname;
  if(path.endsWith('/health'))return reply(res,200,{ok:true,service:'hyt-analytics',revision:'hourly-v2'});
  if(path.endsWith('/dashboard')&&req.method==='GET'){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});return res.end(dashboard)}
  if(path.endsWith('/stats')){
   if(!process.env.ANALYTICS_ADMIN_TOKEN_HASH||!authorized(hash(req.headers['x-hyt-token']||''),process.env.ANALYTICS_ADMIN_TOKEN_HASH))return reply(res,403,{error:'forbidden'});
   if(req.method!=='GET')return reply(res,405,{error:'method'});
   return reply(res,200,await (await outboxReady).stats());
  }
  if(path.endsWith('/internal/flush')){
   if(req.method!=='POST'||!process.env.ANALYTICS_BATCH_TOKEN_HASH||!authorized(hash(req.headers['x-hyt-batch-token']||''),process.env.ANALYTICS_BATCH_TOKEN_HASH))return reply(res,403,{error:'forbidden'});
   return reply(res,200,await (await outboxReady).flush());
  }
  if(req.method!=='POST')return reply(res,405,{error:'method'});
  if(!req.headers['content-type']?.startsWith('application/json'))return reply(res,415,{error:'content_type'});
  const action=path.split('/').pop(),token=req.headers['x-hyt-token'];
  let b;try{b=await readBody(req)}catch{return reply(res,400,{error:'invalid_request'})}
  const status=validate(action,b,token);if(status!==200)return reply(res,status,{error:'invalid_request'});
  // The gateway supplies X-Real-IP. Never persist raw addresses or request bodies.
  const ip=String(req.headers['x-real-ip']||req.socket.remoteAddress||'unknown');
  const service=await outboxReady;
  const result=await service[action](b,hash(token),hash(process.env.ANALYTICS_SALT+'|'+day()+'|'+ip));
  const {status:code,...body}=result;reply(res,code,body);
 }catch(e){console.error('Analytics request failed', ['database_unavailable','database_response'].includes(e.message)?e.message:e.name, String(e.cause?.code||'').replace(/[^A-Z0-9_]/g,'').slice(0,60));reply(res,503,{error:'temporarily_unavailable',...(process.env.ANALYTICS_ADMIN_TOKEN_HASH&&authorized(hash(req.headers['x-hyt-token']||''),process.env.ANALYTICS_ADMIN_TOKEN_HASH)?{diagnostic:String(e.message).slice(0,160),cause:String(e.cause?.code||'')}:{} )})}
}).listen(9000,'0.0.0.0');
