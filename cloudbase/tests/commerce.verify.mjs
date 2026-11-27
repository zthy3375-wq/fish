import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {PGlite} from '@electric-sql/pglite';
import jpeg from 'jpeg-js';
import {createCommerce} from '../functions/community/commerce.mjs';
import {createCommunity,digest,hashPassword} from '../functions/community/core.mjs';
import {createServer} from '../functions/community/server.mjs';

const root=new URL('../',import.meta.url);
const png=jpeg.encode({width:2,height:2,data:Buffer.alloc(16,190)},80).data.toString('base64');
function stamp(days){return new Date(Date.now()+days*86_400_000).toISOString();}
const range=(start=-.02,end=5)=>({startsAt:stamp(start),endsAt:stamp(end)});
const settings={adsEnabled:true,iosAdsEnabled:false,reason:'隔离广告测试'};
const salt='isolated-commerce-fixture-policy-salt-12345';
const password='isolated-fixture-passphrase';

export async function fixture(){
 const pg=new PGlite();
 await pg.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role');
 for(const migration of ['community-schema.sql','commerce-schema.sql'])await pg.exec(await readFile(new URL(migration,root),'utf8'));
 const db=async(action,body,token)=>(await pg.query('SELECT hyt_commerce.run($1,$2::jsonb,$3) AS result',[action,JSON.stringify(body),token])).rows[0].result;
 const media=new Map();
 const storage={
  async put(id,bytes){media.set(id,bytes);},
  async urls(ids){return new Map(ids.filter(id=>media.has(id)).map(id=>[id,'https://example.invalid/'+id]));},
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
  const path=action==='login'?action:'commerce.'+action;
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
 return {pg,server,base,users,call,okay,image,enroll,submitAd,password,close:async()=>{server.close();await once(server,'close');await pg.close();}};
}

test('隔离数据库与真实 HTTP：资质、广告、授权、核销和隐私',async()=>{
 const f=await fixture();
 const {call,okay,users,pg}=f;
 try{
  await assert.rejects(pg.exec('SET ROLE anon; SELECT * FROM hyt_commerce.shops'),/permission denied/);
  await pg.exec('RESET ROLE');
  assert.deepEqual((await okay('catalog')).items,[]);
  assert.equal((await call('admin.config',{},'moderator')).status,403);
  assert.equal((await call('merchant.stats',{},'moderator')).status,403);
  assert.equal((await call('merchant.redeem',{code:'123456789012'},'student')).status,403);
  await okay('admin.role',{id:users.business.id,enabled:true,reason:'商务测试授权'},'owner');
  assert.equal((await okay('access',{},'business')).role,'business');
  assert.equal((await okay('access',{},'business')).adminUrl,'https://workbench.example.invalid/');
  assert.equal((await okay('access',{},'student')).adminUrl,undefined);
  assert.equal((await call('admin.settings',settings,'business')).status,403);
  assert.equal((await call('admin.role',{id:users.moderator.id,enabled:true,reason:'无权授权'},'business')).status,403);
  assert.equal((await call('admin.plan',{plan:'preferred',name:'测试套餐',cents:1,categorySlot:true,bannerSlot:false,homeSlot:false,reports:true,reason:'无权改价'},'business')).status,403);
  const communityResult=await fetch(f.base+'admin.members',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+users.business.token},body:'{}'});
  assert.equal(communityResult.status,403);

  const {shop,draft}=await f.enroll('merchant');
  const s2=(await f.enroll('merchant2')).shop;
  const s3=(await f.enroll('merchant3')).shop;
  const s4=(await f.enroll('merchant4')).shop;
  const page=await okay('catalog',{category:'food',query:'merchant'});
  assert.equal(page.items.length,4);
  assert.ok(!JSON.stringify(page).includes(draft.legalPhone));
  assert.ok(!Object.keys(page.media).includes(draft.qualificationImage));
  const wrongMedia=await call('merchant.apply',{...draft,name:'跨商家图片'},'merchant2');
  assert.equal(wrongMedia.error,'invalid_image');
  await okay('merchant.apply',{...draft,name:'待审改名'},'merchant');
  assert.equal((await okay('shop',{shopId:shop})).shop.name,draft.name);
  const review=(await okay('admin.list',{section:'shops',filter:'pending'},'business')).items[0];
  assert.equal(review.draft.legalPhone,draft.legalPhone);
  assert.equal((await call('admin.shop',{id:shop,revision:1,decision:'approved',reason:'旧版审核'},'business')).error,'request_conflict');
  await okay('admin.shop',{id:shop,revision:review.revision,decision:'approved',reason:'改名通过审核'},'business');

  const offer=(await okay('merchant.offer',{id:randomUUID(),title:'学生优惠',terms:'到店使用',quota:1,...range()},'merchant')).id;
  assert.equal((await call('claim',{id:offer},'student')).error,'student_verification_required');
  for(const name of ['student','student2'])await okay('admin.student',{id:users[name].id,enabled:true,reason:'线下核验资格'},'business');
  const claims=await Promise.all([call('claim',{id:offer},'student'),call('claim',{id:offer},'student2')]);
  const winner=claims[0].status===200?'student':'student2';
  const loser=winner==='student'?'student2':'student';
  const won=claims.find(r=>r.status===200);
  assert.equal(claims.filter(r=>r.status===200).length,1);assert.equal(claims.find(r=>r.status!==200).error,'sold_out');
  assert.equal((await okay('claim',{id:offer},winner)).id,won.id);
  assert.equal((await call('coupon',{id:won.id},loser)).status,404);
  const c=(await okay('coupon',{id:won.id},winner)).coupon;
  assert.match(c.code,/^[0-9]{12}$/);
  assert.equal((await okay('wallet',{},winner)).items.length,1);
  assert.equal((await call('merchant.redeem',{code:c.code},'merchant2')).status,404);
  assert.equal((await call('merchant.offer.edit',{id:offer,title:'替换优惠',terms:'新条款',quota:2,...range()},'merchant')).status,409);
  await okay('merchant.offerstate',{id:offer,enabled:false},'merchant');
  const redemptions=await Promise.all([call('merchant.redeem',{code:'HYT1:'+c.code},'merchant'),call('merchant.redeem',{code:c.code},'merchant')]);
  assert.equal(redemptions.filter(r=>r.status===200).length,1);assert.equal(redemptions.find(r=>r.status!==200).error,'already_redeemed');
  assert.ok(!JSON.stringify(redemptions).includes(users[winner].id));
  assert.equal((await okay('coupon',{id:won.id},winner)).coupon.state,'used');
  assert.equal((await okay('coupon',{id:won.id},winner)).coupon.code,null);
  await okay('favorite',{shopId:shop,enabled:true},winner);
  assert.equal((await okay('shop.status',{shopId:shop},winner)).favorited,true);
  assert.equal((await okay('favorites',{},winner)).items[0].id,shop);

  const ad=await f.submitAd('merchant');
  const contractFields={shopId:shop,plan:'home',kind:'monthly',placements:['home','banner','category'],...range(-.05,20),reference:'隔离测试合同'};
  assert.equal((await call('admin.contract',{...contractFields,cents:1},'business')).error,'owner_price_required');
  const contract=(await okay('admin.contract',{id:randomUUID(),...contractFields},'business')).id;
  const competing=await Promise.all([s2,s3].map(shopId=>call('admin.contract',{...contractFields,shopId,placements:['category']},'business')));
  assert.equal(competing.filter(r=>r.status===200).length,1);
  assert.equal(competing.find(r=>r.status!==200).error,'inventory_full');
  await okay('admin.contract',{...contractFields,shopId:s4,placements:['home'],kind:'trial'},'business');
  assert.equal((await call('admin.contract',{...contractFields,shopId:s4,placements:['home'],kind:'trial'},'business')).error,'trial_used');
  const schedule=(await okay('admin.schedule',{id:randomUUID(),adId:ad,contractId:contract,placement:'home',...range()},'business')).id;
  await okay('admin.schedule',{adId:ad,contractId:contract,placement:'banner',...range()},'business');
  await okay('admin.schedule',{adId:ad,contractId:contract,placement:'category',...range()},'business');
  assert.equal((await call('admin.schedule',{adId:ad,contractId:contract,placement:'home',...range()},'business')).error,'schedule_conflict');
  assert.equal((await call('admin.schedule',{adId:ad,contractId:contract,placement:'home',...range(21,23)},'business')).error,'invalid_period');
  assert.equal((await okay('home')).ads.length,0);
  await okay('admin.settings',settings,'owner');
  assert.equal((await okay('home')).ads.length,0);
  const receipt={id:randomUUID(),contractId:contract,cents:19900,reference:'隔离收据'};
  await okay('admin.receipt',receipt,'business');await okay('admin.receipt',receipt,'business');
  assert.equal((await okay('home')).ads[0].id,ad);
  assert.equal((await okay('home',{platform:'ios'})).ads.length,0);
  await okay('admin.settings',{...settings,iosAdsEnabled:true},'owner');
  assert.equal((await okay('home',{platform:'ios'})).ads[0].id,ad);
  assert.equal((await okay('catalog',{category:'food'})).ads[0].placement,'category:food');
  assert.equal((await okay('catalog')).ads[0].placement,'banner');
  assert.equal((await okay('catalog',{query:'隔离'})).ads.length,0);
  await okay('admin.schedule.state',{id:schedule,decision:'paused',reason:'测试暂停'},'business');
  assert.equal((await okay('home')).ads.length,0);
  await okay('admin.schedule.state',{id:schedule,decision:'active',reason:'测试恢复'},'business');

  const events=[{id:ad,kind:'impression'},{id:shop,kind:'visit'}];
  await okay('metrics',{events},winner);
  const initialSession=users[winner].token;
  users[winner].token=Buffer.from(randomUUID().replace(/-/g,'').repeat(2),'hex').toString('base64url');
  await pg.query("INSERT INTO public.hyt_sessions(hash,member_id,expires_at) VALUES($1,$2,now()+interval '1 day')",[digest(users[winner].token),users[winner].id]);
  await okay('metrics',{events},winner);
  const stats=(await okay('merchant.stats',{},'merchant')).days;
  assert.deepEqual(Object.fromEntries(stats.map(x=>[x.kind,x.total])),{claim:1,impression:1,redeem:1,visit:1});
  assert.ok(!JSON.stringify(stats).includes(initialSession));
  await okay('report',{shopId:shop,id:ad,reason:'匿名举报测试'});
  const report=(await okay('admin.list',{section:'reports'},'business')).items[0];
  assert.equal(report.report_key,undefined);
  await okay('admin.report',{id:report.id,reason:'已查证整改'},'business');
  await okay('admin.ad',{id:ad,decision:'removed',reason:'违规下架测试'},'business');
  assert.equal((await okay('home')).ads.length,0);
  await okay('admin.settings',{...settings,adsEnabled:false},'owner');
  await okay('admin.cancel',{id:contract,reason:'释放库存'},'business');
  const data=await okay('admin.list',{section:'contracts',shopId:shop},'business');
  assert.equal(data.items[0].paid,19900);
  assert.equal(data.items[0].receipts.length,1);
  await pg.exec('SELECT hyt_commerce.prune_private()');
 }finally{await f.close();}
});
