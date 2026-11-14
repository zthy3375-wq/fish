async function(operation, requestedTerm) {
  'use strict';
  // Compiled, same-origin read-only adapter. Candidate URLs are not asserted to be Handan contracts.
  const origin='https://jwgl.hdc.edu.cn';
  const result={session:'valid',modules:{},verification:'device-validation-required'};
  const controlled=new Set(['NETWORK','HTTP','SCHEMA','EMPTY','TERM','EXPIRED','LIMIT','TIMETABLE_JSON','COURSE_FIELDS']);
  const text=(v,max=150)=>typeof v==='string'?v.trim().slice(0,max):'';
  function error(code){throw new Error(code)}
  async function request(path,form){
    const url=new URL(path,origin);if(url.origin!==origin||!/^\/(kbcx|cjcx|kwgl|xsxxxggl)\//.test(url.pathname))error('SCHEMA');
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
    try{
      const response=await fetch(url.href,{method:form?'POST':'GET',credentials:'same-origin',cache:'no-store',signal:controller.signal,
        headers:form?{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8','X-Requested-With':'XMLHttpRequest'}:{},
        body:form?new URLSearchParams(form).toString():undefined});
      if(new URL(response.url).origin!==origin||/\/xtgl\/login/.test(response.url))error('EXPIRED');
      if(!response.ok){const e=new Error('HTTP');e.httpStatus=response.status;e.stage=form?'query':'page';throw e;}
      const data=await response.text();if(data.length>2500000)error('LIMIT');
      if(/<input[^>]+(?:type=["']password|id=["']mm)/i.test(data))error('EXPIRED');
      return data;
    }catch(e){if(controlled.has(e.message))throw e;error('NETWORK')}finally{clearTimeout(timer)}
  }
  async function json(path,form){try{return JSON.parse(await request(path,form))}catch(e){if(controlled.has(e.message))throw e;error('SCHEMA')}}
  function menu(prefix,candidate){
    for(const el of document.querySelectorAll('a[href],a[data-url],a[onclick]')){
      for(const value of [el.getAttribute('href'),el.getAttribute('data-url'),el.getAttribute('onclick')]){
        if(prefix==='/kbcx/'&&!(value||'').includes('/kbcx/xskbcx_'))continue;
        const match=(value||'').match(new RegExp('('+prefix+'[a-zA-Z0-9_]+\\.html(?:\\?[^\\s\'"<>)]*)?)'));
        if(match){const u=new URL(match[1],origin);if(u.origin===origin){
          const code=[el.id,el.getAttribute('data-gnmkdm'),el.getAttribute('onclick'),el.closest('[id^=N]')?.id].map(v=>(v||'').match(/\bN\d{4,12}\b/)?.[0]).find(Boolean);
          if(code&&!u.searchParams.has('gnmkdm'))u.searchParams.set('gnmkdm',code);
          return u.pathname+u.search;
        }}
      }
    }return candidate;
  }
  async function module(name,task){
    try{const data=await task();result.modules[name]={status:'ok',data,updatedAt:new Date().toISOString()}}
    catch(e){const code=controlled.has(e.message)?e.message:'SCHEMA';result.modules[name]={status:'error',code,httpStatus:Number.isInteger(e.httpStatus)?e.httpStatus:undefined,stage:e.stage};if(code==='EXPIRED')result.session='expired'}
  }
  const timetablePage=menu('/kbcx/','/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default');
  let doc,term;
  async function context(){
    if(term)return term;
    doc=new DOMParser().parseFromString(await request(timetablePage),'text/html');
    const year=doc.querySelector('#xnm,[name=xnm]')?.value,code=doc.querySelector('#xqm,[name=xqm]')?.value;
    if(!/^20\d{2}$/.test(year||'')||!['3','12'].includes(code))error('TERM');
    const years=Array.from(doc.querySelectorAll('#xnm option')).map(o=>o.value).filter(y=>/^20\d{2}$/.test(y));
    result.modules.semesters={status:'ok',data:years.flatMap(xnm=>['3','12'].map(xqm=>({xnm,xqm}))),updatedAt:new Date().toISOString()};
    const xnm=requestedTerm?.xnm||year,xqm=requestedTerm?.xqm||code;
    if(!/^20\d{2}$/.test(xnm)||!['3','12'].includes(xqm)||years.length&&!years.includes(xnm))error('TERM');
    term={xnm,xqm};return term;
  }
  function rows(raw){
    if(!Array.isArray(raw)||raw.length>500)error('SCHEMA');
    return raw.map(r=>{
      if(!r||!r.kcmc||!/^\d{1,2}(?:-\d{1,2})?(?:节)?$/.test(String(r.jcs).trim())||!/^[1-7]$/.test(String(r.xqj))||!r.zcd)error('COURSE_FIELDS');
      return {kcmc:text(r.kcmc),xm:text(r.xm,100),cdmc:text(r.cdmc),xqj:String(r.xqj),jcs:String(r.jcs).trim().replace(/节$/,''),zcd:text(r.zcd,250)};
    });
  }
  // Confirmed against Handan's authenticated HTML on 2026-11-06. No student data is embedded.
  function htmlTimetable(page){
    if(!page.querySelector('#kbgrid_table_0'))return null;
    const kbList=[],sjkList=[];
    for(const cell of page.querySelectorAll('#kbgrid_table_0 td.td_wrap'))for(const c of cell.querySelectorAll('.timetable_con')){
      const p=c.querySelectorAll('p');
      const value=n=>(p[n]?.querySelector(':scope > font')?.textContent||p[n]?.textContent||'').trim();
      const m=value(0).match(/[（(](\d{1,2}(?:-\d{1,2})?)节[）)]\s*(.+)$/);
      if(!m)error('COURSE_FIELDS');
      kbList.push({kcmc:text(c.querySelector('.title')?.textContent).replace(/[●★○■☆◆]/g,''),xm:text(value(2)),cdmc:text(value(1)),xqj:cell.id.split('-')[0],jcs:m[1],zcd:m[2]});
    }
    for(const footer of page.querySelectorAll('#kbgrid_table_0 .timetable_title')){
      const content=footer.textContent.trim();if(!content.startsWith('实践课程：'))continue;
      for(const part of content.replace(/^实践课程：/,'').split(/[;；]/).filter(x=>x.trim())){
        const m=part.trim().match(/^(.+?)■(.+?)[（(]共\d+周[）)]\/(.+周)$/);
        if(!m)error('COURSE_FIELDS');sjkList.push({kcmc:text(m[1]),xm:text(m[2]),zcd:text(m[3],250)});
      }
    }
    return kbList.length||sjkList.length?{kbList,sjkList}:null;
  }
  async function timetable(){
    const t=await context();
    // This is the standard V9 query form; success requires the actual kbList schema.
    const path=new URL(timetablePage,origin);path.searchParams.delete('layout');path.searchParams.delete('su');path.pathname=path.pathname.replace(/xskbcx_cx(?:XsgrkbIndex|XskbcxIndex)\.html$/, 'xskbcx_cxXsgrkb.html');path.searchParams.set('gnmkdm',path.searchParams.get('gnmkdm')||'N253508');
    let raw=htmlTimetable(doc);
    if(t.xnm!==doc.querySelector('#xnm')?.value||t.xqm!==doc.querySelector('#xqm')?.value)raw=null;
    if(!raw)try{raw=await json(path.pathname+path.search,{...t,kzlx:'ck',xsdm:doc.querySelector('#xsdm')?.value||'',kclbdm:doc.querySelector('#kclbdm')?.value||'',kclxdm:doc.querySelector('#kclxdm')?.value||''})}
    catch(e){
      // Verified old device path: rendered grid fallback, no user detection/import step.
      if(t.xnm!==doc.querySelector('#xnm')?.value||t.xqm!==doc.querySelector('#xqm')?.value)throw e;
      raw=htmlTimetable(doc);
      if(!raw){if(e.message==='SCHEMA')error('TIMETABLE_JSON');throw e;}
    }
    if(typeof raw==='string'){try{raw=JSON.parse(raw)}catch{error('TIMETABLE_JSON')}}
    if(!raw||!Array.isArray(raw.kbList))error('TIMETABLE_JSON');
    if(raw.xsxx?.XNM&&String(raw.xsxx.XNM)!==t.xnm||raw.xsxx?.XQM&&String(raw.xsxx.XQM)!==t.xqm)error('TERM');
    const xs=raw.xsxx||{};
    result.modules.profile={status:'ok',data:{name:text(xs.XM||xs.xm,60),major:text(xs.ZYMC||xs.zymc),className:text(xs.BJMC||xs.bjmc),year:text(xs.NJDM_ID||xs.njdm_id,10)},updatedAt:new Date().toISOString()};
    const kbList=rows(raw.kbList),practice=[];
    if(raw.sjkList!=null&&!Array.isArray(raw.sjkList))error('SCHEMA');
    for(const p of raw.sjkList||[]){
      if(p.jcs&&p.xqj&&p.zcd)kbList.push(...rows([p]));
      else if(p.kcmc)practice.push({name:text(p.kcmc),teacher:text(p.xm||p.jsxm),weeks:text(p.zcd||p.qsjsz,250)});
      else error('SCHEMA');
    }
    if(!kbList.length&&!practice.length)error('EMPTY');
    let periods;
    try{
      const rjc=await json('/kbcx/xskbcx_cxRjc.html?gnmkdm='+encodeURIComponent(path.searchParams.get('gnmkdm')),{...t,xqh_id:doc.querySelector('#xqh_id')?.value||''});
      if(Array.isArray(rjc)&&rjc.length>0&&rjc.length<=24){
        const slots=rjc.map(r=>({number:Number(r.jcmc),start:text(r.qssj,5),end:text(r.jssj,5)})).sort((a,b)=>a.number-b.number);
        if(slots.every((s,i)=>s.number===i+1&&/^([01]\d|2[0-3]):[0-5]\d$/.test(s.start)&&/^([01]\d|2[0-3]):[0-5]\d$/.test(s.end)&&s.end>s.start))periods=slots;
      }
    }catch{} // Optional school times never block the timetable; previously supplied 13 periods remain the fallback.
    return {term:t,kbList,practice,periods,endpoint:path.pathname,method:path.pathname==='/kbcx/xskbcx_cxXskbcxIndex.html'?'HTML':'POST'};
  }
  async function paged(path,form){
    const all=[];let count=1,expected=null;
    for(let page=1;page<=count;page++){
      const data=await json(path,{...form,'queryModel.showCount':'100','queryModel.currentPage':String(page),'queryModel.sortName':'','queryModel.sortOrder':'asc'});
      if(!data||!Array.isArray(data.items))error('SCHEMA');
      const total=Number(data.totalCount??data.totalResult??data.items.length);
      const pages=Number(data.totalPage??Math.ceil(total/100));
      if(!Number.isInteger(pages)||pages>20||pages<0||!Number.isInteger(total)||total<0||total>2000)error('LIMIT');count=Math.max(1,pages);
      if(data.totalCount!=null||data.totalResult!=null){if(expected!==null&&expected!==total)error('SCHEMA');expected=total;}
      if(page<count&&data.items.length===0)error('SCHEMA');
      all.push(...data.items);if(all.length>2000)error('LIMIT');
    }if(expected!==null&&all.length!==expected)error('SCHEMA');return all;
  }
  try{
    if(location.origin!==origin||document.querySelector('input[type=password]'))error('EXPIRED');
    if(operation==='syncAll'||operation==='timetable'||operation==='profile')await module('timetable',timetable);
    if(operation==='semesters')await module('semesters',async()=>{await context();return result.modules.semesters.data});
    if(operation==='syncAll'||operation==='grades')await module('grades',async()=>{
      const t=await context();
      const u=new URL(menu('/cjcx/','/cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005'),origin);u.searchParams.set('doType','query');if(!u.searchParams.has('gnmkdm'))u.searchParams.set('gnmkdm','N305005');const path=u.pathname+u.search;
      const list=await paged(path,{xnm:requestedTerm?.xnm||'',xqm:requestedTerm?.xqm||'',_search:'false',nd:String(Date.now())});
      return list.map(g=>{
        if(!g.kcmc)error('SCHEMA');
        const number=v=>v!==null&&v!==undefined&&String(v).trim()!==''&&Number.isFinite(Number(v))&&Number(v)>=0?Number(v):null;
        return {name:text(g.kcmc),scoreText:g.cj==null?'':String(g.cj).slice(0,40),credit:number(g.xf),gpa:number(g.jd),term:text(g.xnmmc||g.xnm,20)+' '+text(g.xqmmc||g.xqm,20),kind:text(g.kcxzmc||g.kclbmc),courseCode:text(g.kch),recordId:text(g.cjbh),year:text(g.xnm,10),termCode:text(g.xqm,10),examType:text(g.ksxzmc)};
      });
    });
    if(result.modules.grades?.status==='ok')result.modules.grades.scope=requestedTerm?.xnm?'term':'all';
    if(operation==='syncAll'||operation==='exams')await module('exams',async()=>{
      const t=await context();
      const u=new URL(menu('/kwgl/','/kwgl/kscx_cxXsksxxIndex.html?gnmkdm=N358105'),origin);u.searchParams.set('doType','query');if(!u.searchParams.has('gnmkdm'))u.searchParams.set('gnmkdm','N358105');const path=u.pathname+u.search;
      return (await paged(path,{...t,ksmcdmb_id:'',kch:'',_search:'false'})).map(e=>{
        if(!e.kcmc)error('SCHEMA');const value=text(e.kssj,100);const match=value.match(/(20\d{2}[-/]\d{2}[-/]\d{2})\s*(.*)/);
        return {name:text(e.kcmc),date:text(e.ksrq,20)||match?.[1]?.replaceAll('/','-')||'',time:match?.[2]||value,room:text(e.cdmc||e.kscd),seat:text(e.zwh,20)};
      });
    });
  }catch(e){result.session=e.message==='EXPIRED'?'expired':'unknown';result.error=controlled.has(e.message)?e.message:'SCHEMA'}
  if(result.modules.timetable?.code==='TIMETABLE_JSON')result.renderedPage={url:timetablePage,term};
  if(term) result.resolvedTerm=term;
  window.__handanResult=result;
}
