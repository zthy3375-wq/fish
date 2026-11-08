import {describe,it,expect} from 'vitest';
import {quzhiMoney,quzhiMonth,quzhiIssue} from '../src/services/quzhi-client';
describe('quzhi wallet presentation',()=>{
  it('keeps unknown balance different from zero and retains milli-yuan precision',()=>{
    expect(quzhiMoney(null)).toBe('—');expect(quzhiMoney('')).toBe('—');expect(quzhiMoney('NaN')).toBe('—');
    expect(quzhiMoney('0')).toBe('0.00');expect(quzhiMoney('0.125')).toBe('0.125');expect(quzhiMoney('-1.2')).toBe('-1.20');
  });
  it('selects the billing month in China across UTC month boundaries',()=>{
    expect(quzhiMonth(new Date('2026-10-31T16:30:00Z'))).toBe('2026-11');
    expect(quzhiMonth(new Date('2026-12-31T16:30:00Z'))).toBe('2027-01');
  });
  it('uses fixed error copy instead of rendering native/network payloads',()=>{
    expect(quzhiIssue('token=private')).not.toContain('private');
    expect(quzhiIssue('AUTH')).toContain('重新连接');
  });
});
