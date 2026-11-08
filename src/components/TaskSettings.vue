<script setup lang="ts">
import {ref} from 'vue';
import {taskSnapshot,tasksReady,tasksBusy,taskReminderStatus,changeTasks,enableTaskReminders} from '../composables/tasks';
import {taskStore} from '../services/task-store';
import {saveFile} from '../services/files';
import {beijingDay} from '../domain/agenda';
const message=ref('');
function report(e:unknown){message.value=(e as Error).message}
async function reminders(e:Event){try{await enableTaskReminders((e.target as HTMLInputElement).checked)}catch(e){report(e)}}
async function backup(){try{await saveFile('handan-tasks-'+beijingDay()+'.json',JSON.stringify(taskSnapshot.value,null,2));message.value='待办备份已生成'}catch(e){report(e)}}
async function restore(e:Event){const input=e.target as HTMLInputElement,file=input.files?.[0];if(!file)return;try{if(file.size>32*1024*1024)throw Error('备份超过32 MB');const data=JSON.parse(await file.text());await changeTasks(()=>taskStore.restore(data));message.value='备份已合并，已有任务和提醒开关保持原样'}catch(e){report(e)}finally{input.value=''}}
</script><template> <details class="task-settings"><summary>提醒与待办备份</summary><label><span>开启待办系统提醒<small>{{taskReminderStatus}}</small></span><input type="checkbox" aria-label="开启待办提醒" :checked="taskSnapshot.notificationsEnabled" :disabled="!tasksReady||tasksBusy" @change="reminders"/></label><div><button :disabled="!tasksReady" @click="backup">导出待办备份</button><label class="task-import">恢复待办备份<input type="file" accept=".json,application/json" aria-label="恢复待办备份" @change="restore"/></label></div><p>兼容旧版备份，合并时保留已有任务。个人任务与学校账号独立保存；最多500项，提醒按最近30条续排。</p></details>
<p v-if="message" role="status" class="task-hint">{{message}}</p></template>