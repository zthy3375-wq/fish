import {Capacitor,registerPlugin} from '@capacitor/core';
export interface ScannedBike {ticket:string;provider:'hello'|'meituan';number:string}
export type BikeMode='use'|'web'|'scanner';
export type BikeStatus='alipay_requested'|'link_requested'|'scanner_requested'|'unavailable'|'blocked'|'cancelled'|'copied';
interface BikePlugin {scan():Promise<unknown>;open(options:{ticket:string;mode:BikeMode}):Promise<unknown>;copyNumber(options:{ticket:string}):Promise<unknown>;clear():Promise<void>}
const native=registerPlugin<BikePlugin>('BikeScan');
export const bikeSupported=()=>Capacitor.getPlatform()==='android'&&Capacitor.isPluginAvailable('BikeScan');
export const bikeName=(bike:ScannedBike)=>bike.provider==='hello'?'哈啰单车':'美团单车';
export function validateBike(value:unknown):ScannedBike {
 const v=value as ScannedBike;
 if(!v||!['hello','meituan'].includes(v.provider)||typeof v.ticket!=='string'||!/^[a-f0-9-]{36}$/.test(v.ticket)||typeof v.number!=='string'||!/^\d{10}$/.test(v.number))throw Error('FORMAT');
 return {ticket:v.ticket,provider:v.provider,number:v.number};
}
export async function scanBike(){if(!bikeSupported())throw Error('UNSUPPORTED');return validateBike(await native.scan())}
export async function actOnBike(bike:ScannedBike,mode:BikeMode|'copy'):Promise<BikeStatus> {
 validateBike(bike);if(!['use','web','scanner','copy'].includes(mode))throw Error('ARGUMENT');
 const result=mode==='copy'?await native.copyNumber({ticket:bike.ticket}):await native.open({ticket:bike.ticket,mode});
 const status=(result as {status?:unknown})?.status;
 return typeof status==='string'&&['alipay_requested','link_requested','scanner_requested','unavailable','blocked','cancelled','copied'].includes(status)?status as BikeStatus:'unavailable';
}
export async function clearBike(){if(bikeSupported())try{await native.clear()}catch{/* Session is memory-only and also expires when the native host is destroyed. */}}
export function bikeStatusMessage(status:BikeStatus):string {
 switch(status){
  case 'alipay_requested':return '已请求打开支付宝中的哈啰用车入口，请核对车辆、登录及费用后继续。';
  case 'link_requested':return '已交给系统打开车码链接，可能进入官方网页或下载页；页面加载失败请检查网络后重试，未显示这辆车可使用下方官方扫码或复制编号。';
  case 'scanner_requested':return '已请求打开官方扫码页，需要在官方端再次扫描，或输入复制的车辆编号。';
  case 'blocked':return '系统暂未允许跳转，请手动打开官方 App，或尝试车码网页。';
  case 'cancelled':return '已取消打开，可以再次尝试。';
  case 'copied':return '车辆编号已复制，可在官方端选择输入车号。';
  default:return '暂未打开，可能未安装对应应用或当前系统不支持此入口。可尝试车码网页，或手动打开官方 App。';
 }
}
export function bikeErrorMessage(error:unknown):string {
 const e=error as {code?:string;message?:string};const code=e?.code||e?.message;
 if(code==='CANCELLED')return '已取消扫码，可重新扫描。';
 if(code==='PERMISSION'||code==='CAMERA')return '相机未打开，请允许相机权限后重试，也可在扫码页从相册识别。';
 if(code==='QR')return '暂不支持这个二维码，请扫描哈啰或美团单车车身码。';
 if(code==='STALE')return '车码已失效，请重新扫码。';
 if(code==='BUSY')return '正在处理，请稍候再试。';
 return '暂未完成，请重新尝试；也可直接使用官方 App 扫码。';
}
