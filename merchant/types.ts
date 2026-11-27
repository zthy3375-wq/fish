import type {Media,Shop} from '../src/services/commerce';
export interface Draft extends Omit<Shop,'id'> {
 legalName:string;businessId:string;legalAddress:string;legalPhone:string;qualification:string;qualificationImage:string;
}
export interface ShopReview extends Media {shop:{id:string;state:string;draft:Draft;revision:number;decision:string}|null;plans:Plan[]}
export interface Plan {id:string;name:string;cents:number;category_slot:boolean;banner_slot:boolean;home_slot:boolean;reports:boolean}
export interface Daily {day:string;kind:'impression'|'visit'|'claim'|'redeem';total:number}
export interface ShopRecord {id:string;draft:Draft;published:Draft|null;state:string;decision:string;revision:number}
export interface AdRecord {id:string;shop_id:string;shopName:string|null;title:string;subtitle:string;image:string;state:string;decision:string}
export interface OfferRecord {id:string;title:string;terms:string;quota:number;claimed:number;active:boolean;startsAt:string;endsAt:string}
export interface Contract {
 id:string;shop_id:string;snapshot:Plan;kind:string;startsAt:string;endsAt:string;
 cents:number;paid:number;reference?:string;attachment?:string;placements:string[];
 cancelled_at:string|null;receipts:Array<{id:string;cents:number;reference:string;recorded_at:string}>;
}
export interface Schedule {id:string;title:string;contract_id:string;placement:string;state:string;startsAt:string;endsAt:string}
export interface Report {id:string;shop_id:string;ad_id:string|null;reason:string;resolution:string|null;created_at:string}
export interface Audit {id:string;action:string;subject:string|null;created_at:string}
export const stateName:Record<string,string>={pending:'待审核',approved:'已通过',rejected:'未通过',suspended:'已暂停展示',removed:'已下架',active:'启用',paused:'已暂停',monthly:'月度',trial:'14 天试用',short:'短期'};
export const placementName:Record<string,string>={category:'分类推荐',banner:'周边 Banner',home:'首页广告'};
export const metricName:Record<Daily['kind'],string>={impression:'去重曝光',visit:'去重访问',claim:'领取',redeem:'核销'};
export const amount=(cents:number)=>'¥'+(cents/100).toFixed(2);
export const assetName=(placement:string)=>placementName[placement.split(':')[0]]||placement;
export function contractState(contract:Contract){
 if(contract.cancelled_at)return '已取消';
 if(Date.parse(contract.endsAt)<=Date.now())return '已到期';
 if(Date.parse(contract.startsAt)>Date.now())return '未开始';
 return contract.paid<contract.cents?'待收款':'有效';
}
