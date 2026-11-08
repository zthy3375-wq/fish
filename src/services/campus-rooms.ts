import catalog from '../data/campus-rooms.json';
export type RoomCampus = 'east' | 'west' | 'unknown';
export interface CampusRoom {cdbh:string;cdmc:string;xqmc:string;cdlbmc:string;zws:string;jxlmc:string;lch:string}
export const campusRooms:CampusRoom[]=catalog.records;
export const roomCatalogSource={date:catalog.retrievedAt,scope:catalog.scope,url:catalog.source};
// 校区登记与物理位置不一致，只有楼名明确包含东/西区时才归属。
export function roomCampus(room:CampusRoom):RoomCampus{
 return room.jxlmc.startsWith('东区')?'east':room.jxlmc.startsWith('西区')?'west':'unknown';
}
export function roomFloor(room:CampusRoom):string{
 if(room.jxlmc.includes('室外'))return '室外场地';
 return room.lch.trim()?`${room.lch.trim()} 层`:'楼层待核对';
}
export function searchRooms(query:string,campus:RoomCampus|'all'='all',building='',floor=''):CampusRoom[]{
 const normalize=(s:string)=>s.normalize('NFKC').toLocaleLowerCase().replace(/[\s—–-]/g,'');
 const terms=normalize(query).split(/[,，]/).filter(Boolean);
 return campusRooms.filter(r=>(campus==='all'||roomCampus(r)===campus)&&(!building||r.jxlmc===building)&&(!floor||r.lch===floor)&&terms.every(q=>normalize(`${r.cdmc} ${r.cdbh} ${r.jxlmc}`).includes(q)));
}
