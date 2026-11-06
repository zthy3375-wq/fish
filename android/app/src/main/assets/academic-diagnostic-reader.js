(function(collect) {
  'use strict';
  const result={container:'unrecognized',fields:{courseName:false,teacher:false,room:false,weekday:false,periods:false,weeks:false},recordCount:0,invalidCount:0,specialArrangements:false,exportControl:false,frameLimit:false};
  const rows=[], documents=[];
  function term(doc){
    const year=doc.querySelector('select#xnm,select[name="xnm"]')?.value;
    const code=doc.querySelector('select#xqm,select[name="xqm"]')?.value;
    if(/^20\d{2}$/.test(year||'')&&['3','12'].includes(code)){result.termYear=year;result.termCode=code;}
  }
  function addDocument(doc,depth){
    if(!doc||depth>2||documents.length>=12){result.frameLimit=true;return;}
    try {
      const url=new URL(doc.location.href);
      if(url.protocol!=='https:'||url.hostname!=='jwgl.hdc.edu.cn'||(url.port&&url.port!=='443')||/\/xtgl\/login|\/cas\/|\/auth\//i.test(url.pathname))return;
      documents.push(doc);
      for(const frame of doc.querySelectorAll('iframe')){try{addDocument(frame.contentDocument,depth+1)}catch{}}
    }catch{}
  }
  addDocument(document,0);
  function value(node,max){const text=(node?.textContent||'').trim();if(text.length>max)throw Error('length');return text;}
  function append(row){
    if(rows.length>=500)throw Error('limit');
    if(typeof row.kcmc!=='string'||!row.kcmc.trim()||row.kcmc.length>150||typeof row.xm!=='string'||row.xm.length>100||typeof row.cdmc!=='string'||row.cdmc.length>150||typeof row.jcs!=='string'||row.jcs.length>20||typeof row.zcd!=='string'||row.zcd.length>250||!(/^[1-7]$/.test(String(row.xqj))))throw Error('shape');
    rows.push({kcmc:row.kcmc.trim(),xm:row.xm.trim(),cdmc:row.cdmc.trim(),xqj:String(row.xqj),jcs:row.jcs.trim(),zcd:row.zcd.trim()});
  }
  for(const doc of documents){
    try{
      const win=doc.defaultView;
      // Only this documented course collection is inspected; no window enumeration, storage or requests.
      if(Array.isArray(win.kbList)){
        result.container='kbList';term(doc);
        for(const row of win.kbList.slice(0,501)){try{append(row)}catch{result.invalidCount++}}
        result.specialArrangements=Array.isArray(win.sjkList)&&win.sjkList.length>0;
        break;
      }
      const grid=doc.querySelector('#kbgrid_table_0'), list=doc.querySelector('#kblist_table');
      if(!grid&&!list)continue;
      const useList=doc.querySelector('#shcPDF')?.dataset.type==='list'||!grid;
      result.container=useList?'zf-list':'zf-grid';term(doc);
      if(useList){
        const bodies=Array.from(list.querySelectorAll('tbody'));
        bodies.forEach((body,day)=>{
          if(day<1||day>7)return;let sections='';
          for(const tr of body.querySelectorAll('tr')){
            if(!tr.querySelector('.title'))continue;
            try{
              const cells=tr.querySelectorAll('td');if(cells.length>1)sections=value(cells[0],30).replace(/第|节|\s/g,'');
              const info=cells[cells.length-1],fonts=info.querySelectorAll('p font');
              append({kcmc:value(info.querySelector('.title'),150).replace(/[●★○]/g,''),xm:value(fonts[2],100).replace(/^教师\s*[:：]\s*/,''),cdmc:value(fonts[1],150).replace(/^上课地点\s*[:：]\s*/,''),xqj:day,jcs:sections,zcd:value(fonts[0],250).replace(/^周数\s*[:：]\s*/,'')});
            }catch{result.invalidCount++}
          }
        });
      }else{
        for(const cell of grid.querySelectorAll('td.td_wrap')){
          const day=String(cell.id).match(/^([1-7])-/)?.[1];
          for(const course of cell.querySelectorAll('.timetable_con')){
            try{
              const paragraphs=course.querySelectorAll('p');
              const info=value(paragraphs[0]?.querySelectorAll('font')[1]||paragraphs[0],300);
              const match=info.match(/[（(](\d{1,2}(?:-\d{1,2})?)节[）)]\s*(.+)$/);
              if(!match)throw Error('unknown-period-week');
              append({kcmc:value(course.querySelector('.title font')||course.querySelector('.title'),150).replace(/[●★○]/g,''),xm:value(paragraphs[2]?.querySelector('font'),100),cdmc:value(paragraphs[1]?.querySelector('font'),150),xqj:day,jcs:match[1],zcd:match[2]});
            }catch{result.invalidCount++}
          }
        }
      }
      // Only known export control existence, never labels/URLs or downloaded files.
      result.exportControl=!!doc.querySelector('#shcPDF, #export, #btn_export');
      break;
    }catch{result.invalidCount++}
  }
  result.recordCount=rows.length;
  for(const row of rows){
    result.fields.courseName ||= !!row.kcmc;
    result.fields.teacher ||= !!row.xm;
    result.fields.room ||= !!row.cdmc;
    result.fields.weekday ||= !!row.xqj;
    result.fields.periods ||= !!row.jcs;
    result.fields.weeks ||= !!row.zcd;
  }
  return JSON.stringify({observation:result,...(collect?{kbList:rows}:{})});
})
