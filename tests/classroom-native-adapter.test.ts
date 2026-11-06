import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';
import {describe,it,expect,vi} from 'vitest';
const script=readFileSync('android/app/src/main/assets/handan-classrooms.js','utf8');
const q={xnm:'2026',xqm:'3',date:'2026-11-06',week:8,weekday:5,campusId:'1',buildingId:'',startPeriod:1,endPeriod:2};
const rawRoom={cd_id:'r1',cdxqxx_id:'tr1',cdbh:'R001',cdmc:'人工测试教室',lh:'b1',jxlmc:'人工教学楼',xqmc:'人工校区',cdlbmc:'测试类型',zws:'40',userModel:{password:'PRIVATE'},cdgly:'PRIVATE'};
const html='<select id="dm_cx"><option value="2026-3" selected>人工学期</option></select><select id="xqh_id"><option value="1">人工校区</option></select>';
async function run(operation:string,overrides:(u:URL)=>unknown=()=>undefined,query:any=q,legacyArrays=false){
 const dom=new JSDOM('<div id="menu"></div>',{url:'https://jwgl.hdc.edu.cn/xtgl/index_initMenu.html',runScripts:'outside-only'});
 if(legacyArrays)dom.window.eval(`
  Array.prototype.filter=function(fn,scope){const out=[];for(let i=0;i<this.length;i++)if(fn.call(scope||window,i,this[i],this))out.push(this[i]);return out};
  Array.prototype.some=function(fn,scope){for(let i=0;i<this.length;i++)if(fn.call(scope||window,i,this[i],this))return true;return false};
  Array.prototype.every=function(){return true};
 `);
 const fetch=vi.fn(async(url:string)=>{const u=new URL(url);let value=overrides(u);
 if(value===undefined){
  if(u.pathname.includes('cxKxcdlb'))value=u.searchParams.get('doType')==='query'?{items:[rawRoom],totalCount:1,totalPage:1}:html;
  else if(u.pathname.includes('cxXqjc'))value={lhList:[{JXLDM:'b1',JXLMC:'人工教学楼'}],jcList:[{JCMC:1,SJD:'08:00-08:40'},{JCMC:2,SJD:'08:45-09:25'},{JCMC:3,SJD:'09:45-10:25'}]};
  else if(u.pathname.includes('cxQtlb'))value={dqzcxq:{ZXRQ:'2026-09-14',ZDRQ:'2027-01-24'},nxqzcList:Array.from({length:19},(_,i)=>({dxqzc:String(i+1),zczt:'3'}))};
  else if(u.pathname.includes('cxDateInforma'))value=[u.searchParams.get('zcd')==='1'?'2026-09-14':'2026-11-06'];
  else if(u.pathname.includes('cxAtyycdSchedule'))value={jcList:[{jcmc:'1',jcm:'1'},{jcmc:'2',jcm:'2'},{jcmc:'3',jcm:'4'}],scheduleList:[{...rawRoom,rs_2:'PRIVATE occupation details'}]};
 }
 return {url,ok:true,status:200,text:async()=>typeof value==='string'?value:JSON.stringify(value)};
 });
 Object.defineProperty(dom.window,'fetch',{value:fetch});dom.window.AbortController=AbortController;
 Object.defineProperty(dom.window.document,'cookie',{get(){throw Error('no Vue/script credential access')}});
 await dom.window.eval(`(${script})(${JSON.stringify(operation)},${JSON.stringify(query)})`);
 const result=dom.window.__handanResult;dom.window.close();return {result,fetch};
}
describe('Handan N2155 compiled native connector',()=>{
 it('loads real-contract options and school calendar, exporting only normalized fields',async()=>{const {result}=await run('rooms-options');expect(result.classrooms.data).toMatchObject({weekStartDate:'2026-09-14',campusId:'1'});expect(result.classrooms.data.periods[1]).toEqual({number:2,start:'08:45',end:'09:25'});expect(JSON.stringify(result)).not.toContain('PRIVATE')});
 it('encodes week/period bit masks and rechecks date using the server before querying',async()=>{const {result,fetch}=await run('rooms-query');expect(result.classrooms.status).toBe('ok');const calls=fetch.mock.calls.map(([u])=>new URL(u));const u=calls.find(u=>u.searchParams.get('doType')==='query')!;expect(u.searchParams.get('zcd')).toBe('128');expect(u.searchParams.get('jcd')).toBe('3');expect(u.searchParams.get('xqj')).toBe('5');expect(u.searchParams.get('gnmkdm')).toBe('N2155');expect(result.classrooms.data.rooms[0].capacity).toBe(40);expect(JSON.stringify(result)).not.toContain('PRIVATE');expect(calls.every(u=>u.origin==='https://jwgl.hdc.edu.cn'&&u.pathname.startsWith('/cdjy/'))).toBe(true)});
 it('paginates instead of claiming only the first 100 rooms are the complete list',async()=>{const {result}=await run('rooms-query',u=>u.searchParams.get('doType')==='query'?{items:[{...rawRoom,cd_id:'r'+u.searchParams.get('queryModel.currentPage')}],totalCount:2,totalPage:2}:undefined);expect(result.classrooms.data.rooms).toHaveLength(2)});
 it('treats a well formed zero-result query as empty, without expiring login',async()=>{const {result}=await run('rooms-query',u=>u.searchParams.get('doType')==='query'?{items:[],totalCount:0,totalPage:0}:undefined);expect(result.session).toBe('valid');expect(result.classrooms.data.rooms).toEqual([])});
 it('does not infer free rooms from malformed or partial pages',async()=>{const {result}=await run('rooms-query',u=>u.searchParams.get('doType')==='query'?{items:[],totalCount:2,totalPage:2}:undefined);expect(result.classrooms.code).toBe('SCHEMA');expect(result.classrooms.data).toBeUndefined()});
 it('rejects a date/week mismatch before querying rooms',async()=>{const {result,fetch}=await run('rooms-query',()=>undefined,{...q,date:'2026-11-07'});expect(result.classrooms.code).toBe('DATE');expect(fetch.mock.calls.some(([u])=>u.includes('doType=query'))).toBe(false)});
 it('does not accept nonexistent buildings or out-of-range periods',async()=>{expect((await run('rooms-query',()=>undefined,{...q,buildingId:'missing'})).result.classrooms.code).toBe('FILTER');expect((await run('rooms-query',()=>undefined,{...q,endPeriod:9})).result.classrooms.code).toBe('SCHEMA')});
 it('recognizes actual login markup without disclosing credentials or treating it as an empty list',async()=>{const {result}=await run('rooms-query',()=>'<input type="password" id="mm">');expect(result.session).toBe('expired');expect(result.classrooms.code).toBe('EXPIRED')});
 it('parses sparse school day occupancy and strips all occupation text',async()=>{const {result}=await run('rooms-day',()=>undefined,{...q,roomId:'r1',roomName:'人工测试教室'});expect(result.classrooms.data.slots.map((p:any)=>p.state)).toEqual(['free','occupied','free']);expect(JSON.stringify(result)).not.toContain('PRIVATE')});
 it('marks missing period mappings unknown; missing rooms fail rather than become free all day',async()=>{const missing=await run('rooms-day',u=>u.pathname.includes('cxAtyy')?{jcList:[{jcmc:'1',jcm:'1'}],scheduleList:[rawRoom]}:undefined,{...q,roomId:'r1',roomName:'人工测试教室'});expect(missing.result.classrooms.data.slots[1].state).toBe('unknown');expect((await run('rooms-day',()=>undefined,{...q,roomId:'other',roomName:'人工测试教室'})).result.classrooms.code).toBe('SCHEMA')});
});

describe('school legacy Array overrides',()=>{
 it.each(['rooms-options','rooms-query','rooms-day'])('keeps %s working when the school reverses filter/some callback arguments',async operation=>{
  const {result}=await run(operation,()=>undefined,{...q,roomId:'r1',roomName:'人工测试教室'},true);
  expect(result.classrooms.status).toBe('ok');
  if(operation==='rooms-query')expect(result.classrooms.data.rooms[0].name).toBe('人工测试教室');
  if(operation==='rooms-day')expect(result.classrooms.data.slots[1].state).toBe('occupied');
 });
});

it('still rejects an invalid period sequence when the school every() always returns true',async()=>{
 const {result}=await run('rooms-options',u=>u.pathname.includes('cxXqjc')?{lhList:[],jcList:[{JCMC:1,SJD:'08:00-08:40'},{JCMC:3,SJD:'09:45-10:25'}]}:undefined,q,true);
 expect(result.classrooms.code).toBe('SCHEMA');
});
