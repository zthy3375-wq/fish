import {it,expect} from 'vitest';
import {emptyAcademicCache,schoolError} from '../src/services/academic-sync-engine';
import {emptyLearning} from '../src/domain/learning';
import {buildFailureFeedback} from '../src/services/failure-feedback';
it('exports useful failure diagnostics without account or content fields',()=>{
 const a=emptyAcademicCache(),l=emptyLearning();a.connected=true;a.lastError=schoolError('WEEKS')+'（周次格式：1/3周）';
 a.profile.data={name:'PRIVATE_NAME',major:'PRIVATE_MAJOR',className:'PRIVATE_CLASS',year:'2026'};
 l.accountKey='PRIVATE_ACCOUNT';l.courses=[{courseId:'PRIVATE_ID',classId:'PRIVATE_CLASS',name:'PRIVATE_COURSE',teacher:'PRIVATE_TEACHER'}];
 l.issues={'PRIVATE_ID/PRIVATE_CLASS':'WORK_ENC'};l.courseSync={'PRIVATE_ID/PRIVATE_CLASS':{status:'error',count:0,at:'',code:'WORK_ENC'}};
 l.diagnostics={workEncInputs:0,stage:'work-list',path:'/private/TOKEN',cookie:'PRIVATE_COOKIE',host:'PRIVATE_HOST',workRows:4};
 const r=buildFailureFeedback(a,l,'1.0.8-test.1','android',new Date('2026-11-09T04:00:00Z'));
 expect(r.academic.lastFailure).toEqual({code:'WEEKS',weekFormats:['1/3周']});expect(r.learning.errorCodes).toEqual(['WORK_ENC']);
 expect(r.learning.diagnostics).toEqual({workRows:4,workEncInputs:0,stage:'work-list'});
 expect(JSON.stringify(r)).not.toMatch(/PRIVATE|TOKEN/);
});
it('redacts unknown errors and distinguishes a healthy empty report',()=>{
 const a=emptyAcademicCache(),l=emptyLearning();let r=buildFailureFeedback(a,l,'test','web');
 expect(r.academic.lastFailure).toBeNull();expect(r.learning.errorCodes).toEqual([]);
 a.lastError='password=SECRET';l.issues={connection:'https://example.test/?token=SECRET'};
 r=buildFailureFeedback(a,l,'test','web');expect(r.academic.lastFailure?.code).toBe('UNKNOWN');expect(JSON.stringify(r)).not.toContain('SECRET');
});
