import {computed,ref,toRaw} from 'vue';
import {Preferences} from '@capacitor/preferences';
import {AcademicSyncEngine,emptyAcademicCache,validateAcademicCache,termKey,type AcademicCache} from '../services/academic-sync-engine';
import {handanAcademicClient,schoolConnectionSupported,type SchoolTerm} from '../services/handan-academic-client';
import {schedule} from './schedule';
const KEY='handan.academic.cache.v050';
export const academicCache=ref<AcademicCache>(emptyAcademicCache());
export const academicBusy=ref(false),academicError=ref('');
export const schoolTerm=computed(()=>academicCache.value.selectedTerm?academicCache.value.terms[academicCache.value.selectedTerm!]:null);
async function commit(c:AcademicCache){await Preferences.set({key:KEY,value:JSON.stringify(c)});academicCache.value=c}
const engine=new AcademicSyncEngine(handanAcademicClient,()=>structuredClone(toRaw(academicCache.value)),commit,()=>schedule.value.semesters);
let initialized=false,lastAuto=0;
export async function initAcademic(){if(initialized)return;try{const {value}=await Preferences.get({key:KEY});if(value)academicCache.value=validateAcademicCache(JSON.parse(value));initialized=true}catch{academicError.value='无法读取学校缓存，个人课表仍可使用'}}
export async function syncAcademic(login=false,term?:SchoolTerm){
 if(!schoolConnectionSupported()){academicError.value='学校连接仅支持 Android 客户端';return}
 if(academicBusy.value)return;
 academicBusy.value=true;academicError.value='';
 try{await engine.sync(term,login);lastAuto=Date.now();if(academicCache.value.session==='expired')academicError.value='学校登录已过期，请重新连接'}
 catch(e){if((e as {code?:string}).code!=='CANCELLED')academicError.value='学校连接未完成，已保留上次数据'}finally{academicBusy.value=false;if(login&&academicCache.value.connected)setTimeout(()=>void syncAcademic(),0)}
}
export function autoSyncAcademic(){if(academicCache.value.connected&&Date.now()-lastAuto>120000)return syncAcademic()}
export async function disconnectAcademic(){if(academicBusy.value)return;try{await engine.logout();academicError.value=''}catch{academicError.value='退出未完成，请重试'}}
export async function selectSchoolTerm(t:SchoolTerm){if(academicBusy.value)return;const key=termKey(t);if(academicCache.value.terms[key]?.data)await commit({...toRaw(academicCache.value),selectedTerm:key,exams:academicCache.value.examsByTerm?.[key]??{data:null,updatedAt:null,error:'当前学期考试尚未更新'}});await syncAcademic(false,t)}
