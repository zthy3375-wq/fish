(function(){'use strict';const text=(v,max=150)=>typeof v==='string'?v.trim().slice(0,max):'';function error(code){throw Error(code)}
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

try{const parsed=htmlTimetable(document);const year=document.querySelector('#xnm')?.value,code=document.querySelector('#xqm')?.value;const kbList=parsed?.kbList||[];return JSON.stringify({observation:{termYear:year,termCode:code,invalidCount:0,specialArrangements:false,frameLimit:false},kbList,practice:(parsed?.sjkList||[]).map(p=>({name:p.kcmc,teacher:p.xm,weeks:p.zcd}))})}catch{return JSON.stringify({observation:{invalidCount:1},kbList:[],practice:[]})}})