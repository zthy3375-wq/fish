import {contestActions,sanitizeContest} from './contests.mjs';
import {cleanImage,MAX_IMAGE_BYTES} from './media.mjs';
import {randomBytes,createHash,createHmac,scrypt,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';

const categories=['daily','help','study','buddies','entertainment','treehole'];
const sections=['daily','entertainment','buddies','treehole'];
const interestsByCategory={study:['graduate'],entertainment:['reading','fitness','games','anime','film','music','photo','sports']};
const interests=Object.values(interestsByCategory).flat();
const boardTopics=new Set(['graduate','reading','fitness']);
const derive=promisify(scrypt);
let activeKDF=0;
async function deriveBounded(value,salt){if(activeKDF>=2)throw new CommunityError(429,'too_many_requests');activeKDF++;try{return await derive(value,salt,64,{N:32768,r:8,p:1,maxmem:64*1024*1024});}finally{activeKDF--;}}
export const digest=value=>createHash('sha256').update(value).digest('hex');
const secret=()=>randomBytes(32).toString('base64url');
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export class CommunityError extends Error { constructor(status,code){super(code);this.status=status;this.code=code;} }
function fail(code='invalid_request',status=400){throw new CommunityError(status,code);}
function text(value,min,max){if(typeof value!=='string')fail();const clean=value.trim().normalize('NFC');if(clean.length<min||clean.length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(clean))fail();return clean;}
function password(value){if(typeof value!=='string'||value.length<10||value.length>128)fail('password_length');return value;}
function id(value,optional=false){if(optional&&(value===null||value===undefined))return null;if(typeof value!=='string'||!uuid.test(value))fail();return value;}
function boolean(value){if(typeof value!=='boolean')fail();return value;}
function username(value){
 if(typeof value!=='string')fail('invalid_username');
 const name=value.trim().normalize('NFC').toLowerCase().normalize('NFC');
 // Joined emoji are visible identifiers; reject standalone formatting and control characters.
 const visible=name.replace(/[\u200c\u200d]/gu,'');
 if(!/[\p{L}\p{N}\p{P}\p{S}]/u.test(visible)||[...name].length>32||/[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/u.test(visible))fail('invalid_username');
 return name;
}
function time(value){if(typeof value!=='string'||value.length>40||!Number.isFinite(Date.parse(value)))fail();return value;}
export async function hashPassword(value){const salt=randomBytes(16).toString('hex');const key=await deriveBounded(value,salt);return `scrypt-v1$${salt}$${Buffer.from(key).toString('hex')}`;}
export async function verifyPassword(value,stored){
 const parts=String(stored||'').split('$');const valid=parts.length===3&&parts[0]==='scrypt-v1'&&/^[a-f0-9]{32}$/.test(parts[1])&&/^[a-f0-9]{128}$/.test(parts[2]);
 const key=await deriveBounded(value,valid?parts[1]:'00000000000000000000000000000000');
 return valid&&timingSafeEqual(Buffer.from(key),Buffer.from(parts[2],'hex'));
}
export const clientActions=new Set(['honors.hall','honors.wear','honors.manage','honors.change','honors.ack','register','login','recover','me','logout','profile.update','password.change','account.delete','posts.list','posts.get','posts.create','posts.delete','comments.create','comments.delete','reactions.set','reports.create','blocks.set','blocks.clear','admin.reports','admin.resolve','admin.context','admin.content','admin.history','admin.action','media.upload','media.discard','media.url','comments.replies','comments.like','comments.context','threads.watch','notifications.list','notifications.unread','notifications.read','profile.get','avatar.set','responses.set','follows.set','follows.list','polls.vote','buddies.join','buddies.close','buddies.members','follows.stats','followers.list','members.block','messages.open','messages.inbox','messages.unread','messages.list','messages.send','messages.read']);
contestActions.forEach(action=>clientActions.add(action));
const awardCodes=['arrival','firstpost','hello','liked','sprout','neighbor','popular','collector','month','year'];
const honorKinds=['seed','creator','contributor'];
const permissions=['content','reports','users','recommend'];
function oneOf(value,choices){if(!choices.includes(value))fail();return value;}
function selection(values,choices,limit){
 if(!Array.isArray(values)||values.length>limit||new Set(values).size!==values.length)fail();
 return values.map(value=>oneOf(value,choices));
}
function sanitize(action,b){
 if(!b||typeof b!=='object'||Array.isArray(b))fail();
 if(contestActions.includes(action))return sanitizeContest(action,b,{text,id,boolean,time,oneOf,fail});
 if(['register','login','recover'].includes(action))return {username:username(b.username)};
 if(action==='honors.hall')return {memberId:id(b.memberId,true)};
 if(action==='honors.ack')return {codes:selection(b.codes,awardCodes,awardCodes.length)};
 if(action==='honors.wear')return {honor:b.honor===null?null:oneOf(b.honor,honorKinds),showcase:selection(b.showcase,awardCodes,3)};
 if(action==='honors.manage')return {query:text(b.query??'',0,64)};
 if(action==='honors.change'){
  const operation=oneOf(b.operation,['appoint','dismiss','grant','revoke','recommend','decline','mute','unmute']);
  return {memberId:id(b.memberId),requestId:id(b.requestId),reason:text(b.reason,2,200),operation,
   ...(operation==='appoint'?{caps:selection(b.caps,permissions,4).sort()}:{}),
   ...(['grant','revoke'].includes(operation)?{kind:oneOf(b.kind,honorKinds)}:{})};
 }
 if(action==='profile.update')return {nickname:text(b.nickname,2,20),...(b.bio!==undefined?{bio:text(b.bio,0,120)}:{})};
 if(action==='avatar.set'){if(b.imageId===undefined)fail();return {imageId:id(b.imageId,true)};}
 if(['messages.open','members.block'].includes(action))return {memberId:id(b.memberId)};
 if(['messages.unread','follows.stats'].includes(action))return {};
 if(action.startsWith('messages.')){
  const seq=v=>{if(typeof v!=='string'||! /^[1-9][0-9]{0,17}$/.test(v))fail();return v;};
  if(action==='messages.inbox')return b.beforeSeq!=null?{beforeSeq:seq(b.beforeSeq),beforeId:id(b.beforeId)}:{};
  const out={conversationId:id(b.conversationId)};
  if(action==='messages.send')return {...out,body:text(b.body,1,1000),requestId:id(b.requestId)};
  if(action==='messages.read')return {...out,throughSeq:seq(b.throughSeq),withUnread:b.withUnread===true};
  if(b.beforeSeq!=null&&b.afterSeq!=null)fail();
  return {...out,...(b.beforeSeq!=null?{beforeSeq:seq(b.beforeSeq)}:{}),...(b.afterSeq!=null?{afterSeq:seq(b.afterSeq)}:{})};
 }
 if(action==='profile.get')return {memberId:id(b.memberId)};
 if(action==='follows.set')return {memberId:id(b.memberId),enabled:boolean(b.enabled)};
 if(['follows.list','followers.list'].includes(action))return b.beforeTime!=null||b.beforeId!=null?{beforeTime:time(b.beforeTime),beforeId:id(b.beforeId)}:{};
 if(action==='notifications.unread')return {};
 if(action==='notifications.read'){
  if(!Array.isArray(b.ids)||b.ids.length<1||b.ids.length>50)fail();
  return {ids:[...new Set(b.ids.map(x=>id(x)))]};
 }
 if(action==='notifications.list'){
  const filter=b.filter??'all';if(!['all','replies','likes'].includes(filter))fail();
  return {filter,...(b.beforeTime!=null||b.beforeId!=null?{beforeTime:time(b.beforeTime),beforeId:id(b.beforeId)}:{})};
 }
 if(action==='posts.list'){
  const scope=b.scope??'all';if(!['all','mine','saved','participated','watching','author','following','joined'].includes(scope))fail();
  const category=b.category??'all',sort=b.sort??'latest';if(!['all',...categories].includes(category)||!['latest','hot'].includes(sort))fail();
  const section=b.section??'all',interest=b.interest??'';if(!['all',...sections].includes(section)||(interest!==''&&!interests.includes(interest)))fail();
  if(interest==='graduate'?(section!=='daily'||category!=='study'):interest&&section!=='entertainment')fail();
  const out={scope,category,section,interest,sort,query:b.query?text(b.query,1,80):'',...(scope==='author'?{memberId:id(b.memberId)}:{})};
  if(b.snapshotTime!=null)out.snapshotTime=time(b.snapshotTime);
  if(b.beforeRank!=null){if(typeof b.beforeRank!=='string'||!/^\d{1,12}(\.\d{1,8})?$/.test(b.beforeRank))fail();out.beforeRank=b.beforeRank;}
  if(b.beforeTime!=null||b.beforeId!=null){out.beforeTime=time(b.beforeTime);out.beforeId=id(b.beforeId);}return out;
 }
 if(action==='media.upload'){
  if(typeof b.data!=='string'||b.data.length>Math.ceil(MAX_IMAGE_BYTES/3)*4||b.data.length%4!==0||!/^[A-Za-z0-9+/]+={0,2}$/.test(b.data))fail('invalid_image');
  const purpose=b.purpose??'post';if(!['post','avatar','comment'].includes(purpose))fail();
  return {requestId:id(b.requestId),digest:digest(b.data),purpose};
 }
 if(action==='media.discard')return {imageId:id(b.imageId)};
 if(action==='posts.create'){
  const images=b.images??[];if(!Array.isArray(images)||images.length>9||new Set(images).size!==images.length)fail();images.forEach(x=>id(x));
  const category=b.category??'daily';if(!categories.includes(category))fail();
  const interest=b.interest??'';if(typeof interest!=='string'||interest&&!interestsByCategory[category]?.includes(interest))fail();
  const anonymous=boolean(b.anonymous);if(category==='treehole'&&!anonymous)fail();
  let poll=null;
  if(b.poll!=null){const d=b.poll;if(typeof d!=='object'||Array.isArray(d)||!Array.isArray(d.options)||d.options.length<2||d.options.length>6||![24,72,168].includes(d.durationHours))fail();
   const options=d.options.map(x=>text(x,1,40));if(new Set(options.map(x=>x.toLowerCase())).size!==options.length)fail();poll={question:text(d.question,1,80),options,durationHours:d.durationHours};}
  let buddy=null;
  if(b.buddy!=null){const d=b.buddy;if(typeof d!=='object'||Array.isArray(d)||category!=='buddies'||poll||!Number.isInteger(d.capacity)||d.capacity<1||d.capacity>20)fail();
   if(typeof d.startsAt!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/.test(d.startsAt)||!Number.isFinite(Date.parse(d.startsAt)))fail();
   buddy={location:text(d.location,1,60),startsAt:new Date(d.startsAt).toISOString(),capacity:d.capacity};}
  return {buddy,poll,body:text(b.body,buddy?1:images.length||poll?0:1,3000),title:text(b.title??'',0,40),category,interest,images,anonymous,requestId:id(b.requestId)};
 }
 if(['admin.content','admin.history'].includes(action))return {...(action==='admin.content'?{query:b.query?text(b.query,1,80):''}:{}),...(b.beforeTime!=null||b.beforeId!=null?{beforeTime:time(b.beforeTime),beforeId:id(b.beforeId)}:{})};
 if(action==='admin.context')return {postId:id(b.postId),commentId:id(b.commentId,true)};
 if(action==='admin.action'){
  if(!['remove','lock','unlock','ban','dismiss'].includes(b.decision))fail();
  return {postId:id(b.postId),commentId:id(b.commentId,true),reportId:id(b.reportId,true),requestId:id(b.requestId),decision:b.decision,reason:text(b.reason,2,300)};
 }
 if(action==='admin.resolve'){
  if(!['remove','lock','ban','dismiss'].includes(b.decision))fail();
  return {reportId:id(b.reportId),decision:b.decision,reason:text(b.reason,2,300)};
 }
 if(['me','logout','password.change','account.delete','blocks.clear','admin.reports'].includes(action))return {};
 const out={postId:id(b.postId)};
 if(action==='buddies.join')out.enabled=boolean(b.enabled);
 if(action==='buddies.close')out.closed=boolean(b.closed);
 if(action==='polls.vote'){if(b.optionId!==null&&(typeof b.optionId!=='string'||! /^[0-5]$/.test(b.optionId)))fail();out.optionId=b.optionId;}
 if(action==='responses.set'){if(b.kind!==null&&!['same','hug','useful','joy'].includes(b.kind))fail();out.kind=b.kind;}
 if(action==='threads.watch')out.enabled=boolean(b.enabled);
 if(action==='comments.context')out.commentId=id(b.commentId);
 if(action==='posts.get')out.threaded=b.threaded===true;
 if(action==='media.url')out.imageId=id(b.imageId);
 if(action==='comments.replies')out.rootId=id(b.rootId);
 if(['posts.get','comments.replies'].includes(action)&&(b.afterTime!=null||b.afterId!=null)){out.afterTime=time(b.afterTime);out.afterId=id(b.afterId);}
 if(action==='comments.like')Object.assign(out,{commentId:id(b.commentId),enabled:boolean(b.enabled)});
 if(action==='comments.create'){const images=b.images??[];if(!Array.isArray(images)||images.length>3||new Set(images).size!==images.length)fail();images.forEach(x=>id(x));Object.assign(out,{images,body:text(b.body,images.length?0:1,1000),anonymous:boolean(b.anonymous),requestId:id(b.requestId),replyTo:id(b.replyTo,true)});}
 if(['comments.delete','reports.create','blocks.set'].includes(action))out.commentId=id(b.commentId,action!=='comments.delete');
 if(action==='reports.create')out.reason=text(b.reason,2,300);
 if(action==='reactions.set'){if(!['like','save'].includes(b.kind))fail();Object.assign(out,{kind:b.kind,enabled:boolean(b.enabled)});}
 return out;
}
/** db is a server-only RPC adapter; client-controlled proof, ids and roles are discarded. */
export function createCommunity({db,storage=null,registrationEnabled=false,boardsEnabled=true,contestsEnabled=false,rateSalt=randomBytes(32).toString('hex'),now=Date.now,scheduler=null}){
 async function call(action,payload={},token=''){const r=await db(action,payload,token);if(!r||!Number.isInteger(r.status))throw Error('database_response');if(r.status>=400)fail(r.error||'temporarily_unavailable',r.status);return r;}
 const rate=(key,limit,seconds)=>call('rate',{key:createHmac('sha256',rateSalt).update(new Date().toISOString().slice(0,10)+':'+key).digest('hex'),limit,seconds});
 let nextUploadCleanup=-Infinity,uploadCleanupPending=null;
 async function cleanupMedia(){const stale=await call('media.cleanup');for(const image of stale.images||[]){await storage.remove(image.key);await call('media.purge',{imageId:image.id});}return (stale.images||[]).length;}
 async function uploadCleanup(){
  if(uploadCleanupPending||now()<nextUploadCleanup)return;
  nextUploadCleanup=now()+600000;
  uploadCleanupPending=cleanupMedia().then(count=>{if(count>=20)nextUploadCleanup=now();}).catch(()=>{nextUploadCleanup=now()+60000;console.warn('Community image cleanup will retry');}).finally(()=>{uploadCleanupPending=null;});
  await uploadCleanupPending;
 }
 async function execute(action,input={},bearer='',peer='unknown'){
  if(!clientActions.has(action))fail('not_found',404);
  if(contestActions.includes(action)&&!contestsEnabled)fail('contests_unavailable',503);
  const b=sanitize(action,input);if(!boardsEnabled&&boardTopics.has(b.interest))fail('invalid_request');let tokenHash='';let sessionToken;let recoveryCode;
  if(['register','login','recover'].includes(action)){
   await rate('auth-ip:'+peer,30,900);await rate('auth-name:'+b.username,12,900);
   if(action==='register'){
    if(!registrationEnabled)fail('registration_closed',403);
    if(input.agreed!==true)fail('agreement_required');
    b.nickname=input.nickname==null?'同学'+randomBytes(3).toString('hex'):text(input.nickname,2,20);b.passwordHash=await hashPassword(password(input.password));
    recoveryCode=secret();b.recoveryHash=digest(recoveryCode);
   }else{
    // Uniform responses and the same password KDF for unknown/incorrect usernames.
    const found=await db('credentials',b,'');
    if(action==='login'){
     if(!await verifyPassword(password(input.password),found?.passwordHash))fail('invalid_credentials',401);
     b.proof=found.passwordHash;
    }else{
     const supplied=text(input.recoveryCode,40,64);const expected=found?.recoveryHash||'0'.repeat(64);
     if(!timingSafeEqual(Buffer.from(digest(supplied)),Buffer.from(expected)))fail('invalid_credentials',401);
     b.proof=expected;b.passwordHash=await hashPassword(password(input.password));recoveryCode=secret();b.recoveryHash=digest(recoveryCode);
    }
    b.id=found.id;
   }
   sessionToken=secret();tokenHash=digest(sessionToken);
  }else{
   if(typeof bearer!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(bearer))fail('session_expired',401);
   tokenHash=digest(bearer);
   if(['password.change','account.delete'].includes(action)){
    const s=await call('session',{},tokenHash);
    await rate('reauth:'+s.user.id,8,900);
    if(!await verifyPassword(password(input.password),s.passwordHash))fail('invalid_credentials',401);
    b.proof=s.passwordHash;
    if(action==='password.change'){b.passwordHash=await hashPassword(password(input.newPassword));recoveryCode=secret();b.recoveryHash=digest(recoveryCode);}
   }
  }
  if(contestActions.includes(action))await rate('contest:'+tokenHash,120,60);
  if(scheduler&&((action==='contests.save')||(action==='contests.manage'&&['publish','resume','restore'].includes(b.operation))||(action==='contests.review'&&['entry','vote'].includes(b.kind)))){
   const plan=await call('contests.schedule',{contestId:b.contestId},tokenHash);
   const contest=plan.contest||(action==='contests.save'&&b.publish?{...b,id:b.contestId,published:true}:null);
   const needed=action==='contests.save'?(b.publish||contest?.published):
    action==='contests.manage'?['publish','resume','restore'].includes(b.operation):contest?.published;
   const visible=(!contest?.visibility||contest.visibility==='visible');
   const lifecycleAllowed=action==='contests.manage'&&b.operation==='restore'?!visible:visible;
   if(needed&&contest&&lifecycleAllowed){
    try{await scheduler.ensure(action==='contests.save'?{...contest,awardAt:b.awardAt,autoPublish:b.autoPublish}:contest)}
    catch{fail('contest_scheduler_unavailable',503)}
   }
  }
  let r;
  if(action==='media.upload'){
   if(!storage)fail('images_unavailable',503);
   const reserved=await call('media.reserve',b,tokenHash);
   if(reserved.ready)r={status:200,image:reserved.image};
   else {
    let encoded;try{encoded=cleanImage(input.data,b.purpose==='avatar');}catch(e){fail(e.code||'invalid_image',e.status||400);}
    await storage.put(reserved.image.key,encoded.bytes);
    r=await call('media.commit',{imageId:reserved.image.id,width:encoded.width,height:encoded.height,bytes:encoded.bytes.length},tokenHash);
   }
  }else if(action==='me'&&input.entry===true){
   r=await call('posts.list',{...sanitize('posts.list',{}),entry:true},tokenHash);
   if(!r.user)r=await call('me',{},tokenHash);
   else r.config=config();
  }else{
   if((action==='notifications.unread'||action==='notifications.list')&&input.withMessages===true)b.withMessages=true;
   r=await call(action,b,tokenHash);
  }
  if(action==='me'&&!r.config)r.config=config();
  // Cursor pages never include excess records or private credential fields.
  delete r.passwordHash;delete r.recoveryHash;
  if(r.posts){const rows=r.posts;r.posts=rows.slice(0,20);r.next=rows.length>20?{beforeTime:r.posts.at(-1).createdAt,beforeId:r.posts.at(-1).id,beforeRank:r.posts.at(-1).rank,snapshotTime:r.snapshotTime}:null;}
  if(r.comments){const rows=r.comments,limit=action==='posts.get'&&b.threaded?20:50;r.comments=rows.slice(0,limit);r.next=rows.length>limit?{afterTime:r.comments.at(-1).createdAt,afterId:r.comments.at(-1).id}:null;}
  if(r.notifications){const rows=r.notifications;r.notifications=rows.slice(0,30);r.next=rows.length>30?{beforeTime:r.notifications.at(-1).createdAt,beforeId:r.notifications.at(-1).id}:null;}
  if(r.following){const rows=r.following;r.following=rows.slice(0,20);r.next=rows.length>20?{beforeTime:r.following.at(-1).followedAt,beforeId:r.following.at(-1).id}:null;}
  if(r.followers){const rows=r.followers;r.followers=rows.slice(0,20);r.next=rows.length>20?{beforeTime:r.followers.at(-1).followedAt,beforeId:r.followers.at(-1).id}:null;}
  if(r.conversations){const rows=r.conversations;r.conversations=rows.slice(0,20);r.next=rows.length>20?{beforeSeq:r.conversations.at(-1).lastSeq,beforeId:r.conversations.at(-1).id}:null;}
  if(r.messages){const rows=r.messages;r.messages=rows.slice(0,30);r.next=rows.length>30?{[b.afterSeq?'afterSeq':'beforeSeq']:r.messages.at(-1).seq}:null;if(!b.afterSeq)r.messages.reverse();}
  // Internal object keys never leave this service. Signed links expire after ten minutes.
  const images=[];
  function collect(value){if(!value||typeof value!=='object')return;if(typeof value.key==='string'&&typeof value.id==='string'&&typeof value.width==='number')images.push(value);for(const child of Object.values(value))collect(child);}
  collect(r);
  const keys=[...new Set(images.map(i=>i.key))];let urls=new Map();
  if(storage&&keys.length){try{urls=storage.urls?await storage.urls(keys,{fresh:action==='media.url'||action==='contests.image'}):new Map(await Promise.all(keys.map(async key=>[key,await storage.url(key)])));}catch{}}
  for(const image of images){image.url=urls.get(image.key)||null;delete image.key;}
  if(storage&&['posts.delete','comments.delete','account.delete','admin.resolve','admin.action','media.discard','media.upload','avatar.set'].includes(action)){
   try {if(action==='media.upload')await uploadCleanup();else await cleanupMedia();}catch{console.warn('Community image cleanup will retry');}
  }
  // Older clients can browse topic posts through their parent category without unknown labels.
  if(input.boardTopics!==true){
   for(const post of [...(r.posts||[]),...(r.post?[r.post]:[])]){
    if(boardTopics.has(post.interest))post.interest='';
   }
  }
  // Older clients still render an eight-slot cabinet. New codes remain intact in storage.
  if(input.timeAwards!==true){
   const visible=code=>code!=='month'&&code!=='year';
   for(const item of [r.hall,r.user,r.profile,r.updatedIdentity])if(item?.showcase)item.showcase=item.showcase.filter(visible);
   if(r.unlocks)r.unlocks=r.unlocks.filter(visible);
   if(r.hall){
    delete r.hall.awards.month;delete r.hall.awards.year;
    if(r.hall.progress){delete r.hall.progress.days;r.hall.total=Object.keys(r.hall.awards).length;}
   }
  }
  if(sessionToken)r.sessionToken=sessionToken;
  if(recoveryCode)r.recoveryCode=recoveryCode;
  return r;
 }
 function config(){return {contestsEnabled,registrationEnabled,requiresInvite:false,simpleRegistration:true,combinedUnread:true,imagesEnabled:!!storage,categories,sections,interests,schema:contestsEnabled?15:12,legacyTimeProjection:true,timeAwards:true,honorsEnabled:true,moderationEnabled:true,boardsEnabled,responseKinds:['useful','joy','hug'],messagesEnabled:true,socialEnabled:true,buddiesEnabled:true,pollsEnabled:true,commentImagesEnabled:!!storage,followingEnabled:true,discoveryEnabled:true,engagementEnabled:true,avatarsEnabled:!!storage,responsesEnabled:true};}
 return {execute,config};
}
