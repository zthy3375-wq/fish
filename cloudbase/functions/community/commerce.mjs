import {createHmac, randomInt, randomUUID} from 'node:crypto';
import {CommunityError, digest} from './core.mjs';
import {cleanImage} from './media.mjs';

const publicActions=new Set(['home','catalog','shop','report']);
const adminSections=['shops','ads','contracts','schedule','reports','audit'];
const planIds=['basic','preferred','featured','home'];
const placements=['category','banner','home'];
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const bearerPattern=/^[A-Za-z0-9_-]{43}$/;
const codePattern=/^[0-9]{12}$/;
function invalid(){throw new CommunityError(400,'invalid_request');}
function text(v,min,max){
 if(typeof v!=='string')invalid();
 const s=v.trim().normalize('NFC');
 if(s.length<min||s.length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(s))invalid();
 return s;
}
function id(v,optional=false){if(optional&&v==null)return null;if(typeof v!=='string'||!uuid.test(v))invalid();return v.toLowerCase();}
function one(v,choices){if(!choices.includes(v))invalid();return v;}
function bool(v){return one(v,[true,false]);}
function int(v,min,max){if(!Number.isSafeInteger(v)||v<min||v>max)invalid();return v;}
function time(v){
 if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:\d{2})$/.test(v)||!Number.isFinite(Date.parse(v)))invalid();
 return new Date(v).toISOString();
}
function period(b,maxDays=366){
 const startsAt=time(b.startsAt),endsAt=time(b.endsAt),duration=Date.parse(endsAt)-Date.parse(startsAt);
 if(duration<=0||duration>maxDays*86_400_000)invalid();
 return {startsAt,endsAt};
}
function array(v,convert,max,min=0){
 if(!Array.isArray(v)||v.length>max||v.length<min)invalid();
 return v.map(x=>convert(x));
}
function category(v){const s=text(v,1,24);if(!/^[a-z]+$/.test(s))invalid();return s;}
function reason(v){return text(v,2,500);}
function requestId(v){return v==null?randomUUID():id(v);}
function coordinate(v,lo,hi){if(v==null)return null;if(typeof v!=='number'||!Number.isFinite(v)||v<lo||v>hi)invalid();return Math.round(v*1e6)/1e6;}
function phone(v){const s=text(v,6,32);if(!/^[+0-9 ()-]+$/.test(s)||s.replace(/\D/g,'').length<6)invalid();return s;}
function sanitize(action,b){
 if(!b||typeof b!=='object'||Array.isArray(b))invalid();
 const platform=one(b.platform??'android',['android','ios','web']);
 switch(action){
 case 'home':return {platform};
 case 'catalog':return {platform,category:b.category?category(b.category):'',query:text(b.query??'',0,64),next:id(b.next,true)};
 case 'shop':case 'shop.status':return {shopId:id(b.shopId)};
 case 'access': case 'merchant.read':case 'admin.config':case 'merchant.stats':return {};
 case 'wallet':case 'favorites':case 'merchant.ads':case 'merchant.offers':case 'merchant.contracts':return {next:id(b.next,true)};
 case 'admin.stats':return {shopId:id(b.shopId,true)};
 case 'coupon':case 'claim':return {id:id(b.id)};
 case 'favorite':return {shopId:id(b.shopId),enabled:bool(b.enabled)};
 case 'report':return {shopId:id(b.shopId),id:id(b.id,true),reason:reason(b.reason)};
 case 'merchant.apply':{
  const images=array(b.images,x=>id(x),4,1);
  if(new Set(images).size!==images.length)invalid();
  const latitude=coordinate(b.latitude,-90,90),longitude=coordinate(b.longitude,-180,180);
  if((latitude===null)!==(longitude===null))invalid();
  return {name:text(b.name,2,50),category:category(b.category),description:text(b.description,2,500),
   hours:text(b.hours,2,120),phone:phone(b.phone),address:text(b.address,2,200),latitude,longitude,images,
   legalName:text(b.legalName,2,120),businessId:text(b.businessId,6,32),legalAddress:text(b.legalAddress,2,200),
   legalPhone:phone(b.legalPhone),qualification:text(b.qualification,2,500),qualificationImage:id(b.qualificationImage)};
 }
 case 'merchant.offer':case 'merchant.offer.edit':return {id:requestId(b.id),title:text(b.title,2,64),terms:text(b.terms,2,500),quota:int(b.quota,1,10000),...period(b,180)};
 case 'merchant.offerstate':return {id:id(b.id),enabled:bool(b.enabled)};
 case 'merchant.ad':return {id:requestId(b.id),title:text(b.title,2,36),subtitle:text(b.subtitle,0,80),image:id(b.image)};
 case 'merchant.redeem':{
  const code=text(b.code,12,32).replace(/^HYT1:/,'').replace(/[ -]/g,'');
  if(!codePattern.test(code))invalid();
  return {code};
 }
 case 'admin.list':{
  const section=one(b.section,adminSections);
  const choices=section==='shops'?['pending','approved','rejected','suspended']:section==='ads'?['pending','approved','rejected','removed']:section==='reports'?['open','resolved']:[];
  return {section,filter:b.filter?one(b.filter,choices):null,shopId:id(b.shopId,true),next:id(b.next,true)};
 }
 case 'admin.role':case 'admin.student':return {id:id(b.id),enabled:bool(b.enabled),reason:reason(b.reason)};
 case 'admin.settings':return {adsEnabled:bool(b.adsEnabled),iosAdsEnabled:bool(b.iosAdsEnabled),reason:reason(b.reason)};
 case 'admin.plan':{
  const plan=one(b.plan,planIds),cents=int(b.cents,0,10_000_000);
  const entitlements={categorySlot:bool(b.categorySlot),bannerSlot:bool(b.bannerSlot),homeSlot:bool(b.homeSlot),reports:bool(b.reports)};
  if(plan==='basic'&&(cents!==0||Object.values(entitlements).some(Boolean)))invalid();
  return {plan,name:text(b.name,2,24),cents,...entitlements,reason:reason(b.reason)};
 }
 case 'admin.shop':return {id:id(b.id),revision:int(b.revision,1,1_000_000),decision:one(b.decision,['approved','rejected','suspended']),reason:reason(b.reason)};
 case 'admin.ad':return {id:id(b.id),decision:one(b.decision,['approved','rejected','removed']),reason:reason(b.reason)};
 case 'admin.contract':{
  const kind=one(b.kind,['monthly','trial','short']);
  const selected=array(b.placements,v=>one(v,placements),3);
  if(new Set(selected).size!==selected.length||kind==='trial'&&b.cents!=null)invalid();
  return {id:requestId(b.id),shopId:id(b.shopId),plan:one(b.plan,planIds),kind,placements:selected,
   ...(kind==='short'?period(b,30):{startsAt:time(b.startsAt)}),cents:b.cents==null?null:int(b.cents,0,10_000_000),
   attachment:id(b.attachment,true),renewedFrom:id(b.renewedFrom,true),reference:text(b.reference,2,200)};
 }
 case 'admin.receipt':{
  const cents=int(b.cents,-10_000_000,10_000_000);
  if(cents===0)invalid();
  return {id:requestId(b.id),shopId:id(b.contractId),cents,reference:text(b.reference,2,200)};
 }
 case 'admin.schedule':return {id:requestId(b.id),adId:id(b.adId),contractId:id(b.contractId),placement:one(b.placement,placements),...period(b)};
 case 'admin.schedule.state':return {id:id(b.id),decision:one(b.decision,['active','paused','removed']),reason:reason(b.reason)};
 case 'admin.cancel':case 'admin.report':return {id:id(b.id),reason:reason(b.reason)};
 case 'metrics':return {platform,events:array(b.events,x=>{
  if(!x||typeof x!=='object')invalid();
  return {id:id(x.id),kind:one(x.kind,['impression','visit'])};
 },12,1)};
 case 'media.upload':{
  const data=text(b.data,8,1_600_000);
  if(data.length%4!==0||!/^[A-Za-z0-9+/]+={0,2}$/.test(data))invalid();
  return {id:requestId(b.id),purpose:one(b.purpose,['shop','ad','qualification','contract']),data};
 }
 default:throw new CommunityError(404,'not_found');
 }
}

function mediaKeys(result,action){
 const keys=new Set();
 function shop(s){for(const image of s?.images??[])keys.add(image);}
 function review(s){
  shop(s); if(s?.qualificationImage)keys.add(s.qualificationImage);
 }
 if(result.shop?.draft)review(result.shop.draft);else shop(result.shop);
 for(const ad of result.ads??[])if(ad.image)keys.add(ad.image);
 for(const item of result.items??[]){
  if(action==='admin.list'&&item.draft)review(item.draft);
  if(item.attachment)keys.add(item.attachment);
  if(item.image)keys.add(item.image);
  shop(item);
 }
 return [...keys];
}

export function createCommerce({db,storage,salt,adminWebURL,now=Date.now}){
 const cache=new Map();
 const pending=new Map();
 let cacheEpoch=0;
 function clearCache(){cache.clear();cacheEpoch++;}
 async function execute(action,body,bearer,peer='unknown'){
  const clean=sanitize(action,body);
  const token=bearerPattern.test(bearer||'')?digest(bearer):'';
  if(!publicActions.has(action)&&!token)throw new CommunityError(401,'session_expired');
  if(action==='media.upload'){
   const {data,...image}=clean;
   let jpeg;try{jpeg=cleanImage(data);}catch(e){throw new CommunityError(e.status||400,e.code||'invalid_image');}
   const started=await db('media.begin',image,token);
   if(started.status!==200)return started;
   await storage.put(image.id,jpeg.bytes);
   return db('media.finish',image,token);
  }
  if(action==='metrics'||action==='report'){
   if(typeof salt!=='string'||salt.length<32)throw new CommunityError(503,'temporarily_unavailable');
   const day=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(now());
   if(action==='metrics')clean.dailyKey=createHmac('sha256',salt).update(day).digest('hex');
   else clean.reportKey=createHmac('sha256',salt).update(['report',day,peer].join(':')).digest('hex');
  }
  if(action==='claim'){
   for(let attempt=0;attempt<3;attempt++){
    const result=await db(action,{...clean,code:String(randomInt(1_000_000_000_000)).padStart(12,'0')},token);
    if(result.error!=='code_collision')return result;
   }
   throw new CommunityError(503,'temporarily_unavailable');
  }
  async function read(){
   const result=await db(action,clean,token);
   if(!result||typeof result.status!=='number')throw new CommunityError(503,'temporarily_unavailable');
   if(action==='access'&&['owner','business'].includes(result.role)&&adminWebURL){
    const url=URL.canParse(adminWebURL)?new URL(adminWebURL):null;
    if(url?.protocol==='https:'&&!url.username&&!url.password)result.adminUrl=url.href;
   }
   const ids=mediaKeys(result,action);
   if(ids.length){
    try{result.media=Object.fromEntries(await storage.urls(ids));}
    catch{result.media={};}
   }
   if(result.status===200&&['admin.settings','admin.shop','admin.ad','admin.cancel','admin.receipt','admin.schedule','admin.schedule.state','merchant.offer','merchant.offer.edit','merchant.offerstate'].includes(action))clearCache();
   return result;
  }
  const cached=action==='home'||(action==='catalog'&&!clean.next&&!clean.query)||action==='shop';
  if(!cached)return read();
  const key=action+':'+JSON.stringify(clean);
  const hit=cache.get(key);
  const start=now(),epoch=cacheEpoch;
  if(hit?.until>start)return hit.result;
  const inFlight=pending.get(key);
  if(inFlight?.epoch===epoch)return inFlight.promise;
  const promise=read().then(result=>{
   const hasAds=Array.isArray(result.ads)&&result.ads.length>0;
   const deadline=hasAds?Math.min(...result.ads.map(ad=>Date.parse(ad.endsAt))):Infinity;
   const until=Math.min(start+15_000,deadline);
   if(result.status===200&&epoch===cacheEpoch&&until>now()){
    cache.set(key,{result,until});
    if(cache.size>128)cache.delete(cache.keys().next().value);
   }
   return result;
  }).finally(()=>{if(pending.get(key)?.promise===promise)pending.delete(key);});
  if(pending.size<128)pending.set(key,{epoch,promise});
  return promise;
 }
 return {execute};
}
