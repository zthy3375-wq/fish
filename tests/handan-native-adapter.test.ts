import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';
import {it,expect,vi} from 'vitest';
const script=readFileSync('android/app/src/main/assets/handan-academic.js','utf8');
const termHtml='<select id="xnm"><option selected value="2026">2026</option></select><select id="xqm"><option selected value="3">秋季</option></select>';
const row={kcmc:'人工格式课程',xm:'教师',cdmc:'教室',xqj:'1',jcs:'1-2',zcd:'1-16周(单)',token:'PRIVATE_TOKEN'};
async function run(routes:(url:string,init:any)=>unknown,operation='syncAll'){
 const dom=new JSDOM('<div id="menu"></div>',{url:'https://jwgl.hdc.edu.cn/xtgl/index_initMenu.html',runScripts:'outside-only'});
 const fetch=vi.fn(async(url:string,init:any)=>({ok:true,url,text:async()=>{const r=routes(url,init);return typeof r==='string'?r:JSON.stringify(r)}}));
 Object.defineProperty(dom.window,'fetch',{value:fetch});dom.window.AbortController=AbortController;
 Object.defineProperty(dom.window.document,'cookie',{get(){throw Error('cookie must stay native')}});
 await dom.window.eval(`(${script})(${JSON.stringify(operation)}, {})`);
 const result=dom.window.__handanResult;dom.window.close();return {result,fetch};
}
it('runs the compiled same-origin query adapter and exports only whitelisted module data',async()=>{
 const {result,fetch}=await run((url,init)=>{
  if(!init.body)return termHtml;
  if(url.includes('/kbcx/'))return {kbList:[row],xsxx:{XM:'姓名',password:'PRIVATE_PASSWORD'},sjkList:[{kcmc:'实践课',jsxm:'教师',qsjsz:'7-10周'}]};
  return {items:[],totalPage:0};
 });
 expect(result.modules.timetable.status).toBe('ok');expect(result.modules.grades.data).toEqual([]);expect(result.modules.exams.data).toEqual([]);
 expect(JSON.stringify(result)).not.toContain('PRIVATE');expect(fetch.mock.calls.every(([u])=>u.startsWith('https://jwgl.hdc.edu.cn/'))).toBe(true);
 const form=new URLSearchParams(fetch.mock.calls.find(([u,i])=>u.includes('cxXsgrkb')&&i.body)![1].body);expect(form.get('xnm')).toBe('2026');expect(form.get('xqm')).toBe('3');
});
it('does not turn empty exams into a login failure and isolates malformed grades from timetable',async()=>{
 const {result}=await run((url,init)=>!init.body?termHtml:url.includes('/kbcx/')?{kbList:[row]}:url.includes('/cjcx/')?'<html>unknown</html>':{items:[],totalPage:0});
 expect(result.session).toBe('valid');expect(result.modules.timetable.status).toBe('ok');expect(result.modules.grades.code).toBe('SCHEMA');expect(result.modules.exams.status).toBe('ok');
});
it('recognizes actual login HTML as expiry rather than a successful empty dataset',async()=>{
 const {result}=await run(()=>'<input type="password" id="mm">');expect(result.session).toBe('expired');expect(result.modules.timetable.code).toBe('EXPIRED');
});
it('paginates history rather than silently returning the first grade page',async()=>{
 const {result}=await run((url,init)=>{
  if(!init.body)return termHtml;
  const p=new URLSearchParams(init.body).get('queryModel.currentPage');
  return {items:[{kcmc:'人工成绩'+p,cj:'优秀',xf:'2',jd:'4',xnm:'2026',xqm:'3'}],totalPage:2};
 },'grades');
 expect(result.modules.grades.data).toHaveLength(2);expect(result.modules.grades.data[0]).toMatchObject({scoreText:'优秀',credit:2,gpa:4});
});
