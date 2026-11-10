/* Read the platform-generated code image, never manufacture an identity from a phone or parcel code. */
(function(){
  'use strict';
  if (!window.HytIdentity) {
    window.HytIdentity = { image:'', busy:false };
    var state = window.HytIdentity;
    state.capture = function(){
      if (state.busy || state.image) return;
      var root = document.querySelector('[class*="identity--"],[class*="identification-code-container"]');
      if (!root) return;
      var el = root.querySelector('img[class*="width-origin--"],img[class*="width-rotate--"],img.identification-code-img,svg.identification-qr-code-svg');
      if (!el) return;
      function paint(img) {
        try {
          var w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
          if (!w || !h || w > 2048 || h > 2048 || w * h > 2000000) return;
          var canvas = document.createElement('canvas'); canvas.width=w; canvas.height=h;
          var ctx=canvas.getContext('2d'); ctx.fillStyle='#fff'; ctx.fillRect(0,0,w,h); ctx.drawImage(img,0,0);
          var data=canvas.toDataURL('image/png'); if(data.length<1500000) state.image=data;
        } catch(_) {} finally { state.busy=false; }
      }
      if (el.tagName.toLowerCase()==='img') { if(el.complete && el.naturalWidth) paint(el); return; }
      var svg = new XMLSerializer().serializeToString(el);
      if (svg.length>300000 || /<script|<foreignObject|\bon\w+=|(?:href|url)\s*[=(]/i.test(svg)) return;
      state.busy=true;
      var uri=URL.createObjectURL(new Blob([svg],{type:'image/svg+xml'})), img=new Image();
      img.onload=function(){paint(img); URL.revokeObjectURL(uri);};
      img.onerror=function(){state.busy=false;URL.revokeObjectURL(uri);}; img.src=uri;
    };
  }
  window.HytIdentity.capture();
  return window.HytIdentity.image;
})()
