import {computed,ref} from 'vue';
import {defaultState,validateState,type ScheduleState} from '../domain/schedule';
import {readSchedule,writeSchedule} from '../services/schedule-storage';
export const schedule=ref<ScheduleState>(defaultState());
export const storageReady=ref(false),storageError=ref(''),saving=ref(false);
export const semester=computed(()=>schedule.value.semesters.find(s=>s.id===schedule.value.activeSemesterId)!);
let queue:Promise<unknown>=Promise.resolve();
export async function initSchedule(){storageReady.value=false;storageError.value='';try{const saved=await readSchedule();if(saved)schedule.value=saved;else await writeSchedule(schedule.value);storageReady.value=true}catch(e){storageError.value=`无法读取本地课表，未覆盖已有数据：${String(e)}`;throw e}}
export function changeSchedule(mutate:(draft:ScheduleState)=>void){const commit=async()=>{if(!storageReady.value)throw Error('本地存储尚未就绪，请先重试');saving.value=true;try{const latest=await readSchedule();const next=JSON.parse(JSON.stringify(latest??schedule.value)) as ScheduleState;mutate(next);next.updatedAt=new Date().toISOString();await writeSchedule(validateState(next));schedule.value=next;storageError.value=''}catch(e){storageError.value=`保存失败，修改未生效：${String(e)}`;throw e}finally{saving.value=false}};const job=queue.catch(()=>{}).then(async()=>{if(typeof navigator!=='undefined'&&navigator.locks)await navigator.locks.request('handan-schedule-write',async()=>{await commit()});else await commit()});queue=job;return job}
export async function refreshSchedule(){await queue.catch(()=>{});try{const saved=await readSchedule();if(saved&&saved.updatedAt!==schedule.value.updatedAt)schedule.value=saved}catch(e){storageError.value='读取失败，当前显示上次数据：'+String(e)}}
