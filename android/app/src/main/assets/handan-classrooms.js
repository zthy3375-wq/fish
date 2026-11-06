async function(operation, query) {
  'use strict';
  // Handan's N2155 HTML + deployed kxcdlb.js and live JSON verified 2026-11-06.
  // Read-only allowlist: no reservation, export, mutation or credential access.
  const origin='https://jwgl.hdc.edu.cn', base='/cdjy/', code='N2155';
  const allowed=new Set(['cdjy_cxKxcdlb.html','cdjy_cxXqjc.html','cdjy_cxQtlb.html','cdjy_cxDateInforma.html','cdjy_cxAtyycdSchedule.html']);
  const known=new Set(['NETWORK','HTTP','FORBIDDEN','EXPIRED','SCHEMA','LIMIT','DATE','FILTER','CALENDAR']);
  const fail=c=>{throw Error(c)};
  const text=(v,n=150)=>typeof v==='string'?v.trim().slice(0,n):typeof v==='number'?String(v):'';
  const int=(v,a,b)=>Number.isInteger(Number(v))&&Number(v)>=a&&Number(v)<=b?Number(v):fail('SCHEMA');
  const list=(v,max)=>Array.isArray(v)&&v.length<=max?v:fail('SCHEMA');
  const day=v=>/^20\d{2}-\d{2}-\d{2}$/.test(v||'')&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v?v:fail('DATE');
  const time=v=>/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(v||'')?v:fail('SCHEMA');
  async function get(action,params={},html=false){
    if(!allowed.has(action))fail('SCHEMA');
    const u=new URL(base+action,origin);u.search=new URLSearchParams({...params,gnmkdm:code}).toString();
    const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),12000);
    try{
      const r=await fetch(u.href,{credentials:'same-origin',cache:'no-store',signal:ctl.signal,headers:{'X-Requested-With':'XMLHttpRequest'}});
      if(new URL(r.url).origin!==origin||/\/xtgl\/login/.test(r.url))fail('EXPIRED');
      if(r.status===403)fail('FORBIDDEN');if(!r.ok)fail('HTTP');
      const s=await r.text();if(s.length>2500000)fail('LIMIT');
      if(/<input[^>]+(?:type=["']password|id=["']mm)/i.test(s))fail('EXPIRED');
      if(html)return new DOMParser().parseFromString(s,'text/html');
      try{return JSON.parse(s)}catch{fail('SCHEMA')}
    }catch(e){if(known.has(e.message))throw e;fail('NETWORK')}finally{clearTimeout(timer)}
  }
  // The school overrides Array.filter/some to pass (index,value), not ES (value,index).
  // Use explicit loops inside this untrusted page realm; do not patch school globals.
  function options(doc,id){const out=[];for(const o of list(Array.from(doc.querySelectorAll('#'+id+' option')),150)){if(o.value&&text(o.textContent))out.push({id:o.value,name:text(o.textContent)})}return out}
  async function dates(term,week,weekday){const d=list(await get('cdjy_cxDateInforma.html',{...term,zcd:String(2**(week-1)),xqj:String(weekday)}),7);if(d.length!==1)fail('CALENDAR');return day(d[0])}
  async function context(){
    const doc=await get('cdjy_cxKxcdlb.html',{layout:'default'},true);
    const terms=options(doc,'dm_cx'),campuses=options(doc,'xqh_id');
    if(!terms.length||!campuses.length)fail('SCHEMA');
    const termId=query.xnm&&query.xqm?`${query.xnm}-${query.xqm}`:doc.querySelector('#dm_cx')?.value;
    if(!terms.find(t=>t.id===termId))fail('FILTER');
    const [xnm,xqm]=termId.split('-');if(!/^20\d{2}$/.test(xnm)||!['3','12','16'].includes(xqm))fail('FILTER');
    const campusId=query.campusId||doc.querySelector('#xqh_id')?.value;
    if(!campuses.find(c=>c.id===campusId))fail('FILTER');
    const term={xnm,xqm},params={...term,xqh_id:campusId};
    const meta=await get('cdjy_cxXqjc.html',params),cal=await get('cdjy_cxQtlb.html',{...params,flag:'0'});
    if(!cal.dqzcxq)fail('CALENDAR');
    const weeks=[];for(const w of list(cal.nxqzcList,53))if(String(w.zczt)!=='0')weeks.push(int(w.dxqzc,1,53));
    if(!weeks.length)fail('CALENDAR');
    const periods=list(meta.jcList,24).map(p=>{const [start,end]=text(p.SJD).split('-');if(time(end)<=time(start))fail('SCHEMA');return {number:int(p.JCMC,1,24),start:time(start),end:time(end)}}).sort((a,b)=>a.number-b.number);
    if(!periods.length)fail('SCHEMA');for(let i=0;i<periods.length;i++)if(periods[i].number!==i+1)fail('SCHEMA');
    const buildings=list(meta.lhList,300).map(b=>({id:text(b.JXLDM,80),name:text(b.JXLMC)}));for(const b of buildings)if(!b.id||!b.name)fail('SCHEMA');
    return {term,campusId,terms,campuses,buildings,periods,weeks,weekStartDate:await dates(term,1,1),minDate:day(cal.dqzcxq.ZXRQ),maxDate:day(cal.dqzcxq.ZDRQ)};
  }
  function room(r){
    const value={id:text(r.cd_id,100),termRoomId:text(r.cdxqxx_id,100),number:text(r.cdbh,100),name:text(r.cdmc),buildingId:text(r.lh,80),building:text(r.jxlmc)||'学校未提供楼号',campus:text(r.xqmc),type:text(r.cdlbmc),capacity:r.zws==null||r.zws===''?null:int(r.zws,0,100000)};
    if(!value.id||!value.name)fail('SCHEMA');return value;
  }
  try{
    if(location.origin!==origin||document.querySelector('input[type=password]'))fail('EXPIRED');
    const ctx=await context();let data;
    if(operation==='rooms-options')data=ctx;
    else{
      const date=day(query.date),week=int(query.week,1,53),weekday=int(query.weekday,1,7);
      if(!ctx.weeks.includes(week)||date<ctx.minDate||date>ctx.maxDate||await dates(ctx.term,week,weekday)!==date)fail('DATE');
      if(query.buildingId&&!ctx.buildings.find(b=>b.id===query.buildingId))fail('FILTER');
      if(operation==='rooms-query'){
        const start=int(query.startPeriod,1,ctx.periods.length),end=int(query.endPeriod,start,ctx.periods.length);
        const params={...ctx.term,xqh_id:ctx.campusId,lh:query.buildingId||'',jyfs:'0',zcd:String(2**(week-1)),xqj:String(weekday),jcd:String(2**end-2**(start-1)),cdlb_id:'',cdejlb_id:'',qszws:'',jszws:'',cdmc:'',cdjylx:'',sfbhkc:'','queryModel.showCount':'100','queryModel.sortName':'cdbh','queryModel.sortOrder':'asc',_search:'false'};
        const rooms=[],seen=new Set();let total=0,pages=1;
        for(let page=1;page<=pages;page++){
          const r=await get('cdjy_cxKxcdlb.html',{...params,doType:'query','queryModel.currentPage':String(page)});
          const items=list(r.items,100),count=int(r.totalCount,0,5000),next=int(r.totalPage,0,50);
          if(page===1){total=count;pages=Math.max(1,next)}else if(count!==total||Math.max(1,next)!==pages)fail('SCHEMA');
          if(items.length===0&&page<pages)fail('SCHEMA');
          for(const raw of items){const item=room(raw);if(seen.has(item.id))fail('SCHEMA');seen.add(item.id);rooms.push(item)}
        }
        if(rooms.length!==total)fail('SCHEMA');
        data={rooms,total,query:{date,week,weekday,campusId:ctx.campusId,buildingId:query.buildingId||'',...ctx.term,startPeriod:start,endPeriod:end},periods:ctx.periods};
      }else if(operation==='rooms-day'){
        if(!text(query.roomId,100)||!text(query.roomName))fail('FILTER');
        const raw=await get('cdjy_cxAtyycdSchedule.html',{...ctx.term,xqh_id:ctx.campusId,rq:date,cdmc:text(query.roomName),cdjylx:'',sfbhkc:''});
        const periods=list(raw.jcList,24),rows=list(raw.scheduleList,5000),r=rows.find(r=>String(r.cd_id)===query.roomId);
        if(!r)fail('SCHEMA');
        const slots=ctx.periods.map(p=>{const jp=periods.find(j=>Number(j.jcmc)===p.number);if(!jp||Number(jp.jcm)!==2**(p.number-1))return {...p,state:'unknown'};
          // School's own loadSchedule renders absent rs_<bit> as free within its query range.
          const value=r['rs_'+jp.jcm];return {...p,state:value==null||value===''?'free':typeof value==='string'?'occupied':'unknown'};
        });
        data={roomId:query.roomId,date,slots};
      }else fail('FILTER');
    }
    window.__handanResult={session:'valid',classrooms:{status:'ok',data,updatedAt:new Date().toISOString()}};
  }catch(e){const code=known.has(e.message)?e.message:'SCHEMA';window.__handanResult={session:code==='EXPIRED'?'expired':'valid',classrooms:{status:'error',code}}}
}
