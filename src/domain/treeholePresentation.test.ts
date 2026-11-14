import {describe,it,expect} from 'vitest';
import {treeholeTimestamp} from './treeholePresentation';
describe('treehole timestamps',()=>{
 const now=Date.parse('2026-11-14T16:00:00Z');
 it('uses readable relative time only for past timestamps',()=>{
  expect(treeholeTimestamp('2026-11-14T15:59:40Z',now)).toBe('刚刚');
  expect(treeholeTimestamp('2026-11-14T15:55:00Z',now)).toBe('5 分钟前');
  expect(treeholeTimestamp('2026-11-14T14:00:00Z',now)).toBe('2 小时前');
  expect(treeholeTimestamp('2026-11-14T16:10:00Z',now)).toContain('00:10');
 });
 it('uses campus time for old posts and handles malformed timestamps',()=>{
  expect(treeholeTimestamp('2026-11-12T16:10:00Z',now)).toContain('11/13');
  expect(treeholeTimestamp('2026-11-12T16:10:00Z',now)).toContain('00:10');
  expect(treeholeTimestamp('invalid',now)).toBe('时间未知');
 });
});
