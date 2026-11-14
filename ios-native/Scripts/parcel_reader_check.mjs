/** Execute the production iOS reader against synthetic DOM only. No real login or network. */
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const source = readFileSync(new URL('../Hanyuantong/Features/Parcel/ParcelReader.swift', import.meta.url), 'utf8');
const script = source.split('static let script = #"""')[1].split('"""#')[0];
const urls = {
  taobao: 'https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home',
  pinduoduo: 'https://m.pinduoduo.net/mdkd/package?tab=ID_CODE'
};
let checks = 0;
function read(html, provider = 'taobao', url = urls[provider]) {
  const dom = new JSDOM(html, { url, runScripts: 'outside-only', pretendToBeVisual: true });
  dom.window.HTMLElement.prototype.getClientRects = function () { return [{x: 0, y: 0, width: 100, height: 30}]; };
  // Disable all request APIs; reader must not need them, use page globals, or modify cookies.
  for (const name of ['fetch', 'XMLHttpRequest']) Object.defineProperty(dom.window, name, { get() { throw new Error('Unexpected network API: ' + name); } });
  const result = JSON.parse(dom.window.Function('requestedProvider', script)(provider));
  dom.window.close(); checks++;
  assert.equal(result.version, 1); assert.equal(result.provider, provider);
  return result;
}
const tb = (station = '合成驿站', field = '取件码：01-02-003') => `<div class="stations--a"><div class="stationName--a">${station}</div><span>${field}</span></div>`;
const pdd = (station = '合成驿站', field = '001-02') => `<div class="package-list-wrapper"><div class="package-list-picking"><div class="station-name">${station}</div><span class="package-code-value">${field}</span></div></div>`;
assert.deepEqual(read(tb()).items, [{station: '合成驿站', code: '01-02-003'}]);
assert.deepEqual(read(pdd(), 'pinduoduo').items, [{station: '合成驿站', code: '001-02'}]);
assert.equal(read(tb() + tb()).items.length, 1);
assert.equal(read(tb('东站') + tb('西站')).items.length, 2);
assert.equal(read(tb('', '取件码 A01 0203')).items[0].code, 'A01 0203');
assert.equal(read(tb('', '取件码：') .replace('</span>', '</span><b>000123</b>')).items[0].code, '000123');
assert.equal(read('<p>正在加载</p>').phase, 'loading');
assert.equal(read('<div class="empty--a">暂无待取包裹</div>').phase, 'empty');
assert.equal(read('<div class="package-none-container">暂无包裹</div>', 'pinduoduo').phase, 'empty');
for (const wrapper of ['hidden', 'style="display:none"', 'style="visibility:hidden"', 'style="opacity:0"', 'aria-hidden="true"']) {
  assert.equal(read(`<div ${wrapper}>${tb()}</div>`).items.length, 0);
  assert.notEqual(read(`<div ${wrapper}><div class="empty--a">暂无待取包裹</div></div>`).phase, 'empty');
}
assert.equal(read('<input type="password">' + tb()).phase, 'login');
assert.equal(read('<input type="tel">' + tb()).phase, 'login');
assert.equal(read('<input autocomplete="one-time-code">' + tb()).phase, 'login');
assert.equal(read('<iframe src="https://login.taobao.com/"></iframe>' + tb()).phase, 'login');
assert.equal(read('<iframe src="https://login.taobao.com/verify"></iframe>' + tb()).phase, 'verify');
assert.equal(read('<div class="captcha">请拖动滑块完成验证</div>' + tb()).phase, 'verify');
assert.equal(read('<script>var x = "暂无待取";</script>').phase, 'loading');
assert.notEqual(read(tb('站点', '取件码：13912345678') + '<div class="empty--a">暂无待取</div>').phase, 'empty');
for (const value of ['取件码：13912345678', '取件码：1234567890', '订单编号：012345', '手机号码：13912345678', '取件码：ABC', '取件码：１２３４', '取件码：A<script>x</script>1']) {
  assert.equal(read(tb('站点', value)).items.length, 0, value);
}
assert.equal(read(tb(), 'taobao', 'https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code').phase, 'unrecognized');
assert.equal(read(tb(), 'taobao', 'https://evil.test/').phase, 'unrecognized');
assert.equal(read(pdd(), 'pinduoduo', 'https://m.pinduoduo.net/mdkd/package/other').phase, 'unrecognized');
assert.equal(read(pdd('', '012-34'), 'pinduoduo').items[0].station, '');
const many = Array.from({length: 110}, (_, i) => `<span class="package-code-value">A-${i}</span>`).join('');
const bounded = read(`<div class="package-list-wrapper"><div class="package-list-picking">${many}</div></div>`, 'pinduoduo');
assert.equal(bounded.items.length, 100); assert.equal(bounded.phase, 'partial');
assert.ok(!/document\.cookie|\.value\b|window\.webkit|fetch\(|XMLHttpRequest|\.click\(|\.submit\(|rawData/.test(script), 'Reader gained credential access or side effects');
console.log(`Parcel production DOM reader: ${checks} synthetic cases passed. No network, accounts, official compatibility or iPhone evidence.`);
