import {expect,it} from 'vitest';
import {campusRooms} from '../src/services/campus-rooms';
import {roomPlanTarget,planBuildings,isRoomInPlanBuilding} from '../src/services/campus-plan';
it('maps only diagram-identified buildings and blocks',()=>{
 const a=campusRooms.find(r=>r.cdmc==='A201')!;
 expect(roomPlanTarget(a)).toMatchObject({campus:'east',name:'文理综合楼 A 区'});
 const w=campusRooms.find(r=>r.jxlmc==='西区第一教学楼')!;
 expect(roomPlanTarget(w)).toMatchObject({campus:'west',name:'天玑楼（一教）'});
 expect(roomPlanTarget({...a,jxlmc:'未知楼'})).toBeUndefined();
 expect(roomPlanTarget({...a,cdmc:'无法识别的房间'})).toBeUndefined();
});
it('keeps east blocks distinct when opening rooms from the plan',()=>{
 const a=planBuildings.find(b=>b.block==='A')!;
 const rooms=campusRooms.filter(r=>isRoomInPlanBuilding(r,a));
 expect(rooms.length).toBeGreaterThan(0);expect(rooms.every(r=>/^A\d/.test(r.cdmc))).toBe(true);
 expect(isRoomInPlanBuilding({...rooms[0]!,cdmc:'B201'},a)).toBe(false);
});
