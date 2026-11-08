import type {CampusRoom} from './campus-rooms';
export interface PlanTarget {campus:'east'|'west';name:string;x:number;y:number;building:string;block?:string}
// Pixel reference points read from the user-provided diagrams, never latitude/longitude or room-door coordinates.
const west:Record<string,[string,number,number]>={
 '西区第一教学楼':['天玑楼（一教）',340,451],
 '西区第二教学楼':['天枢楼（二教）',340,408],
 '西区第三教学楼':['天权楼（三教）',340,489],
 '西区第四教学楼（综合）':['天璇楼（四教）',246,428],
 '西区第五教学楼':['玉衡楼（五教）',138,482],
 '西区第六教学楼':['开阳楼（六教）',140,529],
 '西区第七教学楼（美术）':['瑶光楼（七教）',140,580],
};
const eastBlocks:Record<string,[number,number]>={A:[75,762],B:[94,810],C:[142,852],D:[210,869],E:[229,806]};
export const planBuildings:PlanTarget[]=[
 ...Object.entries(west).map(([building,w])=>({campus:'west' as const,name:w[0],x:w[1],y:w[2],building})),
 ...Object.entries(eastBlocks).map(([block,p])=>({campus:'east' as const,name:`文理综合楼 ${block} 区`,x:p[0],y:p[1],building:'东区文理综合楼',block})),
];
export function isRoomInPlanBuilding(room:CampusRoom,target:PlanTarget){
 return room.jxlmc===target.building&&(!target.block||new RegExp(`^${target.block}[0-9]`,'i').test(room.cdmc));
}
export function roomPlanTarget(room:CampusRoom):PlanTarget|undefined{
 return planBuildings.find(target=>isRoomInPlanBuilding(room,target));
}
