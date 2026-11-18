// @vitest-environment jsdom
import {beforeEach,expect,it,vi} from 'vitest';
import {catalog,byCode} from '../src/domain/globalAchievements';
import {emptyAcademicCache} from '../src/services/academic-sync-engine';
import {emptyLearning} from '../src/domain/learning';
import {emptyTasks,type CampusTask} from '../src/domain/agenda';
beforeEach(()=>{vi.resetModules();localStorage.clear()});
it('has 32 unique collectibles including eight hidden discoveries',()=>{
 expect(catalog.length).toBe(32);expect(byCode.size).toBe(32);expect(new Set(catalog.map(a=>a.group)).size).toBe(6);
 expect(catalog.filter(a=>a.hidden).map(a=>a.code)).toEqual(['goldfish','puff','dream','timewalk','freeday','mapfish','emptyfish','lastline']);
});
it('records the device celebrations once, derives the three-service goal and enforces three private pins',async()=>{
 const j=await import('../src/services/achievementJournal');
 await Promise.all(['welcome','profile','bath','bath','laundry','map','water','goldfish'].map(c=>j.record(c)));
 await vi.waitFor(()=>expect(j.localStamps.value.life).toBeTruthy());
 expect(Object.keys(j.localStamps.value)).toHaveLength(8);expect(j.localQueue.value.filter(x=>x==='bath')).toHaveLength(1);
 await Promise.all(['welcome','bath','map','profile'].map(c=>j.togglePrivate(c)));expect(j.privatePins.value).toEqual(['welcome','bath','map']);
 await j.togglePrivate('bath');await j.togglePrivate('profile');expect(j.privatePins.value).toEqual(['welcome','map','profile']);
 await j.record('arrival');expect(j.localStamps.value.arrival).toBeUndefined();
 const backup=localStorage.getItem('hyt-collection-v1:device')!;vi.resetModules();
 const reopened=await import('../src/services/achievementJournal');await reopened.book('device');expect(reopened.localQueue.value).toEqual([]);
 expect(localStorage.getItem('hyt-collection-v1:device')).toBe(backup);expect(reopened.privatePins.value).toHaveLength(3);
});
it('rejects forged cloud awards and wrong account scope in an imported local record',async()=>{
 const j=await import('../src/services/achievementJournal');
 const stamp={at:new Date().toISOString(),historical:false};
 localStorage.setItem('hyt-collection-v1:device',JSON.stringify({stamps:{year:stamp,grade:stamp,welcome:stamp},pins:['year','grade','welcome']}));
 await j.book('device');expect(Object.keys(j.localStamps.value)).toEqual(['welcome']);expect(j.privatePins.value).toEqual(['welcome']);
});
it('requires actual school data and isolates school, learning, and signed-out histories',async()=>{
 const e=await import('../src/services/achievementEvidence'),j=await import('../src/services/achievementJournal');
 const c=emptyAcademicCache(),stamp='2026-10-01T12:00:00Z';e.observeSchool(c,true);e.schoolView(c,'exams',true);
 Object.assign(c,{connected:true,session:'valid',localScope:'schoolUserA',selectedTerm:'term'});
 e.observeSchool(c,false);e.schoolView(c,'schedule',true);expect(j.localStamps.value.offline).toBeUndefined();
 c.grades={data:[{name:'私人成绩'}] as never,updatedAt:stamp,error:null};c.terms.term={data:{courses:[{}]} as never,updatedAt:stamp,error:null};
 c.exams={data:[{name:'私人考试'}] as never,updatedAt:stamp,error:null};e.observeSchool(c,true);
 e.schoolView(c,'exams',false);e.schoolView(c,'schedule',false);e.schoolView(c,'schedule',true);
 await vi.waitFor(()=>expect(j.localStamps.value.offline).toBeTruthy());expect(j.localStamps.value.grade.at).toBe(stamp);expect(j.localStamps.value.exam).toBeTruthy();
 expect(j.localQueue.value).not.toContain('grade');expect(localStorage.getItem('hyt-collection-v1:school-schoolUserA')).not.toContain('私人');
 const other={...emptyAcademicCache(),connected:true,localScope:'schoolUserB'};e.observeSchool(other,false);expect(j.localStamps.value.grade).toBeUndefined();
 e.observeSchool(c,true);expect(j.localStamps.value.grade).toBeTruthy();
 const l=emptyLearning();Object.assign(l,{connected:true,accountKey:'a'.repeat(24),session:'valid',courses:[{}],lastAttempt:stamp,issues:{courses:'partial'}});
 e.observeLearning(l,true);expect(j.localStamps.value.learning).toBeUndefined();l.issues={};e.observeLearning(l,true);
 await vi.waitFor(()=>expect(j.localStamps.value.learning).toBeTruthy());e.observeSchool(emptyAcademicCache(),false);expect(j.localStamps.value.grade).toBeUndefined();expect(j.localStamps.value.learning).toBeTruthy();
 e.observeLearning(emptyLearning(),false);expect(j.localStamps.value.learning).toBeUndefined();
});
it('requires completed personal task and two checked steps, suppresses repeats',async()=>{
 const e=await import('../src/services/achievementEvidence'),j=await import('../src/services/achievementJournal'),s=emptyTasks();
 const t={completed:true,completedAt:new Date().toISOString(),steps:[{completed:true},{completed:false}]} as CampusTask;
 s.tasks=[t];const previous=structuredClone(s);e.observeTasks(s,previous);expect(j.localStamps.value.tasks).toBeUndefined();
 t.steps![1].completed=true;t.source='chaoxing';e.observeTasks(s,previous);expect(j.localStamps.value.tasks).toBeUndefined();
 delete t.source;e.observeTasks(s,previous);await vi.waitFor(()=>expect(j.localStamps.value.tasks).toBeTruthy());
});
it('separates notification acknowledgments between different community users',async()=>{
 const d=await import('../src/services/achievementDelivery');const r={awardOwner:'a',unlocks:['month','year','offline']};
 expect(d.pendingAwards(r,'b')).toEqual([]);expect(d.pendingAwards(r,'a')).toEqual(['month','year']);
 d.markPresented('a','month');expect(d.pendingAwards(r,'a')).toEqual(['year']);
 expect(d.pendingAwards({...r,awardOwner:'b'},'b')).toEqual(['month','year']);
});
it('retains a test.28 discovery and pin and saves each new egg once before presenting it',async()=>{
 const stamp={at:'2026-11-01T12:34:56Z',historical:false};
 localStorage.setItem('hyt-collection-v1:device',JSON.stringify({stamps:{goldfish:stamp},pins:['goldfish']}));
 const j=await import('../src/services/achievementJournal'),d=await import('../src/services/hiddenDiscovery');
 await d.discover('goldfish');expect(d.moment.value).toBeNull();
 await Promise.all([d.discover('dream'),d.discover('dream')]);
 expect(j.localStamps.value.dream).toBeDefined();expect(j.localQueue.value).toEqual([]);expect(d.moment.value).toBe('dream');
 await vi.waitFor(()=>expect(j.localQueue.value).toEqual(['dream']),{timeout:1800});
 await d.discover('dream');expect(d.moment.value).toBeNull();expect(j.localStamps.value.goldfish).toEqual(stamp);
 expect(j.privatePins.value).toEqual(['goldfish']);
});
it('requires consecutive gestures and a manually visited first week in this term',async()=>{
 const {tapSequence,weekJourney}=await import('../src/domain/discoveryGestures');
 const taps=tapSequence(5);
 expect([0,1,2,1000,1010,1020,1030,1040,1050].map(n=>taps.tap(n))).toEqual([false,false,false,false,false,false,false,true,false]);
 const w=weekJourney();expect(w.move(1,7,7)).toBe(false);expect(w.move(7,1,7)).toBe(false);w.reset();expect(w.move(1,7,7)).toBe(false);
 expect(w.move(7,1,7)).toBe(false);expect(w.move(1,7,7)).toBe(true);expect(w.move(7,7,7)).toBe(false);
});
it('limits compact identity to one verified role and one worn honor while the hall lists all honors',async()=>{
 const {visibleBadges}=await import('../src/domain/communityHonors');
 const items=(['moderator','developer','seed','seed','creator','contributor','unknown'] as const).map(code=>({code,at:null})) as never;
 expect(visibleBadges(items).map(x=>x.code)).toEqual(['developer','seed']);
 expect(visibleBadges(items,true).map(x=>x.code)).toEqual(['developer','seed','creator','contributor']);
});
