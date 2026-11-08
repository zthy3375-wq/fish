import http from 'node:http';
import {readFileSync} from 'node:fs';
import {catalog,manifest,resolveDownload} from './core.mjs';
const state=catalog(JSON.parse(readFileSync(new URL('./releases.json',import.meta.url))));
const key=process.env.PGYER_API_KEY;
function json(res,status,body){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(body))}
http.createServer(async(req,res)=>{
 const path=new URL(req.url,'https://localhost').pathname.replace(/^\/hyt-updates(?=\/)/,'');
 if(req.method!=='GET')return json(res,405,{error:'method'});
 if(path==='/health')return json(res,200,{ok:true,service:'hyt-updates',providerConfigured:Boolean(key?.trim()),releaseConfigured:Boolean(state.current)});
 if(path==='/android/stable.json')return state.current&&key?.trim()?json(res,200,manifest(state.current)):json(res,503,{error:'release_not_ready'});
 const match=/^\/android\/download\/([1-9][0-9]{0,9})$/.exec(path);
 if(!match)return json(res,404,{error:'not_found'});
 const release=state.releases.find(r=>r.versionCode===Number(match[1]));
 if(!release)return json(res,404,{error:'not_found'});
 try{const location=await resolveDownload(release,key);res.writeHead(302,{Location:location,'Cache-Control':'no-store'});res.end()}
 catch{return json(res,503,{error:'download_unavailable'})}
}).listen(9000,'0.0.0.0');
