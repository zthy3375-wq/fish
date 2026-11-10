import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Outbox,PREFIX,SNAPSHOT,mergeEvents} from '../functions/analytics/outbox.mjs';
import {hash,day,validate} from '../functions/analytics/core.mjs';
const id='11111111-1111-4111-8111-111111111111',token='b'.repeat(64),now=Date.UTC(2026,10,10,5),body={id,day:day(now),version:'1.2.1-test.5',versionCode:138,features:{parcel:1}};
class Store {
 data=new Map();fail=false;
 async get(k){return structuredClone(this.data.get(k)??null)}
 async put(k,v,immutable=false){if(this.fail)throw Error('storage_failure');if(!immutable||!this.data.has(k))this.data.set(k,structuredClone(v))}
 async remove(k){this.data.delete(k)}
 async list(prefix,limit){return [...this.data.keys()].filter(k=>k.startsWith(prefix)).slice(0,limit)}
}
function setup(){const store=new Store(),calls=[];let fail=false;const sql=async(q,p)=>{calls.push([q,p]);if(fail)throw Error('database_down');if(q.includes('hyt_metric'))return [{result:{status:200,ok:true}}];if(q.includes('jsonb_build_object'))return [{result:{totals:{total:1,today:1,newToday:1,weekly:1},trend:[],versions:[]}}];return []};return {store,calls,box:new Outbox(store,sql,()=>now),failure(v){fail=v}}}
test('warm and cold processes durably queue records without visiting PostgreSQL',async()=>{
 const s=setup();await s.box.enroll({id},hash(token),'rate');s.calls.length=0;
 await s.box.record(body,hash(token));await new Outbox(s.store,()=>{throw Error('must_not_query')},()=>now).record(body,hash(token));
 assert.equal(s.calls.length,0);assert.equal((await s.store.list(PREFIX+'queue/',2000)).length,1);
 s.store.fail=true;await assert.rejects(()=>s.box.record({...body,features:{parcel:2}},hash(token)));
 assert.equal((await s.box.record(body,hash('c'.repeat(64)))).status,401);
});
test('replay after SQL or snapshot failure retains queue and merges cumulative counters by max',async()=>{
 const s=setup();await s.box.enroll({id},hash(token),'rate');await s.box.record(body,hash(token));await s.box.record({...body,features:{parcel:3}},hash(token));
 s.failure(true);await assert.rejects(()=>s.box.flush());assert.equal((await s.store.list(PREFIX+'queue/',2000)).length,2);
 s.failure(false);s.store.fail=true;await assert.rejects(()=>s.box.flush());assert.equal((await s.store.list(PREFIX+'queue/',2000)).length,2);
 s.store.fail=false;await s.box.flush();const bulk=s.calls.find(([q])=>q.startsWith('WITH incoming'));assert.equal(JSON.parse(bulk[1][0])[0].features.parcel,3);
 assert.equal((await s.store.list(PREFIX+'queue/',2000)).length,0);
});
test('dashboard reads snapshots without SQL; midnight marks today unknown instead of reusing yesterday',async()=>{
 const s=setup();await s.box.snapshot();s.calls.length=0;await s.box.stats();await s.box.stats();assert.equal(s.calls.length,0);
 const next=new Outbox(s.store,()=>{throw Error('must_not_query')},()=>now+86400000);assert.equal((await next.stats()).totals.today,null);
 await s.box.flush();assert.equal(s.calls.length,0);
});
test('deletion removes authorization and queued records are never used to re-enroll devices',async()=>{
 const s=setup();await s.box.enroll({id},hash(token),'rate');await s.box.record(body,hash(token));await s.box.delete({id},hash(token),'rate');
 assert.equal((await s.box.record(body,hash(token))).status,401);s.calls.length=0;await s.box.flush();assert.ok(!s.calls.some(([q])=>q.includes("'enroll'")));
});
test('bounded pre-release versions from existing test APKs are accepted',()=>{assert.equal(validate('record',body,token,now),200);assert.equal(validate('record',{...body,version:'1.2.1-'+ 'a'.repeat(100)},token,now),400)});
test('coalescing preserves different days and the highest version independently',()=>{
 const a={body,tokenHash:hash(token),receivedAt:now},b={...a,body:{...body,version:'1.2.0',versionCode:133,features:{water:2}}};const [r]=mergeEvents([a,b]);assert.equal(r.versionCode,138);assert.equal(r.features.parcel,1);assert.equal(r.features.water,2);
});

test('published version 1.2 is accepted without admitting arbitrary dotted values',()=>{assert.equal(validate('record',{...body,version:'1.2',versionCode:133},token,now),200);assert.equal(validate('record',{...body,version:'1.2.3.4'},token,now),400)});
