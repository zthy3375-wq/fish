import {ref} from 'vue';
import {pangguaiNative,pangguaiSupported,pangguaiError,type PangguaiSnapshot,type PangguaiDevice} from '../services/pangguai-client';
export const pangguai=ref<PangguaiSnapshot>({connected:false,expired:false,phone:''});
export const pgBusy=ref(false),pgReady=ref(false),pgError=ref('');
let initialization:Promise<void>|undefined,lastAttempt=0;
export async function initPangguai(){
 if(initialization)return initialization;
 initialization=(async()=>{try{if(pangguaiSupported())pangguai.value=await pangguaiNative.getSnapshot()}catch{pgError.value='账户暂时无法读取，请重试';initialization=undefined}finally{pgReady.value=true}})();return initialization;
}
async function operation<T>(action:()=>Promise<T>):Promise<T|undefined>{
 if(pgBusy.value||!pangguaiSupported())return;
 pgBusy.value=true;pgError.value='';try{return await action()}catch(e){const code=(e as {code?:string})?.code;if(code!=='CANCELLED')pgError.value=pangguaiError(code);return undefined}finally{pgBusy.value=false}
}
export async function refreshPangguai(automatic=false){
 await initPangguai();if(!pangguai.value.connected||pangguai.value.expired||pgBusy.value)return;
 if(automatic&&Date.now()-lastAttempt<60_000)return;
 lastAttempt=Date.now();const result=await operation(()=>pangguaiNative.refresh());if(result)pangguai.value=result;
}
export async function connectPangguai(){const result=await operation(()=>pangguaiNative.login());if(result){pangguai.value=result;await refreshPangguai()}}
export async function disconnectPangguai(){const result=await operation(()=>pangguaiNative.logout());if(result){pangguai.value=result;lastAttempt=0}}
export async function scanPangguai():Promise<PangguaiDevice|undefined>{return operation(()=>pangguaiNative.scan())}
export async function rechargePangguai(merchantId:string){return operation(()=>pangguaiNative.openRecharge({merchantId}))}

export async function quoteLaundry(skuId?:string){return operation(()=>pangguaiNative.quoteLaundry(skuId?{skuId}:{existing:true}))}
async function transactionOperation(action:()=>Promise<PangguaiSnapshot>){
 return operation(async()=>{try{const result=await action();pangguai.value=result;return result}finally{try{pangguai.value=await pangguaiNative.getSnapshot()}catch{}}});
}
export async function startLaundry(quoteId:string,method:string){return transactionOperation(()=>pangguaiNative.startLaundry({quoteId,method}))}
export async function pollLaundry(){return transactionOperation(()=>pangguaiNative.pollLaundry())}
export async function cancelLaundry(sessionId:string){return transactionOperation(()=>pangguaiNative.cancelLaundry({sessionId}))}

export async function prepareWater(skuId:string){return operation(()=>pangguaiNative.prepareWater({skuId}))}
export async function startWater(quoteId:string){return transactionOperation(()=>pangguaiNative.startWater({quoteId}))}
export async function pollWater(){return transactionOperation(()=>pangguaiNative.pollWater())}
export async function endWater(sessionId:string){return transactionOperation(()=>pangguaiNative.endWater({sessionId}))}
export async function confirmPhysicalWaterEnd(sessionId:string){return transactionOperation(()=>pangguaiNative.confirmPhysicalWaterEnd({sessionId}))}
export async function openWaterPaymentSetup(){return operation(()=>pangguaiNative.openWaterPaymentSetup())}
