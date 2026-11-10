/* Read-only DOM adapter. No requests, form values, cookies, images or identity codes. */
(function () {
  'use strict';
  var provider = location.origin === 'https://m.pinduoduo.net' ? 'pinduoduo' :
    location.origin === 'https://pages-fast.m.taobao.com' ? 'taobao' : '';
  var items = [], seen = new Set(), missing = 0;
  function result(phase) { return {version: 1, provider: provider, phase: phase, items: items}; }
  function text(node, limit) { return node ? (node.textContent || '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, limit || 100) : ''; }
  function visible(node) {
    if (!node || node.hidden) return false;
    var style = node.ownerDocument.defaultView.getComputedStyle(node);
    return style.display !== 'none' && style.visibility !== 'hidden';
  }
  function login(doc) {
    if (window.HandyCodeOfficialIdentity && HandyCodeOfficialIdentity.loginVisible(doc)) return true;
    return Array.from(doc.querySelectorAll('input,textarea,[contenteditable="true"]')).some(function (node) {
      return !/^(hidden|checkbox|radio|button|submit|reset)$/.test(node.type || '') && visible(node) && node.getClientRects().length;
    });
  }
  function code(value) {
    value = value.replace(/^(?:取件码|提货码|取货码)\s*[:：]?\s*/, '').trim();
    // Explicit pickup field only; never infer a code from a phone, order or tracking number.
    return /^(?=.{2,24}$)(?=.*\d)[A-Za-z0-9]+(?:[-—–－\s][A-Za-z0-9]+)*$/.test(value) && !/^\d{11,}$/.test(value) ? value : '';
  }
  function add(station, value) {
    if (!value) { missing++; return; }
    station = station || '驿站待核对';
    var key = station + '\n' + value;
    if (seen.has(key)) return;
    seen.add(key);
    if (items.length < 100) items.push({station: station.slice(0, 100), code: value});
    else missing++;
  }
  function empty(root) {
    // Only specific official empty-state elements count, not an empty DOM or a failed read.
    return Array.from(root.querySelectorAll('[class*="package-none-container"],[class*="empty--"],[class*="emptyTip--"]')).some(function (el) {
      return visible(el) && /暂无待取|没有待取|无待取包裹|暂无包裹/.test(text(el));
    });
  }
  if (!provider || login(document)) return result(provider ? 'login' : 'unrecognized');
  if (provider === 'pinduoduo') {
    if (location.pathname !== '/mdkd/package') return result(/login/.test(location.pathname) ? 'login' : 'unrecognized');
    // The original React root remains in the document after HandyCode projects the page.
    var groups = document.querySelectorAll('[class*="package-list-wrapper"] .package-list-picking');
    groups.forEach(function (group) {
      var station = text(group.querySelector('.station-name'));
      var fields = group.querySelectorAll('.package-code-value');
      fields.forEach(function (field) { if (visible(field)) add(station, code(text(field, 40))); });
      if (!fields.length && text(group)) missing++;
    });
    if (items.length) return result('partial');
    if (!missing && empty(document)) return result('empty');
    return result(missing ? 'unrecognized' : 'loading');
  }
  var doc = document;
  if (document.getElementById('handycode-merged')) {
    var frame = document.getElementById('parcels-source');
    // Do not reuse a previous projection during refresh, authentication or a cross-origin redirect.
    var mount = document.getElementById('parcels-content');
    if (!mount || mount.getAttribute('aria-busy') === 'true') return result('loading');
    try { doc = frame && frame.contentDocument; } catch (_) { return result('login'); }
    if (!doc || !doc.body) return result('loading');
    if (login(doc)) return result('login');
    try { if (new URL(doc.URL).origin !== location.origin) return result('login'); } catch (_) { return result('unrecognized'); }
  } else if (!/\/m-end-school-tab\/home$/.test(location.pathname)) return result('loading');
  var stationGroups = doc.querySelectorAll('[class^="stations--"],[class*=" stations--"]');
  stationGroups.forEach(function (group) {
    var station = text(group.querySelector('[class^="stationName--"],[data-role="station"]'));
    // A number is accepted only when its own leaf explicitly labels it as a pickup code.
    var leaves = Array.from(group.querySelectorAll('span,div,p,strong,b')).filter(function (node) {
      return visible(node) && node.children.length === 0 && /^(?:取件码|提货码|取货码)(?:\s*[:：]|\s|$)/.test(text(node, 60));
    });
    leaves.forEach(function (leaf) {
      var value = code(text(leaf, 60));
      if (!value && /^(?:取件码|提货码|取货码)\s*[:：]?\s*$/.test(text(leaf))) {
        var sibling = leaf.nextElementSibling;
        if (sibling && visible(sibling)) value = code(text(sibling, 40));
      }
      add(station, value);
    });
    if (!leaves.length && text(group)) missing++;
  });
  if (items.length) return result('partial');
  if (!missing && empty(doc)) return result('empty');
  return result(missing ? 'unrecognized' : 'loading');
})()
