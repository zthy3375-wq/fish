(function () {
  'use strict';
  if (location.origin !== 'https://m.pinduoduo.net' || location.pathname !== '/mdkd/package') return false;
  // Keep any visible login/verification form intact. A React root or empty card is not a login result.
  var fields = document.querySelectorAll('input,textarea,[contenteditable="true"]');
  for (var i = 0; i < fields.length; i++) {
    var field = fields[i];
    if (!/^(hidden|checkbox|radio|button|submit)$/.test(field.type || '') && field.getClientRects().length) return false;
  }
  var root = document.querySelector('[class*="identification-code-container"]');
  var img = root && root.querySelector('.identification-code-img');
  if (img && img.complete && img.naturalWidth > 0) return true;
  if (root && root.querySelector('.identification-qr-code-svg')) return true;
  var pending = document.querySelector('[class*="package-list-wrapper"] .package-list-picking');
  if (pending && pending.textContent.trim() && !/^加载中[.。…]*$/.test(pending.textContent.trim())) return true;
  var empty = document.querySelector('[class*="package-none-container"]');
  return !!(empty && /暂无|没有|无待取/.test(empty.textContent));
})()
