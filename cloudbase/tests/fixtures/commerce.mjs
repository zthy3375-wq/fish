import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import jpeg from 'jpeg-js';
import {createCommerce} from '../../functions/community/commerce.mjs';
import {createCommunity,digest,hashPassword} from '../../functions/community/core.mjs';
import {createServer} from '../../functions/community/server.mjs';

const root=new URL('../../',import.meta.url);
const png=jpeg.encode({width:2,height:2,data:Buffer.alloc(16,190)},80).data.toString('base64');
function stamp(days){return new Date(Date.now()+days*86_400_000).toISOString();}
const range=(start=-.02,end=5)=>({startsAt:stamp(start),endsAt:stamp(end)});
const salt='isolated-commerce-fixture-policy-salt-12345';
const password='isolated-fixture-passphrase';

export async function fixture({pg=new PGlite()}={}){
 const calls=new Map();
 await pg.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role');
 for(const migration of ['community-schema.sql','commerce-schema.sql'])await pg.exec(await readFile(new URL(migration,root),'utf8'));
 const db=async(action,body,token)=>{
  calls.set(action,(calls.get(action)||0)+1);
  return (await pg.query('SELECT hyt_commerce.run($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),token])).rows[0].result;
 };
 const media=new Map();
 const storage={
  async put(id,bytes){media.set(id,bytes);},
  async urls(ids){return new Map(ids.filter(id=>media.has(id)).map(id=>[id,'data:image/jpeg;base64,'+media.get(id).toString('base64')]));},
 };
 const commerce=createCommerce({db,storage,salt,adminWebURL:'https://workbench.example.invalid/'});
 const community=createCommunity({db:async(action,body,token)=>(await pg.query('SELECT public.hyt_community($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),token])).rows[0].result,registrationEnabled:true,rateSalt:salt});
 const users={};
 const hashed=await hashPassword(password);
 async function add(name,developer=false,role='member'){
  const id=randomUUID(),token=Buffer.from(id.replace(/-/g,'').repeat(2),'hex').toString('base64url');
  await pg.query(`INSERT INTO public.hyt_members(id,username,nickname,password_hash,recovery_hash,developer_since,role)
   VALUES($1,$2,$2,$3,'fixture',CASE WHEN $4 THEN now() ELSE NULL END,$5)`,[id,name,hashed,developer,role]);
  await pg.query("INSERT INTO public.hyt_sessions(hash,member_id,expires_at) VALUES($1,$2,now()+interval '1 day')",[digest(token),id]);
  return users[name]={id,token};
 }
 for(const name of ['owner','business','merchant','merchant2','merchant3','merchant4','student','student2','student3','moderator'])await add(name,name==='owner',name==='owner'||name==='moderator'?'moderator':'member');
 const server=createServer(community,{commerce,allowedOrigins:['http://localhost:4173','http://127.0.0.1:4173']});
 server.listen(0,'127.0.0.1');await once(server,'listening');
 const base='http://127.0.0.1:'+server.address().port+'/hyt-community/v1/';
 async function call(action,body={},user,peer){
  const path=action.startsWith('community:')?action.slice(10):'commerce.'+action;
  const response=await fetch(base+path,{
   method:'POST',headers:{'Content-Type':'application/json',...(user?{Authorization:'Bearer '+users[user].token}:{}),...(peer?{'X-Real-IP':peer}:{})},
   body:JSON.stringify(body),
  });
  return {status:response.status,...await response.json()};
 }
 async function okay(action,body,user){
  const result=await call(action,body,user);assert.equal(result.status,200,action+': '+JSON.stringify(result));return result;
 }
 async function image(user,purpose){return (await okay('media.upload',{purpose,data:png},user)).id;}
 async function enroll(user,category='food'){
  const imageId=await image(user,'shop'),qualificationImage=await image(user,'qualification');
  const draft={name:'隔离门店 '+user,category,description:'可用夹具介绍',hours:'10:00-19:00',phone:'13100000000',address:'东校区测试地址',
   latitude:36.6,longitude:114.4,legalName:'测试主体 '+user,businessId:'000000000001',legalAddress:'封闭测试地址',legalPhone:'13200000000',
   qualification:'隔离数据库资质说明',images:[imageId],qualificationImage};
  const shop=(await okay('merchant.apply',draft,user)).id;
  await okay('admin.shop',{id:shop,revision:1,decision:'approved',reason:'核验通过'},'owner');
  return {shop,draft};
 }
 async function submitAd(user){
  const id=(await okay('merchant.ad',{id:randomUUID(),title:'商家福利',subtitle:'到店可用',image:await image(user,'ad')},user)).id;
  await okay('admin.ad',{id,decision:'approved',reason:'素材经过核对'},'owner');
  return id;
 }
 return {pg,server,base,calls,users,call,okay,image,enroll,submitAd,password,close:async()=>{server.close();await once(server,'close');await pg.close();}};
}

