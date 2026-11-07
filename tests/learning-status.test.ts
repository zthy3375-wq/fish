import {it,expect} from 'vitest';
import {learningState} from '../src/domain/learning-status';
const now=new Date('2026-11-07T08:00:00Z');
it('deadline never claims submission and unknown remains distinct from overdue pending',()=>{
 expect(learningState({status:'unknown',statusText:'未知',deadline:'2026-11-06T18:00'},now)).toEqual({key:'unknown',label:'已截止 · 提交状态未知'});
 expect(learningState({status:'pending',statusText:'未交',deadline:'2026-11-06T18:00'},now)).toEqual({key:'closed',label:'未提交 · 已逾期'});
 expect(learningState({status:'submitted',statusText:'待批阅',deadline:'2026-11-06T18:00'},now)).toEqual({key:'submitted',label:'已提交 · 待批阅'});
 expect(learningState({status:'submitted',statusText:'已完成',deadline:null},now).label).toBe('已完成');
 expect(learningState({status:'pending',statusText:'未交',deadline:null},now).label).toBe('未提交');
 expect(learningState({status:'pending',statusText:'未交，已截止',deadline:null},now)).toEqual({key:'closed',label:'未提交 · 已逾期'});
});
