import {computed,ref} from 'vue';
import {Capacitor,registerPlugin} from '@capacitor/core';
import {version} from '../../package.json';
export interface UpdateRelease {versionCode:number;versionName:string;minSupportedVersionCode:number;minSdk:number;apkUrl:string;sha256:string;sizeBytes:number;notes:string[]}
export interface UpdateState {currentVersion:string;currentCode:number;stage:'idle'|'checking'|'downloading'|'ready';progress:number;error:string;available:boolean;mandatory:boolean;release?:UpdateRelease;checkedAt:number}
const native=registerPlugin<{getState():Promise<UpdateState>;check():Promise<UpdateState>;download():Promise<UpdateState>;install():Promise<{status:'permission'|'installer'}>}>('AppUpdate');
export const updateState=ref<UpdateState>({currentVersion:version,currentCode:101,stage:'idle',progress:0,error:'',available:false,mandatory:false,checkedAt:0});
export const updateRequested=ref(false),updateDeferred=ref(false),updateHint=ref(''),updateActionBusy=ref(false);
export const manualUpdateRequested=ref(false),updateDeferredReason=ref('');
export const updatesOpen=computed(()=>(!updateDeferred.value||manualUpdateRequested.value)&&(updateRequested.value||updateState.value.mandatory));
export const updateSupported=()=>Capacitor.isNativePlatform()&&Capacitor.isPluginAvailable('AppUpdate');
let lastAttempt=0,checking=false,dismissed=0;
export async function refreshUpdateState(){if(updateSupported())try{updateState.value=await native.getState()}catch{/* Retain the last known policy on bridge failure. */}}
export async function checkUpdates(manual=false){
 if(manual){manualUpdateRequested.value=true;updateRequested.value=true;updateHint.value=''}
 if(!updateSupported()){if(manual)updateHint.value='请在邯院通 Android 正式版中检查更新';return}
 if(checking||updateState.value.stage==='downloading'||(!manual&&Date.now()-lastAttempt<300000))return;
 lastAttempt=Date.now();checking=true;updateState.value={...updateState.value,stage:'checking',error:''};
 try{updateState.value=await native.check();if(updateState.value.available&&updateState.value.release?.versionCode!==dismissed)updateRequested.value=true}
 catch{updateState.value={...updateState.value,stage:'idle',error:'暂时无法检查更新，请重试'}}finally{checking=false}
}
export async function initializeUpdates(){await refreshUpdateState();await checkUpdates()}
export function dismissUpdate(){if(updateState.value.mandatory&&!updateDeferred.value)return;manualUpdateRequested.value=false;dismissed=updateState.value.release?.versionCode??0;updateRequested.value=false}
export async function downloadUpdate(){if(updateDeferred.value){updateHint.value='请先完成当前操作，再下载更新';return}if(updateActionBusy.value)return;updateActionBusy.value=true;updateHint.value='';try{updateState.value=await native.download()}catch{updateHint.value='下载未开始，请重试'}finally{updateActionBusy.value=false}}
export async function installUpdate(){if(updateActionBusy.value||updateDeferred.value)return;updateActionBusy.value=true;try{const r=await native.install();updateHint.value=r.status==='permission'?'请开启“允许来自此来源的应用”，返回后再次点击安装':'请在系统界面确认安装；取消后可再次点击安装'}catch{updateHint.value='安装未完成，请重新下载或重试';await refreshUpdateState()}finally{updateActionBusy.value=false}}
