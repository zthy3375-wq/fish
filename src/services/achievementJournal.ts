import { Capacitor, registerPlugin } from '@capacitor/core';
import { computed, ref, shallowReactive, watch } from 'vue';
import { byCode, lifeCodes, type Source } from '../domain/globalAchievements';
import type { HonorHall } from '../domain/communityHonors';

export interface Stamp {at:string; historical:boolean}
interface Journal { stamps:Record<string,Stamp>; pins:string[] }
interface CacheReply {signedIn:boolean; hall?:HonorHall; cachedAt?:number; dirty?:boolean}
interface Bridge {
  journalRead(input:{scope:string}):Promise<{value?:string}>;
  journalWrite(input:{scope:string;value:string}):Promise<void>;
  cachedHall():Promise<CacheReply>;
}
const bridge=registerPlugin<Bridge>('Treehole');
const android=()=>Capacitor.getPlatform()==='android';
const blank=():Journal=>({stamps:{},pins:[]});
const books=shallowReactive(new Map<string,Journal>());
const inflight=new Map<string,Promise<Journal>>();
export const storageIssue=ref('');
export const scopes=ref({device:'device',school:'',learning:''});
export const feedback=ref({sound:false,motion:true,haptics:true});
try {const v=JSON.parse(localStorage.getItem('hyt-award-feedback')||'{}');feedback.value={sound:v.sound===true,motion:v.motion!==false,haptics:v.haptics!==false};}catch{}
watch(feedback,v=>{try{localStorage.setItem('hyt-award-feedback',JSON.stringify(v));}catch{}},{deep:true});
type LocalSource=Exclude<Source,'community'>;
export function subject(source:LocalSource,id=''){
  if(source==='device')return 'device';
  return /^[a-zA-Z0-9_-]{8,96}$/.test(id)?source+'-'+id:'';
}
export async function book(scope:string){
  if(!scope)return blank();
  const loaded=books.get(scope);if(loaded)return loaded;
  const existing=inflight.get(scope);if(existing)return existing;
  const read=(async()=>{
    const value=android()?(await bridge.journalRead({scope})).value:localStorage.getItem('hyt-collection-v1:'+scope);
    const parsed:Journal=value?JSON.parse(value):blank();
    if(!parsed.stamps||!Array.isArray(parsed.pins))throw Error('invalid_collection');
    const source=scope==='device'?'device':scope.split('-')[0];
    const valid=blank();
    for(const [code,stamp] of Object.entries(parsed.stamps)){
      if(byCode.get(code)?.source===source&&typeof stamp?.at==='string'&&Number.isFinite(Date.parse(stamp.at)))
        valid.stamps[code]={at:stamp.at,historical:stamp.historical===true};
    }
    valid.pins=[...new Set(parsed.pins.filter(code=>valid.stamps[code]))].slice(0,3);
    books.set(scope,valid);return valid;
  })().finally(()=>inflight.delete(scope));
  inflight.set(scope,read);return read;
}
export function activate(source:LocalSource,id=''){
  const key=subject(source,id);
  scopes.value[source]=key;
  if(key)void book(key).catch(()=>{storageIssue.value='本机收藏暂时无法读取。';});
}
let tail:Promise<void>=Promise.resolve();
function change(scope:string,update:(current:Journal)=>Journal|null,after?:()=>void){
  const job=tail.then(async()=>{
    const current=await book(scope),next=update(current);if(!next)return;
    const value=JSON.stringify(next);
    if(android())await bridge.journalWrite({scope,value});else localStorage.setItem('hyt-collection-v1:'+scope,value);
    books.set(scope,next);storageIssue.value='';after?.();
  });
  tail=job.catch(()=>{storageIssue.value='本机收藏保存失败，请检查设备可用空间。';});
  return tail;
}
const queue=ref<{scope:string;code:string}[]>([]);
export const localQueue=computed(()=>queue.value.filter(x=>Object.values(scopes.value).includes(x.scope)).map(x=>x.code));
export function dismiss(code:string){queue.value=queue.value.filter(x=>x.code!==code||!Object.values(scopes.value).includes(x.scope));}
export function record(code:string,scope='device',at=new Date().toISOString(),historical=false){
  const a=byCode.get(code);
  if(!a||a.source==='community'||!scope||scope!==scopes.value[a.source]||!Number.isFinite(Date.parse(at)))return Promise.resolve();
  if(books.get(scope)?.stamps[code])return Promise.resolve();
  return change(scope,current=>{
    if(current.stamps[code])return null;
    if(code==='life'&&!lifeCodes.every(k=>current.stamps[k]))return null;
    return {...current,stamps:{...current.stamps,[code]:{at,historical}}};
  },()=>{
    if(!historical&&Object.values(scopes.value).includes(scope))queue.value.push({code,scope});
    if(lifeCodes.includes(code)&&lifeCodes.every(k=>books.get(scope)?.stamps[k]))void record('life',scope,at);
  });
}
export const localStamps=computed(()=>Object.assign({},...Object.values(scopes.value).map(s=>books.get(s)?.stamps||{})) as Record<string,Stamp>);
export const privatePins=computed(()=>Object.values(scopes.value).flatMap(s=>books.get(s)?.pins??[]).slice(0,3));
export async function togglePrivate(code:string){
  const a=byCode.get(code);if(!a||a.source==='community')return;
  const scope=scopes.value[a.source];if(!scope)return;
  await change(scope,book=>{
    if(!book.stamps[code])return null;
    if(book.pins.includes(code))return {...book,pins:book.pins.filter(k=>k!==code)};
    if(privatePins.value.length===3)return null;
    return {...book,pins:[...book.pins,code]};
  });
}
export async function cachedHall():Promise<CacheReply>{
  if(android())return bridge.cachedHall();
  return {signedIn:Capacitor.isPluginAvailable('Treehole')};
}
