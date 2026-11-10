/* Hanyuantong: official page responses -> bounded parcel fields. No forms, credentials or uploads. */
(function () {
  'use strict';
  if (window.HytParcel) return;
  var host = location.hostname;
  var provider = /(^|\.)taobao\.com$/.test(host) ? 'taobao' :
    /^(m\.pinduoduo\.net|mobile\.yangkeduo\.com)$/.test(host) ? 'pinduoduo' : '';
  if (!provider) return;
  var records = new Map(), responses = 0, explicitEmpty = false, visited = 0;
  var orderLinks = new Set();
  function clean(v, max) { return typeof v === 'string' || typeof v === 'number' ? String(v).replace(/[\x00-\x1f\x7f]/g, ' ').trim().slice(0, max || 120) : ''; }
  function first(o, keys, max) { for (var k of keys) { var s = clean(o[k], max); if (s) return s; } return ''; }
  function code(v) {
    v = clean(v, 40).replace(/^(?:取件码|提货码|取货码)\s*[:：]?\s*/, '');
    return /^(?=.{2,24}$)(?=.*\d)[A-Za-z0-9]+(?:[-—–－\s][A-Za-z0-9]+)*$/.test(v) && !/^\d{10,}$/.test(v) && !/^1[3-9]\d{9}$/.test(v) ? v : '';
  }
  function explicitCode(s) { var m = clean(s, 3000).match(/(?:取件码|提货码|取货码)\s*[:：]?\s*([A-Za-z0-9]+(?:[-—–－][A-Za-z0-9]+)*)/); return m ? code(m[1]) : ''; }
  function put(item) {
    if (!item.id || records.size >= 300) return;
    var old = records.get(item.id);
    // Keep known fields during progressive responses; an explicit picked-up event hides the old code.
    if (old) ['station','tracking','courier','title'].forEach(function (k) { if (!item[k]) item[k] = old[k]; });
    if (item.state === 'picked') item.code = '';
    records.set(item.id, item);
  }
  function parseNode(o, inheritedStation, depth) {
    if (!o || depth > 14 || ++visited > 12000) return;
    if (Array.isArray(o)) { o.slice(0, 300).forEach(function (v) { parseNode(v, inheritedStation, depth + 1); }); return; }
    if (typeof o !== 'object') return;
    var station = first(o, ['stationName','siteName','pickupPointName','station_name','addressName','stationDesc']) || inheritedStation;
    var tracking = first(o, ['mailNo','waybillNo','trackingNo','trackingNumber','tracking_number','mailno'], 64);
    var order = first(o, ['order_sn','orderSn','bizOrderId','orderId'], 80);
    var pickup = code(first(o, ['takeCode','fetchCode','pickupCode','shelfCode','pickCode','fetchNum','pickup_code','take_code','packageCode']));
    var desc = first(o, ['latestTrace','logisticsText','latestDesc','action','description','desc','context'], 1000);
    var status = first(o, ['statusText','statusDesc','stateDesc','status_desc','logisticsStatusDesc','order_status_prompt'], 200);
    if (!pickup) pickup = explicitCode(desc);
    var state = /已取件|已提货|本人已签收|用户已取|已出库/.test(status) ? 'picked' :
      pickup || /待取件|待提货|已入库|等待领取/.test(status) ? 'pending' : 'transit';
    if (order && provider === 'pinduoduo' && !/取消|退款|交易关闭|待付款/.test(status)) orderLinks.add(order);
    // Codes must be explicit fields; generic id/code/order status never become pickup codes.
    if ((pickup || tracking && /待取件|待提货|已入库|已取件|已提货|运输中|派送中/.test(status)) && !/取消|退款|交易关闭/.test(status)) {
      var stableId = tracking ? 'waybill:' + tracking : order ? 'order:' + order + ':' + pickup : 'shelf:' + station + ':' + pickup;
      put({id:stableId, code:pickup, station:station, tracking:tracking, courier:first(o,['cpName','expressCompanyName','shipping_name','courierName']), title:first(o,['goods_name','goodsName','title']), state:state, evidence:status || '官方取件字段'});
    }
    Object.keys(o).slice(0, 100).forEach(function (k) { if (typeof o[k] === 'object') parseNode(o[k], station, depth + 1); });
  }
  function consume(raw) {
    try {
      if (typeof raw === 'string') { if (raw.length > 1500000) return; raw = raw.trim().replace(/^[\w.$]+\s*\(/, '').replace(/\);?\s*$/, ''); raw = JSON.parse(raw); }
      if (!raw || typeof raw !== 'object') return;
      var ret = JSON.stringify(raw.ret || '');
      if (/FAIL|ERROR|EXPIRED|INVALID/.test(ret) || raw.success === false) return;
      visited = 0; parseNode(raw, '', 0); responses++;
    } catch (_) {}
  }
  function allowed(raw) {
    try {
      var u = new URL(raw, location.href);
      if (u.protocol !== 'https:' || u.username || u.password || (u.port && u.port !== '443')) return false;
      if (provider === 'taobao') return /(^|\.)taobao\.com$/.test(u.hostname) && /mtop\.(?:cainiao\.pickup\.plus\.querymultistapackages4xy|cnwireless\.cnlogisticdetailservice\.wapquerylogisticpackagebymailno|taobao\.order\.queryboughtlistv2|taobao\.logisticstracedetailservice\.queryalltrace)/i.test(u.pathname);
      return /^(m\.pinduoduo\.net|api\.pinduoduo\.com|mobile\.yangkeduo\.com)$/.test(u.hostname) && /\/api\/(?:express_trackbox\/|aristotle\/order_list|express\/)/.test(u.pathname);
    } catch (_) { return false; }
  }
  if (window.fetch) {
    var oldFetch = window.fetch;
    window.fetch = function (input) {
      var url = typeof input === 'string' ? input : input && input.url;
      return oldFetch.apply(this, arguments).then(function (r) { if (allowed(url)) r.clone().text().then(consume).catch(function(){}); return r; });
    };
  }
  var oldOpen = XMLHttpRequest.prototype.open, oldSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) { this.__hytParcelAllowed = allowed(url); return oldOpen.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function () {
    if (this.__hytParcelAllowed) this.addEventListener('load', function () { try { consume(this.responseType === 'json' ? this.response : this.responseText); } catch (_) {} });
    return oldSend.apply(this, arguments);
  };
  // MTOP may use JSONP. Wrap only its explicit callback before the request script is attached.
  var oldAppend = Node.prototype.appendChild, oldInsert = Node.prototype.insertBefore;
  function watchScript(node) {
    try {
      if (!node || node.tagName !== 'SCRIPT' || !allowed(node.src)) return;
      var name = new URL(node.src).searchParams.get('callback');
      if (!name || !/^[A-Za-z_$][\w$]{0,100}$/.test(name)) return;
      var fn = window[name];
      if (typeof fn === 'function' && !fn.__hytWrapped) {
        var wrapped = function (data) { consume(data); return fn.apply(this, arguments); };
        wrapped.__hytWrapped = true; window[name] = wrapped;
      }
    } catch (_) {}
  }
  Node.prototype.appendChild = function (node) { watchScript(node); return oldAppend.apply(this, arguments); };
  Node.prototype.insertBefore = function (node) { watchScript(node); return oldInsert.apply(this, arguments); };
  function visible(el) { return !!(el && el.getClientRects().length && getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden'); }
  function authPhase() {
    if (/captcha|punish|verify/.test(location.pathname)) return 'verify';
    if (/login|passport/.test(location.hostname + location.pathname)) return 'login';
    if (Array.from(document.querySelectorAll('iframe')).some(function (f) { return visible(f) && /login|passport|captcha|verify/.test(f.src); })) return 'login';
    var fields = Array.from(document.querySelectorAll('input')).filter(function(e){ return visible(e) && /^(password|tel|text|number)$/.test(e.type); });
    if (fields.length && /登录|验证码|手机号码/.test((document.body && document.body.innerText || '').slice(0, 8000))) return 'login';
    return '';
  }
  function dom() {
    var groups = provider === 'pinduoduo' ? document.querySelectorAll('[class*="package-list-wrapper"] .package-list-picking') : document.querySelectorAll('[class^="stations--"],[class*=" stations--"]');
    groups.forEach(function (g) {
      var st = g.querySelector('.station-name,[class^="stationName--"],[data-role="station"]');
      var station = clean(st && st.textContent);
      var fields = provider === 'pinduoduo' ? Array.from(g.querySelectorAll('.package-code-value')) : Array.from(g.querySelectorAll('span,div,p,b,strong')).filter(function(e){return !e.children.length && /^(取件码|提货码|取货码)/.test(clean(e.textContent));});
      fields.forEach(function (e) {
        var c = code(clean(e.textContent));
        if (!c && /^(取件码|提货码|取货码)[:：\s]*$/.test(clean(e.textContent))) c = code(clean(e.nextElementSibling && e.nextElementSibling.textContent));
        if (c && !Array.from(records.values()).some(function(r){return r.code === c && r.station === station;})) put({id:'shelf:'+station+':'+c, code:c, station:station, tracking:'', courier:'', title:'', state:'pending', evidence:'官方待取列表'});
      });
    });
    explicitEmpty = Array.from(document.querySelectorAll('[class*="package-none-container"],[class*="empty--"],[class*="emptyTip--"]')).some(function (e) { return /暂无待取|没有待取|无待取包裹|暂无包裹/.test(clean(e.textContent)); });
    if (provider === 'pinduoduo' && window.rawData && window.rawData.data) { visited = 0; parseNode(window.rawData.data, '', 0); }
  }
  window.HytParcel = {
    consume:consume,
    read:function () {
      var auth = authPhase();
      if (auth) return {version:2,provider:provider,phase:auth,items:[],orders:[]};
      dom();
      return {version:2,provider:provider,phase:records.size ? 'partial' : explicitEmpty ? 'empty' : 'loading',items:Array.from(records.values()),orders:Array.from(orderLinks).slice(0,30)};
    }
  };
})();
