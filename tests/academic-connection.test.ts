import {describe,expect,it} from 'vitest';
import {
  AcademicConnectionController,
  normalizeAuthorizedAcademicData,
  academicSnapshotToData,
  type AuthorizedAcademicConnector
} from '../src/services/academic-connection';

function studentPayload(){
  return {
    semester: {id:'2026-fall',academicYear:'2026–2027',season:'秋季',startDate:'2026-09-07',weekStartDate:'2026-09-07',weekCount:18},
    courses: [{id:'mine1',name:'数学',teacher:'老师',room:'A102',day:1,start:'08:00',end:'09:35',period:'1-2节',weeks:[2,1,1],color:'blue',password:'must-never-keep'}],
    grades: [{name:'数学',score:92,credit:3,term:'2026–2027 秋季',kind:'必修',token:'never-keep'}],
    exams: [{name:'数学',date:'2027-01-11',time:'09:00–11:00',room:'A102',seat:'12',cookies:'never-keep'}],
    sessionId:'must-never-keep'
  };
}

describe('school-approved academic sync boundary',()=>{
  it('only allows explicitly shaped academic records, no credentials or tokens',()=>{
    const snapshot=normalizeAuthorizedAcademicData(studentPayload(),'school',new Date('2026-11-06T00:00:00Z'));
    expect(snapshot.semester.weekCount).toBe(18);
    expect(snapshot.courses[0].weeks).toEqual([1,2]);
    expect(snapshot.courses).toHaveLength(1);
    expect(snapshot.grades).toHaveLength(1);
    expect(snapshot.exams).toHaveLength(1);
    const result=JSON.stringify(snapshot);
    expect(result).not.toContain('password');
    expect(result).not.toContain('token');
    expect(result).not.toContain('cookies');
    expect(result).not.toContain('sessionId');
    expect(academicSnapshotToData(snapshot).source).toBe('official');
  });

  it('rejects data without academic semester, invalid weeks or malformed times',()=>{
    const noSemester=studentPayload() as Record<string,unknown>;
    delete noSemester.semester;
    expect(()=>normalizeAuthorizedAcademicData(noSemester,'school')).toThrow(/学期/);
    const bad=studentPayload();bad.courses[0].end='07:30';
    expect(()=>normalizeAuthorizedAcademicData(bad,'school')).toThrow(/课程时间/);
    const weeks=studentPayload();weeks.courses[0].weeks=[45];
    expect(()=>normalizeAuthorizedAcademicData(weeks,'school')).toThrow(/教学周/);
  });

  it('connects, syncs, marks expired sessions and clears records on disconnect',async()=>{
    let connected=false;
    const connector:AuthorizedAcademicConnector={
      id:'approved-school',displayName:'Approved School',
      beginOfficialAuthorization:async()=>{connected=true},
      getSessionStatus:async()=>connected?'connected':'expired',
      fetchMyAcademicData:async()=>studentPayload(),
      disconnect:async()=>{connected=false}
    };
    const session=new AcademicConnectionController(connector);
    expect(session.snapshot).toBeNull();
    expect(await session.connect()).toBe(true);
    expect(session.state.phase).toBe('ready');
    expect((await session.refresh())?.courses[0].name).toBe('数学');
    expect(session.state.syncedAt).toBeTruthy();
    connected=false;
    expect(await session.refresh()).toBeNull();
    expect(session.state.phase).toBe('expired');
    await session.disconnect();
    expect(session.state.phase).toBe('disconnected');
    expect(session.snapshot).toBeNull();
  });

  it('does not expose malformed fetched records as successful synchronization',async()=>{
    const connector:AuthorizedAcademicConnector={
      id:'school',displayName:'School',
      beginOfficialAuthorization:async()=>{},
      getSessionStatus:async()=> 'connected',
      fetchMyAcademicData:async()=>({grades:[],courses:[],exams:[]}),
      disconnect:async()=>{}
    };
    const session=new AcademicConnectionController(connector);
    expect(await session.connect()).toBe(true);
    expect(await session.refresh()).toBeNull();
    expect(session.state.phase).toBe('error');
    expect(session.snapshot).toBeNull();
  });
});
