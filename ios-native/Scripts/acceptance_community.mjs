// Loopback-only CI service. Exercise the repository's real RPC, schema and password/session code.
import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {createCommunity} from '../../cloudbase/functions/community/core.mjs';
const db=new PGlite();
await db.exec(await readFile(new URL('../../cloudbase/community-schema.sql',import.meta.url),'utf8'));
const api=createCommunity({registrationEnabled:true,db:async(a,b,t)=>(await db.query('select hyt_community($1,$2,$3) as r',[a,b,t])).rows[0].r});
const server=http.createServer(async(req,res)=>{
  res.setHeader('Content-Type','application/json');
  try{
    const path=new URL(req.url,'http://localhost').pathname;
    if(path==='/ready'){res.end(JSON.stringify({scope:'isolated-ios-acceptance'}));return}
    if(!path.startsWith('/v1/')){res.writeHead(404).end();return}
    const action=path.slice(4);
    if(action==='config' && req.method==='GET'){res.end(JSON.stringify(api.config()));return}
    if(req.method!=='POST'){res.writeHead(405).end();return}
    let data='';
    for await(const chunk of req){data+=chunk;if(data.length>30000){res.writeHead(413).end();return}}
    const token=(req.headers.authorization??'').replace(/^Bearer /,'');
    const result=await api.execute(action,JSON.parse(data||'{}'),token,'ios-test');
    res.writeHead(result.status??200).end(JSON.stringify(result));
  }catch(e){res.writeHead(e.status??500).end(JSON.stringify({error:e.code??'internal'}))}
});
server.listen(18642,'127.0.0.1');
