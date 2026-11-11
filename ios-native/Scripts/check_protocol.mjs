import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
const root = new URL('../', import.meta.url);
const original = readFileSync(new URL('Hanyuantong/Resources/handan-academic.js', root), 'utf8');
const android = readFileSync(new URL('../android/app/src/main/assets/handan-academic.js', root), 'utf8');
assert.equal(original, android, 'Query resource must remain byte-identical to Android');
const marker = '  window.__handanResult=result;';
assert.equal(original.split(marker).length, 2);
const source = original.replace(marker, '  if(term) result.resolvedTerm=term;\n' + marker);
const termHTML = '<select id="xnm"><option selected value="2026">2026</option></select><select id="xqm"><option selected value="3">秋季</option></select>';
async function run(requestedTerm, failTimetable = false) {
  const dom = new JSDOM('<a id="N2151" href="/kbcx/xskbcx_cxXsgrkbIndex.html">课表</a>', {url:'https://jwgl.hdc.edu.cn/xtgl/index_initMenu.html',runScripts:'outside-only'});
  const requests = [];
  dom.window.AbortController = AbortController;
  dom.window.fetch = async (url, init) => {
    requests.push({url, form: new URLSearchParams(init.body)});
    let data;
    if (!init.body) data = termHTML;
    else if (url.includes('/kbcx/')) data = failTimetable ? {invalid:true} : {kbList:[{kcmc:'合成测试课程',xm:'教师',cdmc:'教室',xqj:'1',jcs:'1-2',zcd:'1-16周'}],sjkList:[]};
    else data = {items:[], totalPage:0};
    return {ok:true,url,text:async()=>typeof data === 'string' ? data : JSON.stringify(data)};
  };
  Object.defineProperty(dom.window.document,'cookie',{get(){throw Error('Cookies must remain native')}});
  await dom.window.eval(`(${source})('syncAll',${JSON.stringify(requestedTerm)})`);
  const result = JSON.parse(JSON.stringify(dom.window.__handanResult));
  dom.window.close();
  return {result, requests};
}
for (let i=0;i<2;i++) {
  const {result,requests} = await run({});
  assert.equal(result.modules.grades.scope, 'all');
  assert.equal(requests.find(x=>x.url.includes('/cjcx/')).form.get('xnm'),'');
  assert.deepEqual(result.resolvedTerm,{xnm:'2026',xqm:'3'});
}
const partial = await run({},true);
assert.equal(partial.result.modules.timetable.status,'error');
assert.equal(partial.result.modules.grades.status,'ok');
assert.equal(partial.result.modules.exams.status,'ok');
assert.deepEqual(partial.result.resolvedTerm,{xnm:'2026',xqm:'3'});
const explicit = await run({xnm:'2026',xqm:'12'},true);
assert.equal(explicit.result.modules.grades.scope,'term');
assert.deepEqual(explicit.result.resolvedTerm,{xnm:'2026',xqm:'12'});
assert.ok(explicit.requests.every(x=>new URL(x.url).origin==='https://jwgl.hdc.edu.cn'));
console.log('Native protocol adaptation: 5 scenarios passed (shared bytes, default repeated refresh, partial failure, explicit term, same-origin requests). Synthetic fixtures only.');
