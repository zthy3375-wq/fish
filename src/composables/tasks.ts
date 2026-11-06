import {reactive,ref,toRaw} from 'vue';
import {Capacitor} from '@capacitor/core';
import {LocalNotifications} from '@capacitor/local-notifications';
import {emptyTasks,taskReminderPlan,beijingDay,type TaskSnapshot} from '../domain/agenda';
import {taskStore} from '../services/task-store';
export const taskSnapshot=ref(emptyTasks()),tasksReady=ref(false),tasksBusy=ref(false),taskError=ref(''),taskReminderStatus=ref('待办提醒未开启');
export const agendaView=reactive({date:beijingDay(),range:7,filter:'all',showCompleted:false,editor:false,editing:'',draft:{title:'',course:'',deadline:'',notes:'',remindMinutes:30}});
let writes=0;
let initJob:Promise<void>|null=null,notificationQueue:Promise<unknown>=Promise.resolve();
export function initTasks(){if(tasksReady.value)return Promise.resolve();if(initJob)return initJob;initJob=(async()=>{try{taskSnapshot.value=await taskStore.load();tasksReady.value=true;taskError.value='';await reconcileTaskReminders()}catch{taskError.value='本机待办读取失败，原数据未覆盖';throw Error(taskError.value)}finally{initJob=null}})();return initJob}
export async function changeTasks(action:()=>Promise<TaskSnapshot>){if(!tasksReady.value)throw Error('待办尚未读取，请先重试');tasksBusy.value=++writes>0;try{const next=await action();taskSnapshot.value=next;taskError.value='';await reconcileTaskReminders();return next}catch(e){taskError.value='保存未完成，已保留上次待办：'+(e as Error).message;throw e}finally{tasksBusy.value=--writes>0}}
export async function reloadTasks(){try{taskSnapshot.value=await taskStore.reload();tasksReady.value=true;taskError.value='';await reconcileTaskReminders()}catch{taskError.value='待办读取失败，当前保留上次记录'}}
export function reconcileTaskReminders(request=false){const snapshot=JSON.parse(JSON.stringify(toRaw(taskSnapshot.value))) as TaskSnapshot;const job=notificationQueue.catch(()=>{}).then(async()=>{
 if(!Capacitor.isNativePlatform()){taskReminderStatus.value='浏览器可保存待办，后台提醒请使用 Android 客户端';return}
 try{let p=await LocalNotifications.checkPermissions();if(request&&snapshot.notificationsEnabled&&p.display!=='granted')p=await LocalNotifications.requestPermissions();const pending=await LocalNotifications.getPending();const own=pending.notifications.filter(n=>n.extra?.owner==='handan-task'||n.id>=410000&&n.id<410030);if(own.length)await LocalNotifications.cancel({notifications:own.map(n=>({id:n.id}))});if(!snapshot.notificationsEnabled){taskReminderStatus.value='待办提醒已关闭';return}if(p.display!=='granted'){taskReminderStatus.value='通知权限未允许，待办已保存，可在页面查看';return}const plan=taskReminderPlan(snapshot);if(plan.length)await LocalNotifications.schedule({notifications:plan});taskReminderStatus.value=`已安排 ${plan.length} 条待办提醒；打开 App 时续排，系统节电可能延迟`}catch{taskReminderStatus.value='系统提醒调度失败，待办仍保存在本机'}
 });notificationQueue=job;return job}
export async function enableTaskReminders(enabled:boolean){await changeTasks(()=>taskStore.change(s=>{s.notificationsEnabled=enabled}));if(enabled)await reconcileTaskReminders(true)}
