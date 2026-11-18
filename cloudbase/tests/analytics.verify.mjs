import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {validate,authorized,readBody,day,hash} from '../functions/analytics/core.mjs';
const token='a'.repeat(64),id=randomUUID(),body={id,day:day(),version:'1.0.3',versionCode:103,features:{water:2}};
test('accepts enrolled installation and bounded feature counters',()=>{assert.equal(validate('enroll',{id},token),200);assert.equal(validate('record',body,token),200)});
test('rejects personal fields, unknown features and unbounded counts',()=>{for(const b of [{...body,account:'123'},{...body,features:{unknown:1}},{...body,features:{water:1001}},{...body,features:{water:-1}}])assert.equal(validate('record',b,token),400)});
test('rejects invalid installation credentials and stale/future reports',()=>{assert.equal(validate('enroll',{id},''),401);assert.equal(validate('record',{...body,day:'2000-01-01'},token),400);assert.equal(validate('record',{...body,day:day(Date.now()+86400000)},token),400)});
test('admin comparison fails closed',()=>{assert.equal(authorized(undefined,'abc'),false);assert.equal(authorized('abc',''),false);assert.equal(authorized('a','b'),false);assert.equal(authorized('abc','abc'),true)});
test('body reader stops oversized payloads',async()=>{async function* input(){yield Buffer.alloc(2049)}await assert.rejects(()=>readBody(input()))});
import {bindSQL,decodeRows} from '../functions/analytics/database.mjs';
test('SQL values cannot escape literals or alter query structure',()=>{const value="');DROP TABLE users;--";const sql=bindSQL('SELECT $1,$2::int',[value,3]);assert.ok(!sql.includes('DROP TABLE'));assert.ok(sql.includes(Buffer.from(value).toString('base64')));assert.throws(()=>bindSQL('SELECT $1',[]))});
test('Cloud API row decoder parses JSON and preserves scalar fields',()=>{assert.deepEqual(decodeRows({Columns:['result','count'],Rows:['["{\\"ok\\":true}","2"]']}),[{result:{ok:true},count:'2'}])});

import {retiredAnalytics} from '../functions/analytics/server.mjs';
test('retired clients receive acknowledgement without a single database call; only authenticated deletion uses SQL',async()=>{
 const calls=[],app=retiredAnalytics(async(...args)=>{calls.push(args);return [{result:{status:200,ok:true}}]},async()=>{});
 await new Promise(r=>app.listen(0,'127.0.0.1',r));
 try{
  const origin='http://127.0.0.1:'+app.address().port+'/api/metrics/';
  for(const action of ['enroll','record']){const res=await fetch(origin+action,{method:'POST',body:'discarded'});assert.deepEqual(await res.json(),{ok:true,collection:false})}
  const payload={method:'POST',body:JSON.stringify({id:'00000000-0000-4000-8000-000000000001'})};
  assert.equal((await fetch(origin+'delete',payload)).status,401);assert.equal(calls.length,0);
  assert.equal((await fetch(origin+'delete',{...payload,headers:{'x-hyt-token':'1'.repeat(64)}})).status,200);
  assert.equal(calls.length,1);assert.equal(calls[0][1][0],'delete');
 }finally{await new Promise(r=>app.close(r))}
});
import {deleteLegacyObjects} from '../functions/analytics/legacy-deletion.mjs';
test('deletes only the authenticated legacy installation across queue pages and can retry partial work',async()=>{
 const id='device',proof='proof',prefix='hyt-analytics-v2/',mark=prefix+'auth/'+hash(id+'|'+proof)+'.json';
 const a=prefix+'queue/a',b=prefix+'queue/b',c=prefix+'queue/c';
 const rows=new Map([[mark,{id,tokenHash:proof}],[a,{body:{id},tokenHash:proof}],[b,{body:{id:'other'},tokenHash:'other'}],[c,{body:{id},tokenHash:proof}]]);
 let fail=true;const adapter={get:async k=>rows.get(k),remove:async k=>{if(k===c&&fail)throw Error('offline');rows.delete(k)},page:async cur=>cur?{keys:[b,c],truncated:false}:{keys:[a],next:a,truncated:true}};
 await deleteLegacyObjects(id,'wrong',adapter);assert.equal(rows.size,4);
 await assert.rejects(deleteLegacyObjects(id,proof,adapter));assert(rows.has(mark));fail=false;
 await deleteLegacyObjects(id,proof,adapter);assert.deepEqual([...rows.keys()],[b]);
});
