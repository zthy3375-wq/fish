import {Capacitor,registerPlugin} from '@capacitor/core';
export interface CampusFix {latitude:number;longitude:number;accuracy:number;timestamp:number}
const native=registerPlugin<{locate():Promise<CampusFix>;cancel():Promise<void>}>('CampusLocation');
export function validCampusFix(f:CampusFix,now=Date.now()){
 return Number.isFinite(f.latitude)&&Number.isFinite(f.longitude)&&f.latitude>=-90&&f.latitude<=90&&f.longitude>=-180&&f.longitude<=180&&Number.isFinite(f.accuracy)&&f.accuracy>0&&Number.isFinite(f.timestamp)&&now-f.timestamp>=-5000&&now-f.timestamp<=60000;
}
export async function locateCampus():Promise<CampusFix>{
 if(!Capacitor.isNativePlatform())throw Error('请在 Android 应用中使用个人定位');
 const fix=await native.locate();if(!validCampusFix(fix))throw Error('定位结果已过期或无效，请重试');return fix;
}
export async function stopCampusLocation(){if(Capacitor.isNativePlatform())await native.cancel()}
