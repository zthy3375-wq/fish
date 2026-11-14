import {it,expect,vi} from 'vitest';
import {AcademicSyncEngine,applyAcademicResult,emptyAcademicCache} from '../src/services/academic-sync-engine';
import {defaultState,flatten} from '../src/domain/schedule';
import type {NativeAcademicResult,HandanAcademicClient} from '../src/services/handan-academic-client';
const calendar=()=>defaultState().semesters;
const exam={name:'合成考试',date:'2026-12-01',time:'09:00',room:'测试教室',seat:'1'};
const result=():NativeAcademicResult=>({session:'valid',modules:{timetable:{status:'ok',data:{term:{xnm:'2026',xqm:'3'},kbList:[{kcmc:'人工链路测试课',xm:'教师',cdmc:'教室',xqj:'1',jcs:'11-13',zcd:'1-16周(单)'}],practice:[]}},grades:{status:'error',code:'HTTP'},exams:{status:'ok',data:[]}}});
it('takes real-shaped native results into the existing grid without touching personal storage',()=>{
 const personal=defaultState(),before=structuredClone(personal),c=applyAcademicResult(emptyAcademicCache(),result(),personal.semesters);
 const t=c.terms[c.selectedTerm!].data!;
 expect(flatten(t.courses,t.semester.id,t.table)[0]).toMatchObject({name:'人工链路测试课',start:'19:00',end:'21:10',weeks:[1,3,5,7,9,11,13,15]});
 expect(c.exams.data).toEqual([]);expect(c.session).toBe('valid');expect(c.grades.error).toBeTruthy();expect(personal).toEqual(before);
});
it('protects last good timetable and timestamp on empty, partial or malformed response',()=>{
 const initial=applyAcademicResult(emptyAcademicCache(),result(),calendar()),key=initial.selectedTerm!;
 for(const payload of [[],[{kcmc:'不完整'}]]){
  const r=result();(r.modules!.timetable.data as any).kbList=payload;
  const next=applyAcademicResult(initial,r,calendar());expect(next.terms[key].data).toEqual(initial.terms[key].data);expect(next.terms[key].updatedAt).toBe(initial.terms[key].updatedAt);expect(next.terms[key].error).toBeTruthy();
 }
});
it('retains cache on expired sessions and separates term partitions',()=>{
 const initial=applyAcademicResult(emptyAcademicCache(),result(),calendar());
 const expired=applyAcademicResult(initial,{session:'expired'},calendar());expect(expired.terms).toEqual(initial.terms);
 const r=result();(r.modules!.timetable.data as any).term={xnm:'2025',xqm:'12'};
 const next=applyAcademicResult(initial,r,calendar());expect(Object.keys(next.terms)).toEqual(['2026-3','2025-12']);
});
it('single-flights duplicate startup refresh and saves only a complete update',async()=>{
 let c=emptyAcademicCache();const request=vi.fn(async()=>result()),commit=vi.fn(async(next)=>{c=next});
 const engine=new AcademicSyncEngine({syncAll:request} as unknown as HandanAcademicClient,()=>c,commit,calendar);
 const a=engine.sync(),b=engine.sync();expect(a).toBe(b);await a;expect(request).toHaveBeenCalledTimes(1);expect(commit).toHaveBeenCalledTimes(1);
});
it('does not resurrect school data after logout while a request is pending',async()=>{
 let release!:(r:NativeAcademicResult)=>void,c=emptyAcademicCache();
 const client={syncAll:()=>new Promise<NativeAcademicResult>(resolve=>release=resolve),logout:async()=>({session:'disconnected'})} as unknown as HandanAcademicClient;
 const engine=new AcademicSyncEngine(client,()=>c,async n=>{c=n},calendar);
 const running=engine.sync();await engine.logout();release(result());await running;expect(c).toEqual(emptyAcademicCache());
});
it('a successful interactive account switch cannot keep data from the previous account',async()=>{
 let c=applyAcademicResult(emptyAcademicCache(),result(),calendar());
 const client={login:async()=>({session:'valid',modules:{timetable:{status:'error',code:'HTTP'}}})} as unknown as HandanAcademicClient;
 await new AcademicSyncEngine(client,()=>c,async n=>{c=n},calendar).sync(undefined,true);
 expect(c.terms).toEqual({});expect(c.lastError).toBeTruthy();
});
it('preserves nonnumeric grades, school GPA and strips unrecognized secret metadata',()=>{
 const r=result();r.modules!.grades={status:'ok',data:[{name:'课程',scoreText:'优秀',credit:2,gpa:4,term:'2026 秋季',kind:'必修',token:'PRIVATE'}]};
 const c=applyAcademicResult(emptyAcademicCache(),r,calendar());expect(c.grades.data![0].scoreText).toBe('优秀');expect(JSON.stringify(c)).not.toContain('PRIVATE');
});
it('keeps school weeks beyond the default local 18-week calendar',()=>{
 const r=result();(r.modules!.timetable.data as any).kbList[0].zcd='1-20周';
 const c=applyAcademicResult(emptyAcademicCache(),r,calendar());
 expect(c.terms[c.selectedTerm!].data!.semester.weekCount).toBe(20);
 expect(c.terms[c.selectedTerm!].data!.courses[0].arrangements[0].customWeeks).toContain(20);
});
it('keeps grade history independent of the selected timetable term',async()=>{
 let c=emptyAcademicCache();const getGrades=vi.fn(async()=>({session:'valid',modules:{grades:{status:'ok',scope:'all',data:[]}}}));
 const client={getTimetable:async()=>result(),getGrades} as unknown as HandanAcademicClient;
 await new AcademicSyncEngine(client,()=>c,async n=>{c=n},calendar).sync({xnm:'2026',xqm:'3'});
 expect(getGrades).toHaveBeenCalledWith(undefined);expect(c.grades.scope).toBe('all');
});
it('preserves successful grade history on empty, malformed and expired results',()=>{
 const r=result();r.modules!.grades={status:'ok',scope:'all',data:[{name:'课程',scoreText:'80',credit:2,gpa:3,term:'2026 秋季',kind:'必修',courseCode:'C1',examType:'补考'}]};
 const c=applyAcademicResult(emptyAcademicCache(),r,calendar());expect(c.grades.data![0].courseCode).toBe('C1');
 for(const m of [{status:'ok',data:[]},{status:'ok',data:[{}]},{status:'error',code:'EXPIRED'}]){const n=applyAcademicResult(c,{session:'expired',modules:{grades:m as any}},calendar());expect(n.grades.data).toEqual(c.grades.data);expect(n.grades.updatedAt).toBe(c.grades.updatedAt);expect(n.grades.error).toBeTruthy()}
});

it('an explicit single-term response cannot replace a known all-term grade cache',()=>{const r=result();r.modules!.grades={status:'ok',scope:'all',data:[{name:'历史课',scoreText:'80',credit:2,gpa:3,term:'2025 秋季',kind:'必修'}]};const c=applyAcademicResult(emptyAcademicCache(),r,calendar());const n=applyAcademicResult(c,{session:'valid',modules:{grades:{status:'ok',scope:'term',data:[{name:'当前课',scoreText:'90',credit:2,gpa:4,term:'2026 秋季',kind:'必修'}]}}},calendar());expect(n.grades.data).toEqual(c.grades.data);expect(n.grades.error).toContain('单学期');expect(n.grades.scope).toBe('all')});

it('accepts full-width and alternate parity weeks end-to-end without dropping courses',()=>{
 const r=result();const t=r.modules!.timetable.data as any;
 t.kbList.push({...t.kbList[0],kcmc:'人工兼容课',jcs:'3-4',zcd:'第１９－２１（单）周'});
 const c=applyAcademicResult(emptyAcademicCache(),r,calendar());const saved=c.terms[c.selectedTerm!];
 expect(saved.error).toBeNull();expect(saved.data!.semester.weekCount).toBeGreaterThanOrEqual(21);
 expect(saved.data!.courses).toHaveLength(2);expect(saved.data!.courses[1].arrangements[0].customWeeks).toEqual([19,21]);
});
it('reports only bounded numeric week formats and preserves the last complete timetable',()=>{
 const initial=applyAcademicResult(emptyAcademicCache(),result(),calendar());
 for(const expression of ['1/3周','student-name secret-token=abc']){
  const r=result();(r.modules!.timetable.data as any).kbList[0].zcd=expression;
  const c=applyAcademicResult(initial,r,calendar());
  expect(c.terms[initial.selectedTerm!].data).toEqual(initial.terms[initial.selectedTerm!].data);
  expect(c.lastError).toContain('教学周');
  if(expression==='1/3周')expect(c.lastError).toContain('1/3周');
  else expect(c.lastError).not.toContain('secret');
 }
});

it('partitions exams by verified term and restores them when returning to that timetable',()=>{
 const first=result();first.modules!.exams={status:'ok',data:[exam]};
 const original=applyAcademicResult(emptyAcademicCache(),first,calendar());
 const second=result();(second.modules!.timetable.data as any).term={xnm:'2025',xqm:'12'};
 second.modules!.exams={status:'error',code:'NETWORK'};
 const switched=applyAcademicResult(original,second,calendar());
 expect(switched.selectedTerm).toBe('2025-12');expect(switched.exams.data).toBeNull();
 expect(switched.examsByTerm!['2026-3'].data).toEqual([exam]);
 const restored=applyAcademicResult(switched,{session:'valid',modules:{timetable:first.modules!.timetable}},calendar());
 expect(restored.exams.data).toEqual([exam]);
});
it('a failed timetable cannot attach another term\'s successful exams to the visible schedule',()=>{
 const first=result();first.modules!.exams={status:'ok',data:[exam]};
 const original=applyAcademicResult(emptyAcademicCache(),first,calendar());
 const next=applyAcademicResult(original,{session:'valid',resolvedTerm:{xnm:'2025',xqm:'12'},modules:{timetable:{status:'error',code:'NETWORK'},exams:{status:'ok',data:[]}}},calendar());
 expect(next.selectedTerm).toBe('2026-3');expect(next.exams.data).toEqual([exam]);
 expect(next.examsByTerm!['2025-12'].data).toEqual([]);
});
it('malformed timetable metadata does not discard a valid independent grade result',()=>{
 const response=result();(response.modules!.timetable.data as any).term={xnm:'bad',xqm:'3'};
 response.modules!.grades={status:'ok',scope:'all',data:[{name:'课程',scoreText:'90',credit:2,gpa:4,term:'2026',kind:'必修'}]};
 const next=applyAcademicResult(emptyAcademicCache(),response,calendar());
 expect(next.lastError).toContain('学期');expect(next.grades.data).toHaveLength(1);
});
it('exam requests follow the term resolved by the timetable instead of guessing the current term',async()=>{
 let c=emptyAcademicCache();const getExams=vi.fn(async()=>({session:'valid',modules:{exams:{status:'ok',data:[]}}}));
 await new AcademicSyncEngine({getTimetable:async()=>result(),getExams} as unknown as HandanAcademicClient,()=>c,async next=>{c=next},calendar).sync();
 expect(getExams).toHaveBeenCalledWith({xnm:'2026',xqm:'3'});
});
it('logout is written after an already pending storage write so old data cannot reappear',async()=>{
 let c=emptyAcademicCache(),release!:()=>void;
 const commit=vi.fn(async next=>{if(next.connected)await new Promise<void>(resolve=>{release=resolve});c=next});
 const client={getTimetable:async()=>result(),logout:vi.fn(async()=>({session:'disconnected'}))} as unknown as HandanAcademicClient;
 const engine=new AcademicSyncEngine(client,()=>c,commit,calendar);
 const syncing=engine.sync();await vi.waitFor(()=>expect(release).toBeTypeOf('function'));
 const leaving=engine.logout();release();await Promise.all([syncing,leaving]);
 expect(c).toEqual(emptyAcademicCache());
});
it('a new account can sync after logout without waiting for a stale network request',async()=>{
 let c=emptyAcademicCache(),release!:(r:NativeAcademicResult)=>void;
 const getTimetable=vi.fn().mockImplementationOnce(()=>new Promise<NativeAcademicResult>(resolve=>{release=resolve})).mockResolvedValue(result());
 const engine=new AcademicSyncEngine({getTimetable,logout:async()=>({session:'disconnected'})} as unknown as HandanAcademicClient,()=>c,async next=>{c=next},calendar);
 const stale=engine.sync();await engine.logout();await engine.sync();
 expect(getTimetable).toHaveBeenCalledTimes(2);const current=structuredClone(c);
 release({session:'expired'});await stale;expect(c).toEqual(current);
});
