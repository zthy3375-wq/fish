import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {createCommunity,CommunityError} from './core.mjs';
import {sql} from './database.mjs';

export function createServer(community,{allowedOrigins=[]}={}){
 return http.createServer(async(req,res)=>{
  const origin=req.headers.origin;
  const headers={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
  if(origin&&allowedOrigins.includes(origin))Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Headers':'Authorization,Content-Type','Access-Control-Allow-Methods':'GET,POST,OPTIONS'});
  const send=(status,body)=>{res.writeHead(status,headers);res.end(JSON.stringify(body));};
  if(origin&&!allowedOrigins.includes(origin))return send(403,{error:'origin_not_allowed'});
  if(req.method==='OPTIONS')return send(204,{});
  const path=new URL(req.url,'http://localhost').pathname.replace(/^\/hyt-community/,'');
  if(req.method==='GET'&&path==='/health')return send(200,{ok:true,service:'hyt-community',schema:1});
  if(req.method==='GET'&&path==='/v1/config')return send(200,community.config());
  if(req.method!=='POST'||!/^\/v1\/[a-z.]+$/.test(path))return send(404,{error:'not_found'});
  if(!/^application\/json(?:;|$)/i.test(req.headers['content-type']||''))return send(415,{error:'json_required'});
  if(Number(req.headers['content-length']||0)>20000)return send(413,{error:'request_too_large'});
  try{
   const chunks=[];let length=0;
   for await(const chunk of req){length+=chunk.length;if(length>20000){send(413,{error:'request_too_large'});req.destroy();return;}chunks.push(chunk);}
   let data;try{data=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return send(400,{error:'invalid_json'});}
   const auth=req.headers.authorization||'';const bearer=auth.startsWith('Bearer ')?auth.slice(7):'';
   // Trust the provider-injected client IP only in explicitly configured CloudBase deployment.
   const peer=process.env.COMMUNITY_TRUST_PROXY==='cloudbase'?String(req.headers['x-real-ip']||req.socket.remoteAddress||'unknown'):String(req.socket.remoteAddress||'unknown');
   const result=await community.execute(path.slice(4),data,bearer,peer);
   const {status,...body}=result;send(status,body);
  }catch(e){
   if(e instanceof CommunityError)return send(e.status,{error:e.code});
   console.error('Community request failed',e instanceof SyntaxError?'invalid_json':'service_unavailable');
   send(503,{error:'temporarily_unavailable'});
  }
 });
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const db=async(action,data,token)=>{const rows=await sql('SELECT public.hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(data),token]);return rows[0]?.result;};
 const community=createCommunity({db,registrationEnabled:process.env.COMMUNITY_REGISTRATION==='open',inviteHash:process.env.COMMUNITY_INVITE_HASH||'',rateSalt:process.env.COMMUNITY_RATE_SALT});
 const origins=['https://localhost','capacitor://localhost',...(process.env.COMMUNITY_WEB_ORIGINS||'').split(',').filter(Boolean)];
 createServer(community,{allowedOrigins:origins}).listen(Number(process.env.PORT||9000),'0.0.0.0');
}
