import {afterEach, describe, expect, it} from 'vitest';
import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';
const script=readFileSync('android/app/src/main/assets/parcel/native/collector.js','utf8');
const doms:JSDOM[]=[];
function fixture(html='',url='https://m.pinduoduo.net/mdkd/package'){
 const dom=new JSDOM(html,{url,runScripts:'outside-only'});doms.push(dom);dom.window.HTMLElement.prototype.getClientRects=(()=>[{}]) as any;dom.window.eval(script);
 return {dom,api:(dom.window as any).HytParcel};
}
afterEach(()=>doms.splice(0).forEach(d=>d.window.close()));
describe('native parcel collector',()=>{
 it('reads structured records with inherited stations and preserves code leading zeroes',()=>{
  const {api}=fixture();api.consume({success:true,data:{stationName:'合成东站',packages:[{mailNo:'SYNTHETIC001',takeCode:'01-02-003',cpName:'测试快递'}]}});
  expect(api.read()).toMatchObject({phase:'partial',items:[{id:'waybill:SYNTHETIC001',code:'01-02-003',station:'合成东站',state:'pending'}]});
 });
 it('rejects generic response codes, phone numbers and order IDs as pickup codes',()=>{
  const {api}=fixture();api.consume({code:200,orderId:'123456',phone:'13800138000',data:[{code:'1234'},{takeCode:'13800138000'},{takeCode:'1234567890123'}]});
  expect(api.read().items).toEqual([]);expect(api.read().phase).toBe('loading');
 });
 it('does not infer picked-up from trading status or historical text',()=>{
  const {api}=fixture();api.consume({data:[{mailNo:'SYNTHETIC001',takeCode:'01-02-003',statusText:'待评价'},{mailNo:'SYNTHETIC002',takeCode:'02-03-004',statusText:'已取件'}]});
  expect(api.read().items).toMatchObject([{state:'pending',code:'01-02-003'},{state:'picked',code:''}]);
 });
 it('parses official JSONP without evaluating returned code',()=>{
  const {api,dom}=fixture();api.consume('mtopjsonp1({"data":{"mailNo":"SYNTHETIC001","takeCode":"01-02-003"}})');
  expect(api.read().items).toHaveLength(1);api.consume('window.attack=true');expect((dom.window as any).attack).toBeUndefined();
 });
 it('does not accept payloads reporting expired authentication',()=>{
  const {api}=fixture();api.consume({ret:['FAIL_SYS_SESSION_EXPIRED'],data:{mailNo:'SYNTHETIC001',takeCode:'01-02-003'}});expect(api.read().items).toEqual([]);
 });
 it('returns a login state without any captured codes during authentication',()=>{
  const {api,dom}=fixture();api.consume({data:{takeCode:'01-02-003',stationName:'合成东站'}});dom.reconfigure({url:'https://m.pinduoduo.net/login.html'});
  expect(api.read()).toMatchObject({phase:'login',items:[]});
 });
 it('distinguishes an explicit empty list from an unrecognised page',()=>{
  expect(fixture('<div>Loading</div>').api.read().phase).toBe('loading');
  expect(fixture('<div class="package-none-container">暂无待取包裹</div>').api.read().phase).toBe('empty');
 });
 it('does not treat hidden empty placeholders as successful authentication',()=>{
  const {api}=fixture('<div style="display:none"><div class="package-none-container">暂无待取包裹</div></div>');
  expect(api.read().phase).toBe('loading');
 });
 it('reads narrowly scoped DOM fields without projecting any page',()=>{
  const {api}=fixture('<div class="package-list-wrapper"><section class="package-list-picking"><span class="station-name">合成驿站</span><span class="package-code-value">D-0034</span></section></div><span>取件码 99999</span>');
  expect(api.read().items).toMatchObject([{code:'D-0034',station:'合成驿站'}]);expect(api.read().items).toHaveLength(1);
 });
 it('ignores fetch responses from lookalike or unrelated hosts and preserves original response',async()=>{
  const dom=new JSDOM('',{url:'https://m.pinduoduo.net/mdkd/package',runScripts:'outside-only'});doms.push(dom);
  const response={clone:()=>({text:async()=>JSON.stringify({data:{takeCode:'01-02-003'}})})};
  dom.window.fetch=(async()=>response) as any;dom.window.eval(script);
  expect(await dom.window.fetch('https://api.pinduoduo.com.evil.test/api/express_trackbox/test')).toBe(response);
  await Promise.resolve();expect((dom.window as any).HytParcel.read().items).toEqual([]);
  await dom.window.fetch('https://m.pinduoduo.net/proxy/api/api/express_trackbox/test');await Promise.resolve();await Promise.resolve();
  expect((dom.window as any).HytParcel.read().items).toHaveLength(1);
 });
 it('bounds deep and oversized responses',()=>{
  const {api}=fixture();let o:any={takeCode:'01-02-003'};for(let i=0;i<30;i++)o={data:o};api.consume(o);expect(api.read().items).toEqual([]);
  api.consume(' '.repeat(1500001));expect(api.read().items).toEqual([]);
 });
});
