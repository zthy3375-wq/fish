import {Capacitor,registerPlugin} from '@capacitor/core';
export interface PangguaiTicket {id:string;name:string;balance:string|null;principal:string|null;gift:string|null}
export interface PangguaiOrder {id:string;name:string;amount:string|null;status:string;time:string}
export interface PangguaiSnapshot {connected:boolean;expired:boolean;phone:string;balance?:string|null;walletUpdatedAt?:number;tickets?:PangguaiTicket[];ticketsUpdatedAt?:number;orders?:PangguaiOrder[];ordersUpdatedAt?:number;issues?:Record<string,string>}
export interface PangguaiDevice {id:string;name:string;category:string;operator:string;payment:string;issue:string;skus:{id:string;name:string;price:string|null;feature:string;available:boolean}[]}
interface PangguaiNative {getSnapshot():Promise<PangguaiSnapshot>;login():Promise<PangguaiSnapshot>;refresh():Promise<PangguaiSnapshot>;logout():Promise<PangguaiSnapshot>;scan():Promise<PangguaiDevice>;openRecharge(options:{merchantId:string}):Promise<{opened:boolean}>}
export const pangguaiNative=registerPlugin<PangguaiNative>('PangguaiCampus');
export const pangguaiSupported=()=>Capacitor.getPlatform()==='android'&&Capacitor.isPluginAvailable('PangguaiCampus');
export function pangguaiError(code?:string):string{return ({AUTH:'登录已失效，请重新连接',ACCOUNT:'账户信息不一致，请重新连接',VERIFY:'平台要求验证或稍后重试，请在官方页面完成验证后再试',PARTIAL:'本次数据不完整，保留上次结果',FORMAT:'返回信息暂时无法识别，保留上次结果',QR:'请扫描胖乖机身上的设备二维码',DEVICE:'设备信息不匹配或暂未支持',PHONE:'请输入正确手机号',NO_ALIPAY:'请先安装支付宝，再为商户钱包充值',SERVICE:'平台暂未完成请求，请稍后重试',BUSY:'正在处理，请稍候',NETWORK:'网络连接失败，请稍后重试'} as Record<string,string>)[code??'']??'操作未完成，请稍后重试'}
export function pgAmount(value?:string|null){return value!=null&&/^\d{1,10}(\.\d{1,4})?$/.test(value)?Number(value).toLocaleString('zh-CN',{minimumFractionDigits:2,maximumFractionDigits:2,useGrouping:false}):'—'}
