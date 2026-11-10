import {describe, expect, it} from 'vitest';
import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';
const script = (name: string) => readFileSync(`android/app/src/main/assets/parcel/handycode/${name}`, 'utf8');

describe('PDD document-start compatibility, real browser request contract', () => {
  it('only maps the official API within the package page and preserves fetch options', async () => {
    const dom = new JSDOM('', {url: 'https://m.pinduoduo.net/mdkd/package?tab=ID_CODE', runScripts:'outside-only'});
    const calls: unknown[][] = [];
    dom.window.fetch = ((...args: unknown[]) => { calls.push(args); return Promise.resolve({}) }) as typeof fetch;
    dom.window.eval(script('pdd-same-origin.js'));
    const opts = {method:'POST', body:'synthetic', headers:{'X-Test':'fixture'}, credentials:'include'};
    await dom.window.fetch('https://api.pinduoduo.com/api/express_trackbox/test?x=1', opts as RequestInit);
    expect(calls[0]).toEqual(['https://m.pinduoduo.net/proxy/api/api/express_trackbox/test?x=1', opts]);
    expect(calls[0][1]).toBe(opts);
    for (const url of ['https://api.pinduoduo.com.evil.test/api/test','https://api.pinduoduo.com:444/api/test','https://api.pinduoduo.com/public/test','https://evil.test/api/test']) {
      await dom.window.fetch(url); expect(calls.at(-1)?.[0]).toBe(url);
    }
    dom.window.close();
  });
  it('never changes login-page requests and repeated installation does not wrap twice', async () => {
    const dom = new JSDOM('', {url:'https://m.pinduoduo.net/login.html', runScripts:'outside-only'});
    const original = () => Promise.resolve({}); dom.window.fetch = original as unknown as typeof fetch;
    dom.window.eval(script('pdd-same-origin.js')); expect(dom.window.fetch).toBe(original);
    dom.reconfigure({url:'https://m.pinduoduo.net/mdkd/package'});
    dom.window.eval(script('pdd-same-origin.js')); const wrapped = dom.window.fetch;
    dom.window.eval(script('pdd-same-origin.js')); expect(dom.window.fetch).toBe(wrapped);
    dom.window.close();
  });
});

describe('Taobao login presentation is retained until actual code is ready', () => {
  it('rejects an empty skeleton and an active official auth iframe', () => {
    const dom = new JSDOM('<div class="identity--fixture"><span class="code--fixture"></span><img class="width-origin--fixture"></div>', {url:'https://pages-fast.m.taobao.com', runScripts:'outside-only'});
    dom.window.eval(script('official-identity.js'));
    const win = dom.window as unknown as {HandyCodeOfficialIdentity: {ready: (doc: Document) => boolean}};
    expect(win.HandyCodeOfficialIdentity.ready(dom.window.document)).toBe(false);
    dom.window.document.querySelector('span')!.textContent = 'synthetic-code';
    const image = dom.window.document.querySelector('img')!;
    Object.defineProperty(image, 'complete', {value:true}); Object.defineProperty(image, 'naturalWidth', {value:300});
    expect(win.HandyCodeOfficialIdentity.ready(dom.window.document)).toBe(true);
    const frame = dom.window.document.createElement('iframe'); frame.src = 'https://login.m.taobao.com/login.htm';
    frame.getClientRects = (() => [{}]) as unknown as typeof frame.getClientRects;
    frame.getBoundingClientRect = (() => ({width:300,height:500,right:300,bottom:500,left:0,top:0})) as typeof frame.getBoundingClientRect;
    dom.window.document.body.append(frame);
    expect(win.HandyCodeOfficialIdentity.ready(dom.window.document)).toBe(false);
    dom.window.close();
  });
});
