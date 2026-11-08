import {ref} from 'vue';
import {Capacitor,registerPlugin} from '@capacitor/core';
export type AnalyticsFeature='schedule'|'tasks'|'learning'|'shower'|'wallet'|'water'|'laundry'|'parcel'|'grades'|'map';
export interface AnalyticsState {choice:'unset'|'on'|'off';deletePending:boolean;lastSent:number}
const client=registerPlugin<{getState():Promise<AnalyticsState>;setEnabled(o:{enabled:boolean}):Promise<AnalyticsState>;record(o:{feature:AnalyticsFeature}):Promise<AnalyticsState>;flush():Promise<AnalyticsState>;deleteData():Promise<AnalyticsState>}>('AnonymousAnalytics');
export const analytics=ref<AnalyticsState>({choice:'unset',deletePending:false,lastSent:0}),analyticsReady=ref(false),analyticsBusy=ref(false),analyticsError=ref('');
export const analyticsSupported=()=>Capacitor.isNativePlatform()&&Capacitor.isPluginAvailable('AnonymousAnalytics');
export async function refreshAnalytics(){if(!analyticsSupported())return;try{analytics.value=await client.getState()}catch{}finally{analyticsReady.value=true}}
export async function initAnalytics(){await refreshAnalytics();void flushAnalytics()}
export async function flushAnalytics(){if(!analyticsSupported())return;try{analytics.value=await client.flush()}catch{}}
export async function chooseAnalytics(enabled:boolean){if(analyticsBusy.value||!analyticsSupported())return;analyticsBusy.value=true;analyticsError.value='';try{analytics.value=await client.setEnabled({enabled})}catch{analyticsError.value='设置未保存，请重试'}finally{analyticsBusy.value=false}}
export async function recordFeature(feature:AnalyticsFeature){if(!analyticsSupported()||analytics.value.choice!=='on')return;try{await client.record({feature});void flushAnalytics()}catch{/* Metrics must never interrupt the user's action. */}}
export async function deleteAnalytics(){if(analyticsBusy.value||!analyticsSupported())return;analyticsBusy.value=true;analyticsError.value='';try{analytics.value=await client.deleteData()}catch{analyticsError.value='暂时无法删除，请联网后重试'}finally{analyticsBusy.value=false}}
