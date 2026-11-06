import type {SchoolGrade} from '../services/handan-academic-client';
export type GradeState='passed'|'failed'|'pending'|'unknown';
export interface GradeRecord extends SchoolGrade {key:string;state:GradeState;numeric:number|null;termLabel:string;termOrder:number|null;analysisKind:string}
export interface CourseGroup {key:string;name:string;records:GradeRecord[];ambiguous:boolean;state:GradeState;resolved:boolean;credit:number|null;creditTerm:string|null;representative:GradeRecord|null}
export interface GradeFilter {term:string;query:string;kind:string;band:string;state:string;sort:string}
export const defaultGradeFilter=():GradeFilter=>({term:'all',query:'',kind:'all',band:'all',state:'all',sort:'term'});
const clean=(v:unknown)=>typeof v==='string'?v.normalize('NFKC').trim():'';
const finite=(v:unknown)=>typeof v==='number'&&Number.isFinite(v)&&v>=0?v:null;
export function normalizeGrade(raw:unknown):SchoolGrade {
 const r=raw as SchoolGrade;if(!r||!clean(r.name)||r.name.length>150||typeof r.scoreText!=='string'||r.scoreText.length>40)throw Error('SCHEMA');
 const g:SchoolGrade={name:clean(r.name),scoreText:r.scoreText.trim(),credit:finite(r.credit),gpa:finite(r.gpa),term:clean(r.term).slice(0,60),kind:clean(r.kind).slice(0,150)};
 for(const k of ['courseCode','recordId','year','termCode','examType'] as const)if(clean(r[k]))g[k]=clean(r[k]).slice(0,150);
 if(typeof r.passed==='boolean')g.passed=r.passed;
 return g;
}
export function gradeValue(g:SchoolGrade):{state:GradeState;numeric:number|null} {
 const t=clean(g.scoreText);const n=/^\d+(?:\.\d+)?(?:分)?$/.test(t)?Number(t.replace(/分$/,'')):NaN;
 const numeric=Number.isFinite(n)&&n>=0&&n<=100?n:null;
 let state:GradeState=/^(|—|-|待公布|未公布|暂无|缓考|待考|未录入|未发布)$/.test(t)?'pending':numeric!==null?(numeric>=60?'passed':'failed'):/^(优秀|良好|中等|及格|合格|通过)$/.test(t)?'passed':/^(不及格|不合格|未通过|不通过)$/.test(t)?'failed':'unknown';
 if(typeof g.passed==='boolean'&&state!=='pending')state=state==='unknown'?(g.passed?'passed':'failed'):((state==='passed')===g.passed?state:'unknown');
 return {state,numeric};
}
export function gradeTerm(g:SchoolGrade):{label:string;order:number|null} {
 const raw=clean(g.term),year=clean(g.year)||raw.match(/20\d{2}/)?.[0];
 let season=clean(g.termCode);
 if(!season){if(/秋|第一|第1|[-–—]\d{4}\s*[- ]?1$/.test(raw)||/\s3$/.test(raw))season='3';else if(/春|第二|第2|[-–—]\d{4}\s*[- ]?2$/.test(raw)||/\s12$/.test(raw))season='12'}
 if(year&&/^20\d{2}$/.test(year)&&['3','12'].includes(season))return {label:`${year}–${Number(year)+1} ${season==='3'?'秋季':'春季'}`,order:Number(year)*10+(season==='3'?1:2)};
 return {label:raw||'学期未提供',order:null};
}
const signature=(g:SchoolGrade)=>JSON.stringify([g.courseCode||'',g.recordId||'',g.name,g.scoreText,g.credit,g.gpa,g.term,g.year||'',g.termCode||'',g.kind,g.examType||'',g.passed??null]);
export const bandOf=(r:GradeRecord)=>r.numeric===null?(r.state==='pending'?'pending':r.state==='unknown'?'unknown':'levels'):r.numeric<60?'0-59':r.numeric<70?'60-69':r.numeric<80?'70-79':r.numeric<90?'80-89':'90-100';
export const gradeBands=[['0-59','0–59'],['60-69','60–69'],['70-79','70–79'],['80-89','80–89'],['90-100','90–100'],['levels','等级/两级制'],['pending','待公布'],['unknown','未识别']] as const;
export function buildGradeReport(raw:unknown) {
 const source=Array.isArray(raw)?raw.slice(0,2000):[];
 const records:GradeRecord[]=[],seen=new Set<string>();let invalid=Array.isArray(raw)?Math.max(0,raw.length-2000):1,duplicates=0;
 for(const item of source){try{const g=normalizeGrade(item),key=signature(g);if(seen.has(key)){duplicates++;continue}seen.add(key);const term=gradeTerm(g);records.push({...g,key,...gradeValue(g),termLabel:term.label,termOrder:term.order,analysisKind:g.kind||'性质未提供'})}catch{invalid++}}
 // If any record lacks a code for a shared name, keep that whole name cluster uncertain.
 const missingCodeNames=new Set(records.filter(r=>!r.courseCode).map(r=>r.name));
 const grouped=new Map<string,GradeRecord[]>();
 for(const r of records){const key=missingCodeNames.has(r.name)?`name:${r.name}`:`code:${r.courseCode}`;const list=grouped.get(key)||[];list.push(r);grouped.set(key,list)}
 const groups:CourseGroup[]=[];
 for(const [key,list] of grouped){
  const kinds=new Set(list.map(r=>r.kind||'性质未提供'));
  if(kinds.size>1)for(const r of list)r.analysisKind='性质待核对';
  const ambiguous=key.startsWith('name:')&&list.length>1;
  const passed=list.filter(r=>r.state==='passed'),failed=list.some(r=>r.state==='failed');
  const state:GradeState=ambiguous?'unknown':passed.length?'passed':list.some(r=>r.state==='pending')?'pending':list.every(r=>r.state==='failed')?'failed':'unknown';
  const credits=new Set(passed.map(r=>r.credit));const credit=!ambiguous&&passed.length&&credits.size===1&&passed[0].credit!==null?passed[0].credit:null;
  // A retry is not silently replaced by its best or last score. Unknown school replacement rules => exclude from means.
  const published=list.filter(r=>r.state!=='pending');
  const representative=!ambiguous&&published.length===1?published[0]:null;
  const creditRecord=passed.length?[...passed].sort((a,b)=>(a.termOrder??Infinity)-(b.termOrder??Infinity))[0]:null;
  groups.push({key,name:list[0].name,records:list,ambiguous,state,resolved:!ambiguous&&passed.length>0&&failed,credit,creditTerm:creditRecord?.termLabel??null,representative});
 }
 const terms=[...new Set(records.map(r=>r.termLabel))].sort((a,b)=>{const x=records.find(r=>r.termLabel===a)!,y=records.find(r=>r.termLabel===b)!;return (x.termOrder??Infinity)-(y.termOrder??Infinity)||a.localeCompare(b,'zh-CN')});
 function summary(term='all'){
  const selected=groups.filter(g=>term==='all'||g.records.some(r=>r.termLabel===term));
  const representatives=selected.flatMap(g=>g.representative&&(term==='all'||g.representative.termLabel===term)?[g.representative]:[]);
  const nums=representatives.filter(r=>r.numeric!==null),weighted=nums.filter(r=>r.credit!==null&&r.credit>0),gpas=representatives.filter(r=>r.gpa!==null&&r.credit!==null&&r.credit>0);
  const weight=weighted.reduce((s,r)=>s+r.credit!,0),gpaWeight=gpas.reduce((s,r)=>s+r.credit!,0);
  const earned=groups.filter(g=>g.credit!==null&&(term==='all'||g.creditTerm===term));
  return {courses:selected.length,records:records.filter(r=>term==='all'||r.termLabel===term).length,numericCount:nums.length,weightedCount:weighted.length,gpaCount:gpas.length,excluded:selected.filter(g=>!g.representative).length,
   mean:nums.length?nums.reduce((s,r)=>s+r.numeric!,0)/nums.length:null,weightedMean:weight?weighted.reduce((s,r)=>s+r.numeric!*r.credit!,0)/weight:null,
   gpa:gpaWeight?gpas.reduce((s,r)=>s+r.gpa!*r.credit!,0)/gpaWeight:null,earnedCredits:earned.reduce((s,g)=>s+g.credit!,0),creditCount:earned.length,
   max:nums.length?Math.max(...nums.map(r=>r.numeric!)):null,min:nums.length?Math.min(...nums.map(r=>r.numeric!)):null};
 }
 return {records,groups,terms,summary,overview:summary(),semesters:terms.map(term=>({term,order:records.find(r=>r.termLabel===term)!.termOrder,...summary(term)})),invalid,duplicates,
  failures:groups.filter(g=>g.state==='failed'),resolved:groups.filter(g=>g.resolved),ambiguous:groups.filter(g=>g.ambiguous),unknown:groups.filter(g=>g.state==='unknown'),
  types:[...new Set(records.map(r=>r.analysisKind))].map(kind=>({kind,courses:groups.filter(g=>g.records[0].analysisKind===kind).length,credits:groups.filter(g=>g.credit!==null&&g.records[0].analysisKind===kind).reduce((s,g)=>s+g.credit!,0)}))};
}
export type GradeReport=ReturnType<typeof buildGradeReport>;
export function filterGradeRecords(records:GradeRecord[],f:GradeFilter):GradeRecord[]{
 const q=clean(f.query).toLocaleLowerCase();return records.filter(r=>(f.term==='all'||r.termLabel===f.term)&&(!q||r.name.toLocaleLowerCase().includes(q))&&(f.kind==='all'||r.analysisKind===f.kind)&&(f.band==='all'||bandOf(r)===f.band)&&(f.state==='all'||r.state===f.state)).sort((a,b)=>{
  if(f.sort==='name')return a.name.localeCompare(b.name,'zh-CN');
  if(f.sort==='score-desc'||f.sort==='score-asc'){if(a.numeric===null)return b.numeric===null?0:1;if(b.numeric===null)return -1;return f.sort==='score-desc'?b.numeric-a.numeric:a.numeric-b.numeric}
  if(f.sort==='credit')return (b.credit??-1)-(a.credit??-1);
  return (b.termOrder??-Infinity)-(a.termOrder??-Infinity)||b.termLabel.localeCompare(a.termLabel,'zh-CN')||a.name.localeCompare(b.name,'zh-CN');
 });
}
