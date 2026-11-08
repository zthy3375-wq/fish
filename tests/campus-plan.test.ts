import {expect,it} from 'vitest';
import {campusRooms} from '../src/services/campus-rooms';
import {roomPlanTarget} from '../src/services/campus-plan';
it('maps only diagram-identified buildings and blocks',()=>{
 const a=campusRooms.find(r=>r.cdmc==='A201')!;
 expect(roomPlanTarget(a)).toMatchObject({campus:'east',name:'文理综合楼 A 区'});
 const w=campusRooms.find(r=>r.jxlmc==='西区第一教学楼')!;
 expect(roomPlanTarget(w)).toMatchObject({campus:'west',name:'天玑楼（一教）'});
 expect(roomPlanTarget({...a,jxlmc:'未知楼'})).toBeUndefined();
 expect(roomPlanTarget({...a,cdmc:'无法识别的房间'})).toBeUndefined();
});
