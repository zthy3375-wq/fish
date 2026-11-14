import Foundation

/// Original iOS adapter based on this repository's unpublished Android read-pending.js contract,
/// PR #48 @ dd3ba779. Runs once, in WKContentWorld.defaultClient, on the current official document.
/// No fetch interception, endpoint guessing, form values, account values, image capture, or native bridge.
enum ParcelReader {
    static let script = #"""
    const provider = requestedProvider;
    const expected = provider === 'taobao'
      ? ['https://pages-fast.m.taobao.com', '/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home']
      : provider === 'pinduoduo' ? ['https://m.pinduoduo.net', '/mdkd/package'] : null;
    const items = [], seen = new Set();
    let missing = 0;
    const result = phase => JSON.stringify({version: 1, provider, phase, items});
    const clean = (el, max = 120) => {
      const value = el ? (el.textContent || '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim() : '';
      return value.length <= max ? value : '';
    };
    const visible = el => {
      if (!el || !el.getClientRects().length) return false;
      for (let p = el; p && p.nodeType === 1; p = p.parentElement) {
        const style = getComputedStyle(p);
        if (p.hidden || p.getAttribute('aria-hidden') === 'true' || style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
      }
      return true;
    };
    const fieldCode = value => {
      value = value.replace(/^(?:取件码|提货码|取货码)\s*[:：]?\s*/, '').trim();
      return /^(?=.{2,24}$)(?=.*[0-9])[A-Za-z0-9]+(?:[-—–－ ][A-Za-z0-9]+)*$/.test(value) && !/^[0-9]{10,}$/.test(value) ? value : '';
    };
    const add = (station, code) => {
      if (!code) { missing++; return; }
      const key = station + '\n' + code;
      if (seen.has(key)) return;
      seen.add(key);
      if (items.length < 100) items.push({station, code});
      else missing++;
    };
    if (!expected || location.origin !== expected[0] || location.pathname !== expected[1]) return result('unrecognized');
    const inputs = Array.from(document.querySelectorAll('input')).slice(0, 500);
    if (inputs.some(el => visible(el) && (/password|tel/.test(el.type) || /one-time-code/.test(el.autocomplete) || /手机号|验证码|登录密码|手机号码/.test(el.placeholder || '')))) return result('login');
    const frames = Array.from(document.querySelectorAll('iframe')).slice(0, 30);
    if (frames.some(el => visible(el) && /captcha|punish|verify/i.test(el.src))) return result('verify');
    if (frames.some(el => visible(el) && /login|passport/i.test(el.src))) return result('login');
    const challenge = Array.from(document.querySelectorAll('[class*="captcha"],[id*="captcha"],[class*="verify"],[id*="nc-container"]')).slice(0, 100);
    if (challenge.some(el => visible(el) && /验证|拖动|滑块|安全检查/.test(clean(el, 300)))) return result('verify');
    const selector = provider === 'pinduoduo'
      ? '[class*="package-list-wrapper"] .package-list-picking'
      : '[class^="stations--"],[class*=" stations--"]';
    const allGroups = Array.from(document.querySelectorAll(selector));
    if (allGroups.length > 100) missing++;
    for (const group of allGroups.slice(0, 100)) {
      if (!visible(group)) continue;
      const stationEl = group.querySelector(provider === 'pinduoduo' ? '.station-name' : '[class^="stationName--"],[data-role="station"]');
      const station = visible(stationEl) ? clean(stationEl) : '';
      if (provider === 'pinduoduo') {
        const fields = Array.from(group.querySelectorAll('.package-code-value'));
        if (!fields.length || fields.length > 100) missing++;
        for (const field of fields.slice(0, 100)) if (visible(field)) add(station, fieldCode(clean(field, 60)));
      } else {
        const fields = Array.from(group.querySelectorAll('span,div,p,strong,b'));
        if (fields.length > 4000) missing++;
        const leaves = fields.slice(0, 4000).filter(el => !el.children.length && visible(el) && /^(?:取件码|提货码|取货码)(?:\s*[:：]|\s|$)/.test(clean(el, 60)));
        if (!leaves.length) missing++;
        for (const leaf of leaves) {
          let code = fieldCode(clean(leaf, 60));
          if (!code && /^(?:取件码|提货码|取货码)\s*[:：]?\s*$/.test(clean(leaf))) {
            const sibling = leaf.nextElementSibling;
            if (visible(sibling)) code = fieldCode(clean(sibling, 60));
          }
          add(station, code);
        }
      }
    }
    if (items.length) return result('partial');
    const empty = Array.from(document.querySelectorAll('[class*="package-none-container"],[class*="empty--"],[class*="emptyTip--"]')).slice(0, 100)
      .some(el => visible(el) && /暂无待取|没有待取|无待取包裹|暂无包裹/.test(clean(el, 120)));
    if (!missing && empty) return result('empty');
    return result(missing ? 'unrecognized' : 'loading');
    """#
}
