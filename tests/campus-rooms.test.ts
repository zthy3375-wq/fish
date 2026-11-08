import {describe,it,expect} from 'vitest';
import {campusRooms,roomCampus,roomFloor,searchRooms} from '../src/services/campus-rooms';
describe('verified classroom directory',()=>{
 it('keeps unique source records with no account or administrator fields',()=>{
  expect(campusRooms).toHaveLength(965);expect(new Set(campusRooms.map(r=>r.cdbh)).size).toBe(965);
  for(const r of campusRooms)expect(Object.keys(r).sort()).toEqual(['cdbh','cdmc','xqmc','cdlbmc','zws','jxlmc','lch'].sort());
 });
 it('uses building geography rather than the inaccurate campus field',()=>{
  const west=campusRooms.find(r=>r.jxlmc==='西区第一教学楼')!;
  expect(west.xqmc).toBe('主校区');expect(roomCampus(west)).toBe('west');
  expect(roomCampus({...west,jxlmc:'国际交流中心'})).toBe('unknown');
 });
 it('does not infer missing floors or show outdoor field as floor 1',()=>{
  const r=campusRooms[0]!;expect(roomFloor(r)).toBe('室外场地');
  expect(roomFloor({...r,jxlmc:'教学楼',cdmc:'A201',lch:''})).toBe('楼层待核对');
 });
 it('finds actual A201 and supports campus and floor filtering',()=>{
  expect(searchRooms('ａ２０１','east').some(r=>r.cdmc==='A201'&&r.lch==='2')).toBe(true);
  expect(searchRooms('机器人','west').length).toBeGreaterThan(0);
  expect(searchRooms('天玑','west').length).toBe(27);
  expect(searchRooms('天玑 机器人','west').length).toBeGreaterThan(0);
  expect(searchRooms('','east','东区文理综合楼','2').every(r=>r.lch==='2')).toBe(true);
 });
});
