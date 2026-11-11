import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
const script = readFileSync(new URL('../assets/handan-academic.js', import.meta.url), 'utf8');
const reader = readFileSync(new URL('../assets/handan-rendered-reader.js', import.meta.url), 'utf8');
const term = '<select id="xnm"><option selected value="2026">2026</option></select><select id="xqm"><option selected value="3">秋</option></select>';
const row = {kcmc:'合成课程',xm:'合成教师',cdmc:'合成教室',xqj:'1',jcs:'3-5',zcd:'1-16周(单)',secret:'must-not-leak'};
async function run(handler, html='<a id="N2151" href="/kbcx/xskbcx_cxXskbcxIndex.html?layout=default">课表</a>') {
  const dom = new JSDOM(html,{url:'https://jwgl.hdc.edu.cn/xtgl/index_initMenu.html',runScripts:'outside-only'});
  const calls=[];
  dom.window.fetch = async (url,init) => {calls.push({url,init}); const value=await handler(url,init); return {ok:true,url,text:async()=>typeof value==='string'?value:JSON.stringify(value)};};
  dom.window.AbortController=AbortController;
  Object.defineProperty(dom.window.document,'cookie',{get(){throw Error('cookies must remain native');}});
  await dom.window.eval(`(${script})('timetable', {})`);
  const result=JSON.parse(JSON.stringify(dom.window.__handanResult));dom.window.close();return {result,calls};
}
test('uses verified Index/query routes and only bridges whitelisted timetable fields',async()=>{
 const {result,calls}=await run((url,init)=>!init.body?term:url.includes('cxRjc')?[]:{kbList:[row],sjkList:[],xsxx:{XM:'must-not-leak',password:'must-not-leak'}});
 assert.equal(result.modules.timetable.status,'ok');assert.equal(result.modules.timetable.data.kbList[0].jcs,'3-5');
 assert.deepEqual(Object.keys(result.modules),['timetable']);assert.ok(!JSON.stringify(result).includes('must-not-leak'));
 assert.ok(calls.every(c=>c.url.startsWith('https://jwgl.hdc.edu.cn/kbcx/')));
 const query=calls.find(c=>c.url.includes('cxXsgrkb')&&c.init.body);assert.equal(new URL(query.url).pathname,'/kbcx/xskbcx_cxXsgrkb.html');assert.ok(!query.url.includes('Index'));assert.equal(new URLSearchParams(query.init.body).get('xnm'),'2026');
});
test('validated empty JSON returns EMPTY, not expiry or synthetic courses',async()=>{const {result}=await run((u,i)=>!i.body?term:{kbList:[],sjkList:[]});assert.equal(result.session,'valid');assert.equal(result.modules.timetable.code,'EMPTY');assert.equal(result.modules.timetable.data,undefined);});
test('login HTML is expiry, not empty',async()=>{const {result}=await run(()=>'<input id="mm" type="password">');assert.equal(result.session,'expired');assert.equal(result.modules.timetable.code,'EXPIRED');});
test('network failure is controlled and never includes error details',async()=>{const {result}=await run(()=>{throw Error('must-not-leak');});assert.equal(result.modules.timetable.code,'NETWORK');assert.ok(!JSON.stringify(result).includes('must-not-leak'));});
test('partial/malformed course rejects complete response rather than omitting row',async()=>{const {result}=await run((u,i)=>!i.body?term:{kbList:[row,{...row,xqj:'9'}],sjkList:[]});assert.equal(result.modules.timetable.code,'COURSE_FIELDS');assert.equal(result.modules.timetable.data,undefined);});
test('malformed practice list rejects data',async()=>{const {result}=await run((u,i)=>!i.body?term:{kbList:[row],sjkList:{}});assert.equal(result.modules.timetable.code,'SCHEMA');});
test('school response term mismatch rejects data',async()=>{const {result}=await run((u,i)=>!i.body?term:{kbList:[row],sjkList:[],xsxx:{XNM:'2025',XQM:'12'}});assert.equal(result.modules.timetable.code,'TERM');});
test('unrecognized HTML stays unresolved and selects compiled rendered fallback',async()=>{const {result}=await run((u,i)=>!i.body?term:'<html>Unrecognized</html>');assert.equal(result.modules.timetable.code,'TIMETABLE_JSON');assert.deepEqual(result.renderedPage.term,{xnm:'2026',xqm:'3'});});
test('practice-only response preserved separately without invented periods',async()=>{const {result}=await run((u,i)=>!i.body?term:u.includes('cxRjc')?[]:{kbList:[],sjkList:[{kcmc:'合成实践',xm:'教师',zcd:'7-8周'}]});assert.equal(result.modules.timetable.status,'ok');assert.equal(result.modules.timetable.data.practice.length,1);assert.equal(result.modules.timetable.data.kbList.length,0);});
test('rendered reader preserves practice-only timetable and selected term',()=>{const dom=new JSDOM(term+'<table id="kbgrid_table_0"><tr><td><div class="timetable_title">实践课程：合成实践■教师(共2周)/7-8周;</div></td></tr></table>',{runScripts:'outside-only'});const result=JSON.parse(dom.window.eval(`(${reader})()`));assert.equal(result.observation.termYear,'2026');assert.equal(result.practice.length,1);assert.equal(result.kbList.length,0);dom.window.close();});
