import {expect,it} from 'vitest';
import {learningCourseStatus} from '../src/domain/learning-sync-status';
it('distinguishes empty success from an unread or incompatible course',()=>{
 expect(learningCourseStatus()).toBe('尚未读取');
 expect(learningCourseStatus({status:'ok',count:0})).toBe('已读取 0 份作业');
 expect(learningCourseStatus({status:'error',count:0,code:'WORK_ENC'})).toContain('未识别到作业入口');
 expect(learningCourseStatus({status:'error',count:0,code:'WORK_SCHEMA'})).toContain('导出连接反馈');
 expect(learningCourseStatus({status:'partial',count:2})).toContain('部分');
});
it('offers actionable recovery without exposing unknown error strings',()=>{
 expect(learningCourseStatus({status:'error',count:0,code:'VERIFY'})).toContain('验证码');
 expect(learningCourseStatus({status:'error',count:0,code:'HTTP_403'})).toContain('HTTP 403');
 expect(learningCourseStatus({status:'error',count:0,code:'secret-token=abc'})).not.toContain('abc');
});
