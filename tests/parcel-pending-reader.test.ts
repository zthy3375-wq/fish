import {describe, expect, it} from 'vitest';
import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';

const script = readFileSync('android/app/src/main/assets/parcel/read-pending.js', 'utf8');
const pdd = 'https://m.pinduoduo.net/mdkd/package?tab=ID_CODE';
const tb = 'https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home';
function read(html: string, url = pdd) {
  const dom = new JSDOM(html, {url, runScripts: 'outside-only'});
  const result = JSON.parse(JSON.stringify(dom.window.eval(script)));
  dom.window.close();
  return result;
}
function group(codes: string[], station = '测试驿站') {
  return `<div class="package-list-wrapper"><section class="package-list-picking"><h3 class="station-name">${station}</h3>${codes.map(code => `<div class="package-code"><label>取件码</label><span class="package-code-value">${code}</span></div>`).join('')}</section></div>`;
}

describe('read-only pending parcel adapter', () => {
  it('reads only pickup fields and retains leading zeroes and station grouping', () => {
    const result = read(group(['01-002-003', 'A8 002']) + '<span class="identification-code-container">身份码 123456789</span><input type="hidden" value="private-token">');
    expect(result).toEqual({version: 1, provider: 'pinduoduo', phase: 'partial', items: [
      {station: '测试驿站', code: '01-002-003'}, {station: '测试驿站', code: 'A8 002'},
    ]});
    expect(JSON.stringify(result)).not.toContain('123456789');
    expect(JSON.stringify(result)).not.toContain('private-token');
  });
  it('does not infer codes from arbitrary numbers or completed parcels', () => {
    const html = '<div class="package-list-wrapper"><div class="package-list-signed"><span class="package-code-value">9-001</span></div></div><p>取件码 123-456</p>';
    expect(read(html)).toMatchObject({phase: 'loading', items: []});
    expect(read(group(['13800138000', '单号123456', '加载中', '取件码:']))).toMatchObject({phase: 'unrecognized', items: []});
  });
  it('only an explicit official empty message counts as empty', () => {
    expect(read('')).toMatchObject({phase: 'loading', items: []});
    expect(read('<p>没有待取包裹</p>')).toMatchObject({phase: 'loading', items: []});
    expect(read('<div class="package-none-container">加载中…</div>')).toMatchObject({phase: 'loading', items: []});
    expect(read('<div class="package-none-container">暂无待取包裹</div>')).toMatchObject({phase: 'empty', items: []});
    expect(read(group(['***']) + '<div class="package-none-container">暂无待取包裹</div>')).toMatchObject({phase: 'unrecognized', items: []});
  });
  it('deduplicates within one station but preserves equal codes at different stations', () => {
    expect(read(group(['01-002', '01-002']) + group(['01-002'], '另一驿站')).items).toHaveLength(2);
  });
  it('bounds the returned data rather than serializing the page', () => {
    const result = read(group(Array.from({length: 130}, (_, i) => `01-${i}`), '站'.repeat(200)));
    expect(result.items).toHaveLength(100);
    expect(result.items[0].station).toHaveLength(100);
    expect(Object.keys(result.items[0])).toEqual(['station', 'code']);
  });
  it('clears data when login or verification is visible, including over a stale list', () => {
    const dom = new JSDOM(group(['01-002']) + '<input type="tel">', {url: pdd, runScripts: 'outside-only'});
    dom.window.document.querySelector('input')!.getClientRects = (() => [{}]) as unknown as typeof Element.prototype.getClientRects;
    expect(dom.window.eval(script)).toMatchObject({phase: 'login', items: []});
    dom.window.close();
    expect(read(group(['01-002']), 'https://m.pinduoduo.net/login.html')).toMatchObject({phase: 'login', items: []});
    expect(read(group(['01-002']), 'https://evil.test/mdkd/package')).toMatchObject({phase: 'unrecognized', items: []});
  });
  it('reads explicit Taobao pickup labels, not unrelated numeric siblings', () => {
    const html = '<section class="stations--fixture"><h3 class="stationName--fixture">测试菜鸟站</h3><div><span>取件码：</span><b>0-018-009</b></div><p>单号：123456789</p></section>';
    expect(read(html, tb)).toMatchObject({provider: 'taobao', phase: 'partial', items: [{station: '测试菜鸟站', code: '0-018-009'}]});
    expect(read(html.replace('取件码：', '手机号：'), tb)).toMatchObject({phase: 'unrecognized', items: []});
  });
  it('does not accept Taobao identity numbers or partial markup as pending parcels', () => {
    expect(read('<div class="identity--fixture"><span class="code--fixture">123456789</span></div>', tb)).toMatchObject({phase: 'loading', items: []});
    expect(read('<main id="handycode-merged"><div id="parcels-content" aria-busy="true">旧取件码 1-2-3</div><iframe id="parcels-source"></iframe></main>', tb)).toMatchObject({phase: 'loading', items: []});
  });
});
