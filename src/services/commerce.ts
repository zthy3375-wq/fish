import {Capacitor,registerPlugin} from '@capacitor/core';

export interface Shop {
 id:string; name:string; category:string; description:string; hours:string; phone:string; address:string;
 images:string[]; latitude:number|null; longitude:number|null;
}
export interface Category {id:string;name:string}
export interface Ad {id:string;shopId:string;title:string;subtitle:string;placement:string;image:string;endsAt:string}
export interface Offer {id:string;title:string;terms:string;endsAt:string;soldOut:boolean}
export interface Coupon {id:string;title:string;terms:string;shopName:string;code:string|null;endsAt:string;claimedAt:string;usedAt:string|null;state:'available'|'expired'|'used'}
export interface Access {role:'owner'|'business'|'merchant'|'student';memberId:string;shopId:string|null;verifiedStudent:boolean;adminUrl?:string}
export interface Media {media?:Record<string,string>}
export interface CommercePage<T> extends Media {items:T[];next:string|null}
export interface Catalog extends CommercePage<Shop> {categories:Category[];ads:Ad[]}
export type CommerceRequest=<T=Record<string,unknown>>(action:string,body?:Record<string,unknown>)=>Promise<T>;

const plugin=registerPlugin<{request<T>(options:{action:string;body:Record<string,unknown>}):Promise<T>}>('Treehole');
export const commerceSupported=Capacitor.isPluginAvailable('Treehole');
export const commerceRequest:CommerceRequest=(action,body={})=>plugin.request({action:'commerce.'+action,body});

const messages:Record<string,string>={
 commerce_unavailable:'校园周边暂未开放',not_found:'这项内容已下架或暂不可用',session_expired:'请先登录邯院通账号',
 student_verification_required:'领取前需核验邯郸学院学生身份',forbidden:'当前账号没有这项权限',sold_out:'这张优惠券已经领完',
 offer_unavailable:'这张优惠券已过期或暂停领取',already_redeemed:'这张优惠券已经核销',invalid_coupon:'核销码无效或不属于本店',
 invalid_request:'请核对填写内容',invalid_image:'请选择清晰的图片并重试',invalid_period:'请核对开始和结束时间',
 inventory_full:'所选日期的广告位已满，请调整排期',schedule_conflict:'同一合同下有重叠广告排期',
 schedule_unavailable:'这条排期已到期或关联的商家、素材和合同不可用',shop_unavailable:'请先完成门店审核',
 shop_suspended:'门店已暂停展示，请联系审核人员',contract_overlap:'该门店在所选日期已有有效合同',
 placement_not_in_plan:'所选广告位未在合同中预留',owner_price_required:'自定义价格需由项目所有者登记',
 ad_not_approved:'请先通过素材审核',trial_used:'每家商家可使用一次付费套餐试用',invalid_renewal:'请核对原合同及续期时间',
 invalid_receipt:'收款或退款金额超出合同余额',report_plan_required:'当前套餐未开通推广报告',
 category_reserved:'当前分类仍有推广排期，请先处理合同',request_conflict:'记录状态已变化，请刷新后重试',
 too_many_requests:'操作较频繁，请稍后重试',network_unavailable:'网络连接失败，请检查网络后重试',
};
export function commerceError(cause:unknown){
 const error=cause as {code?:string;message?:string}|null;
 return messages[error?.code||error?.message||'']||'服务暂时无法连接，请稍后重试';
}
export function dateLabel(value:string){
 return new Date(value).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit',hour12:false});
}
export function mapURL(shop:Shop){
 const url=new URL('https://uri.amap.com/'+(shop.latitude===null?'search':'marker'));
 url.searchParams.set('name',shop.latitude===null?shop.address:shop.name);
 if(shop.latitude!==null)url.searchParams.set('position',shop.longitude+','+shop.latitude);
 url.searchParams.set('city','邯郸');
 return url.href;
}
type Metric={kind:'impression'|'visit';id:string};
const events=new Map<string,Metric>();
const submitted=new Set<string>();
let delay:ReturnType<typeof setTimeout>|undefined;
export function trackCommerce(kind:Metric['kind'],id:string){
 if(!commerceSupported)return;
 const key=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Shanghai'})+kind+id;
 if(submitted.has(key)||events.has(key))return;
 events.set(key,{kind,id});
 if(delay===undefined)delay=setTimeout(flush,1800);
}
function flush(){
 delay=undefined;
 const batch=[...events.entries()].slice(0,12);
 for(const [key] of batch){events.delete(key);submitted.add(key);}
 if(submitted.size>256)submitted.clear();
 if(events.size)delay=setTimeout(flush,1800);
 if(batch.length)void commerceRequest('metrics',{events:batch.map(([,event])=>event)}).catch(()=>{});
}
