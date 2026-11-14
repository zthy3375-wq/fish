import {randomBytes,createHash,createHmac,scrypt,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';

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
function username(value){const v=text(value,4,24).toLowerCase();if(!/^[a-z][a-z0-9_]{3,23}$/.test(v))fail('invalid_username');return v;}
function time(value){if(typeof value!=='string'||value.length>40||!Number.isFinite(Date.parse(value)))fail();return value;}
export async function hashPassword(value){const salt=randomBytes(16).toString('hex');const key=await deriveBounded(value,salt);return `scrypt-v1$${salt}$${Buffer.from(key).toString('hex')}`;}
export async function verifyPassword(value,stored){
 const parts=String(stored||'').split('$');const valid=parts.length===3&&parts[0]==='scrypt-v1'&&/^[a-f0-9]{32}$/.test(parts[1])&&/^[a-f0-9]{128}$/.test(parts[2]);
 const key=await deriveBounded(value,valid?parts[1]:'00000000000000000000000000000000');
 return valid&&timingSafeEqual(Buffer.from(key),Buffer.from(parts[2],'hex'));
}
export const clientActions=new Set(['register','login','recover','me','logout','profile.update','password.change','account.delete','posts.list','posts.get','posts.create','posts.delete','comments.create','comments.delete','reactions.set','reports.create','blocks.set','blocks.clear','admin.reports','admin.resolve']);
function sanitize(action,b){
 if(!b||typeof b!=='object'||Array.isArray(b))fail();
 if(['register','login','recover'].includes(action))return {username:username(b.username)};
 if(action==='profile.update')return {nickname:text(b.nickname,2,20)};
 if(action==='posts.list'){
  const scope=b.scope??'all';if(!['all','mine','saved'].includes(scope))fail();
  const out={scope,query:b.query?text(b.query,1,80):''};
  if(b.beforeTime!=null||b.beforeId!=null){out.beforeTime=time(b.beforeTime);out.beforeId=id(b.beforeId);}return out;
 }
 if(action==='posts.create')return {body:text(b.body,1,3000),anonymous:boolean(b.anonymous),requestId:id(b.requestId)};
 if(action==='admin.resolve'){
  if(!['remove','lock','ban','dismiss'].includes(b.decision))fail();
  return {reportId:id(b.reportId),decision:b.decision,reason:text(b.reason,2,300)};
 }
 if(['me','logout','password.change','account.delete','blocks.clear','admin.reports'].includes(action))return {};
 const out={postId:id(b.postId)};
 if(action==='posts.get'&&(b.afterTime!=null||b.afterId!=null)){out.afterTime=time(b.afterTime);out.afterId=id(b.afterId);}
 if(action==='comments.create')Object.assign(out,{body:text(b.body,1,1000),anonymous:boolean(b.anonymous),requestId:id(b.requestId),replyTo:id(b.replyTo,true)});
 if(['comments.delete','reports.create','blocks.set'].includes(action))out.commentId=id(b.commentId,action!=='comments.delete');
 if(action==='reports.create')out.reason=text(b.reason,2,300);
 if(action==='reactions.set'){if(!['like','save'].includes(b.kind))fail();Object.assign(out,{kind:b.kind,enabled:boolean(b.enabled)});}
 return out;
}
/** db is a server-only RPC adapter; client-controlled proof, ids and roles are discarded. */
export function createCommunity({db,registrationEnabled=false,inviteHash='',rateSalt=randomBytes(32).toString('hex')}){
 async function call(action,payload={},token=''){const r=await db(action,payload,token);if(!r||!Number.isInteger(r.status))throw Error('database_response');if(r.status>=400)fail(r.error||'temporarily_unavailable',r.status);return r;}
 const rate=(key,limit,seconds)=>call('rate',{key:createHmac('sha256',rateSalt).update(new Date().toISOString().slice(0,10)+':'+key).digest('hex'),limit,seconds});
 async function execute(action,input={},bearer='',peer='unknown'){
  if(!clientActions.has(action))fail('not_found',404);
  const b=sanitize(action,input);let tokenHash='';let sessionToken;let recoveryCode;
  if(['register','login','recover'].includes(action)){
   await rate('auth-ip:'+peer,30,900);await rate('auth-name:'+b.username,12,900);
   if(action==='register'){
    if(!registrationEnabled)fail('registration_closed',403);
    if(input.agreed!==true)fail('agreement_required');
    if(inviteHash&&digest(String(input.invite||''))!==inviteHash)fail('invite_invalid',403);
    b.nickname=text(input.nickname,2,20);b.passwordHash=await hashPassword(password(input.password));
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
   tokenHash=digest(bearer);await rate('session:'+tokenHash,180,60);
   if(['password.change','account.delete'].includes(action)){
    await rate('reauth:'+tokenHash,8,900);
    const s=await call('session',{},tokenHash);
    if(!await verifyPassword(password(input.password),s.passwordHash))fail('invalid_credentials',401);
    b.proof=s.passwordHash;
    if(action==='password.change'){b.passwordHash=await hashPassword(password(input.newPassword));recoveryCode=secret();b.recoveryHash=digest(recoveryCode);}
   }
  }
  const r=await call(action,b,tokenHash);
  // Cursor pages never include excess records or private credential fields.
  delete r.passwordHash;delete r.recoveryHash;
  if(r.posts){const rows=r.posts;r.posts=rows.slice(0,20);r.next=rows.length>20?{beforeTime:r.posts.at(-1).createdAt,beforeId:r.posts.at(-1).id}:null;}
  if(r.comments){const rows=r.comments;r.comments=rows.slice(0,50);r.next=rows.length>50?{afterTime:r.comments.at(-1).createdAt,afterId:r.comments.at(-1).id}:null;}
  if(sessionToken)r.sessionToken=sessionToken;
  if(recoveryCode)r.recoveryCode=recoveryCode;
  return r;
 }
 return {execute,config:()=>({registrationEnabled,requiresInvite:!!inviteHash,imagesEnabled:false})};
}
