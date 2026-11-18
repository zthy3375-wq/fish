import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {hash,day,validate,readBody} from './core.mjs';
import {deleteLegacyObjects} from './legacy-deletion.mjs';
import {sql} from './database.mjs';

export function retiredAnalytics(query=sql,purge=deleteLegacyObjects){
 return http.createServer(async(req,res)=>{
  function reply(code,body){res.writeHead(code,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(body))}
  const path=new URL(req.url,'http://localhost').pathname.replace(/^\/hyt-analytics(?:-canary)?(?=\/)/,'');
  if(req.method==='GET'&&path==='/health')return reply(200,{ok:true,collection:false});
  if(req.method==='POST'&&path==='/internal/flush'){req.resume();return reply(200,{ok:true,processed:0,collection:false})}
  if(req.method!=='POST')return reply(410,{error:'retired'});
  if(path==='/api/metrics/enroll'||path==='/api/metrics/record'){
   // A successful acknowledgement lets older installations clear their local retry queue.
   req.resume();return reply(200,{ok:true,collection:false});
  }
  if(path!=='/api/metrics/delete')return reply(404,{error:'not_found'});
  let body;try{body=await readBody(req)}catch{return reply(400,{error:'invalid_request'})}
  const token=req.headers['x-hyt-token'],status=validate('delete',body,token);
  if(status!==200)return reply(status,{error:'invalid_request'});
  try{
   const ip=String(req.headers['x-real-ip']||req.socket.remoteAddress||'unknown');
   const rows=await query('SELECT public.hyt_metric($1,$2::uuid,$3,$4::jsonb,$5) AS result',['delete',body.id,hash(token),JSON.stringify(body),hash(process.env.ANALYTICS_SALT+'|'+day()+'|'+ip)]);
   const {status:code,...result}=rows[0].result;
   if(code===200&&result.ok)await purge(body.id,hash(token));
   reply(code,result);
  }catch{reply(503,{error:'temporarily_unavailable'})}
 });
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)retiredAnalytics().listen(9000,'0.0.0.0');
