import {ref} from 'vue';
import {Capacitor} from '@capacitor/core';
export const offlineStatus=ref(Capacitor.isNativePlatform()?'原生包内资源可离线打开':'离线资源尚未准备完成');
export function prepareOffline(){if(Capacitor.isNativePlatform())return;if(!('serviceWorker' in navigator)){offlineStatus.value='当前预览环境不支持离线启动；本机课表仍可保存';return}navigator.serviceWorker.register('/sw.js').then(()=>navigator.serviceWorker.ready).then(()=>{offlineStatus.value='离线资源已缓存；断网可重新打开已保存课表'}).catch(()=>{offlineStatus.value='离线资源缓存失败；请联网后重试'})}
