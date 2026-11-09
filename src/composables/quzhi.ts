import {ref} from 'vue';
import {quzhiClient, quzhiSupported, quzhiIssue, quzhiMonth, type QuzhiSnapshot, type QuzhiBathCode} from '../services/quzhi-client';

export const quzhi = ref<QuzhiSnapshot>({connected:false,expired:false,phone:''});
export const quzhiBusy = ref(false);
export const quzhiError = ref('');
export const quzhiReady = ref(false);
let initialization: Promise<void> | undefined;
export function initQuzhi(): Promise<void> {
  if (initialization) return initialization;
  initialization = (async()=>{
    if (!quzhiSupported()) { quzhiReady.value=true; return }
    try { quzhi.value=await quzhiClient.getSnapshot() }
    catch { quzhiError.value='暂时无法读取趣智账户，请重新打开页面'; initialization=undefined }
    finally { quzhiReady.value=true }
  })();
  return initialization;
}
async function update(action: ()=>Promise<QuzhiSnapshot>): Promise<boolean> {
  if (quzhiBusy.value) return false;
  if (!quzhiSupported()) {quzhiError.value=quzhiIssue('UNAVAILABLE');return false}
  quzhiBusy.value=true; quzhiError.value='';
  try {quzhi.value=await action();return true}
  catch (error) {const code=(error as {code?:string}).code; if(code!=='CANCELLED')quzhiError.value=quzhiIssue(code); return false}
  finally {quzhiBusy.value=false}
}
export async function refreshQuzhi(month=quzhiMonth()) {
  await initQuzhi();
  if (!quzhi.value.connected || quzhi.value.expired) return false;
  if (!/^20\d{2}-(0[1-9]|1[0-2])$/.test(month)) return false;
  return update(()=>quzhiClient.refresh({month}));
}
export async function connectQuzhi(month=quzhiMonth()) {
  await initQuzhi();
  if (await update(()=>quzhiClient.login())) await refreshQuzhi(month);
}
export async function disconnectQuzhi() {return update(()=>quzhiClient.logout())}
export async function rechargeQuzhi(): Promise<boolean> {
  if (!quzhiSupported() || quzhiBusy.value || !quzhi.value.connected || quzhi.value.expired) return false;
  quzhiBusy.value=true;quzhiError.value='';
  try {return (await quzhiClient.openRecharge()).opened}
  catch(error){quzhiError.value=quzhiIssue((error as {code?:string}).code);return false}
  finally{quzhiBusy.value=false}
}

export async function loadQuzhiBathCode():Promise<QuzhiBathCode>{
 if(!quzhiSupported()||!quzhiReady.value||!quzhi.value.connected||quzhi.value.expired)throw Error('请先连接趣智校园');
 if(quzhiBusy.value)throw Error('趣智操作正在进行，请稍候');
 quzhiBusy.value=true;
 try{return await quzhiClient.getBathCode()}
 catch(error){
  const kind=(error as {code?:string}).code;
  if(kind==='AUTH'){
   quzhi.value={...quzhi.value,expired:true};
  }
  throw Error(kind==='FORMAT'?'平台未返回可识别的完整洗澡码，请到趣智校园核对':quzhiIssue(kind));
 }
 finally{quzhiBusy.value=false}
}
