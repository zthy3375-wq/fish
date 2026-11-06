import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';
import {it,expect,vi} from 'vitest';
import {createSchoolPageReport,reportJSON,validateObservation} from '../src/services/academic-diagnostics';
import {previewZhengfangTimetable} from '../src/services/academic-adapters/zhengfang-timetable';
import {defaultState,flatten,backup,restoreBackup} from '../src/domain/schedule';
import {saveSchoolPagePreview,isSchoolPageSemester} from '../src/services/school-page-import';
const reader=readFileSync('android/app/src/main/assets/academic-diagnostic-reader.js','utf8');
const grid=`<div>学生姓名 PRIVATE_STUDENT，学号 PRIVATE_ID</div><input type="password" value="PRIVATE_PASSWORD"><table id="kbgrid_table_0"><tr><td class="td_wrap" id="1-1"><div class="timetable_con text-left"><span class="title"><font>结构测试课程</font></span><p><font>时间</font><font>(1-2节)1-16周(单)</font></p><p><font>测试教室</font></p><p><font>测试教师</font></p></div></td></tr></table>`;
function page(html=grid,url='https://jwgl.hdc.edu.cn/kbcx/example'){
 const dom=new JSDOM(html,{url,runScripts:'outside-only'});
 Object.defineProperty(dom.window.document,'cookie',{get(){throw Error('cookie must not be read')}});
 const fetch=vi.fn();dom.window.fetch=fetch;
 Object.defineProperty(dom.window.HTMLInputElement.prototype,'value',{get(){throw Error('input must not be read')}});
 return {dom,fetch,read:(collect=false)=>{const value=dom.window.eval(`(${reader})(${collect})`);if(typeof value!=="string")throw Error("Expected structural JSON");return JSON.parse(value)}};
}
it('detects real HTML shapes with synthetic DOM, without course contents in structural output',()=>{
 const p=page();const result=p.read();
 expect(result.observation).toMatchObject({container:'zf-grid',recordCount:1,invalidCount:0,fields:{courseName:true,teacher:true,room:true,weekday:true,periods:true,weeks:true}});
 expect(JSON.stringify(result)).not.toContain('测试课程');expect(JSON.stringify(result)).not.toContain('PRIVATE');expect(result.kbList).toBeUndefined();expect(p.fetch).not.toHaveBeenCalled();p.dom.window.close();
});
it('extracts only whitelisted course fields after explicit collection, never identity or authentication data',()=>{
 const p=page();const result=p.read(true);expect(result.kbList[0]).toEqual({kcmc:'结构测试课程',xm:'测试教师',cdmc:'测试教室',xqj:'1',jcs:'1-2',zcd:'1-16周(单)'});
 expect(JSON.stringify(result)).not.toContain('PRIVATE');p.dom.window.close();
});
it.each(['https://jwgl.hdc.edu.cn/xtgl/login_slogin.html','https://evil.invalid/','http://jwgl.hdc.edu.cn/kbcx/'])('does not inspect login or untrusted origin: %s',url=>{
 const p=page(grid,url);expect(p.read(true)).toMatchObject({observation:{container:'unrecognized',recordCount:0},kbList:[]});p.dom.window.close();
});
it('supports documented list markup and custom weeks',()=>{
 const p=page(`<table id="kblist_table"><tbody></tbody><tbody><tr><td>1-2节</td><td><span class="title">列表测试</span><p><font>周数：1,3,5周</font></p><p><font>上课地点：位置</font></p><p><font>教师 ：教师甲</font></p></td></tr></tbody></table>`);
 const result=p.read(true);expect(result.observation.container).toBe('zf-list');expect(result.kbList[0]).toMatchObject({jcs:'1-2',zcd:'1,3,5周',xqj:'1',xm:'教师甲'});p.dom.window.close();
});
it('reads only kbList course fields and flags unsupported practice arrangements without dumping them',()=>{
 const p=page('');p.dom.window.kbList=[{kcmc:'JSON课程',xm:'教师',cdmc:'位置',xqj:2,jcs:'3-4',zcd:'2-16周(双)',token:'PRIVATE_TOKEN',student:'PRIVATE_ID'}];
 p.dom.window.sjkList=[{identity:'PRIVATE_ID'}];
 expect(p.read().observation.specialArrangements).toBe(true);expect(JSON.stringify(p.read(true))).not.toContain('PRIVATE');p.dom.window.close();
});
it('reports malformed visible records rather than pretending a partial timetable is complete',()=>{
 const p=page(grid.replace('(1-2节)1-16周(单)','不支持的课程时间'));
 expect(p.read().observation).toMatchObject({recordCount:0,invalidCount:1});p.dom.window.close();
});
it('filters native report properties and bounds all exposed structures',()=>{
 const p=page();const observation=p.read().observation;p.dom.window.close();
 const clean=reportJSON({...createSchoolPageReport(observation),password:'PRIVATE',kbList:[{name:'PRIVATE'}],observation:{...observation,student:'PRIVATE'}});
 expect(clean).not.toContain('PRIVATE');expect(JSON.parse(clean)).toMatchObject({pageRead:true,automaticSync:false,thirdPartySyncAuthorized:false});
 expect(()=>validateObservation({...observation,recordCount:10000000})).toThrow('超限');
 expect(()=>validateObservation({...observation,fields:{...observation.fields,teacher:'PRIVATE'}})).toThrow();
});
it('full synthetic HTML to preview to isolated persistence model preserves prior personal courses and backups',()=>{
 const p=page();const data=p.read(true);p.dom.window.close();const state=defaultState();
 const result=previewZhengfangTimetable({kbList:data.kbList},{semester:state.semesters[0],timeTable:state.timeTables[0],existing:[]});
 const existing=structuredClone(result.preview.courses[0]);existing.name='原个人课程';state.courses=[existing];
 const before=structuredClone(state);expect(()=>saveSchoolPagePreview(state,result,false)).toThrow('核对');expect(state).toEqual(before);
 const id=saveSchoolPagePreview(state,result,true);expect(isSchoolPageSemester(id)).toBe(true);
 expect(state.courses[0]).toEqual(before.courses[0]);expect(state.semesters[0]).toEqual(before.semesters[0]);
 expect(flatten(state.courses,id,state.timeTables[0])[0].weeks).toEqual([1,3,5,7,9,11,13,15]);
 expect(restoreBackup(backup(state))).toEqual(state);
});
it('blocks partial/empty/conflicting previews without replacing any local data',()=>{
 const state=defaultState(),before=structuredClone(state),p=page();
 const result=previewZhengfangTimetable({kbList:p.read(true).kbList},{semester:state.semesters[0],timeTable:state.timeTables[0],existing:[]});p.dom.window.close();
 for(const patch of [{errors:['unknown']},{courses:[]},{issues:['conflict']}]){
  expect(()=>saveSchoolPagePreview(state,{...result,preview:{...result.preview,...patch}},true)).toThrow();expect(state).toEqual(before);
 }
});
