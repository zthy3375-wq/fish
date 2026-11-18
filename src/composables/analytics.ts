import {ref} from 'vue';
import {Capacitor,registerPlugin} from '@capacitor/core';

interface LegacyState {hasHistory:boolean;deletePending:boolean}
const client=registerPlugin<{getState():Promise<LegacyState>;deleteData():Promise<LegacyState>}>('AnonymousAnalytics');
export const legacy=ref<LegacyState>({hasHistory:false,deletePending:false}),deleting=ref(false),deletionError=ref('');
export async function readLegacyState(){
 if(!Capacitor.isPluginAvailable('AnonymousAnalytics'))return;
 try{legacy.value=await client.getState()}catch{/* Other campus services remain available. */}
}
export async function deleteLegacyHistory(){
 if(deleting.value)return;
 deleting.value=true;deletionError.value='';
 try{legacy.value=await client.deleteData()}catch{deletionError.value='历史记录暂未删除，可以联网后重试。';await readLegacyState()}
 finally{deleting.value=false}
}
export async function retryLegacyDeletion(){
 await readLegacyState();
 if(legacy.value.deletePending)await deleteLegacyHistory();
}
