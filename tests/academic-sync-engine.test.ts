import {it,expect,vi} from 'vitest';
import {AcademicSyncEngine,applyAcademicResult,emptyAcademicCache} from '../src/services/academic-sync-engine';
import {defaultState,flatten} from '../src/domain/schedule';
import type {NativeAcademicResult,HandanAcademicClient} from '../src/services/handan-academic-client';
const calendar=()=>defaultState().semesters;
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
