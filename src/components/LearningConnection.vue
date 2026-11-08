<script setup lang="ts">
import {version as appVersion} from '../../package.json';
import {saveFile} from '../services/files';
import {computed} from 'vue';
import {BookOpen,RefreshCw} from 'lucide-vue-next';
import {learningCache,learningTasks,learningBusy,learningReady,learningIssue,syncLearning,disconnectLearning,openLearningPortal} from '../composables/learning';
import {chaoxingSupported} from '../services/chaoxing-client';
const props=defineProps<{compact?:boolean}>();
const pending=computed(()=>learningTasks.value.filter(t=>t.platformStatus==='pending').length);
const status=computed(()=>learningBusy.value?'学习通正在分批同步':!learningCache.value.connected?'连接学习通':learningCache.value.session==='expired'?'学习通登录已过期':'学习通已连接');
const issue=computed(()=>learningIssue());
const updated=computed(()=>learningCache.value.updatedAt?new Date(learningCache.value.updatedAt).toLocaleString('zh-CN',{hour12:false,timeZone:'Asia/Shanghai'}):'作业尚未同步');
async function exportFeedback(){try{const c=learningCache.value;await saveFile('handan-learning-feedback.json',JSON.stringify({version:appVersion,at:new Date().toISOString(),session:c.session,courseCount:c.courses.length,taskCount:c.items.length,errorCodes:[...new Set(Object.values(c.issues))],syncProgress:{planned:c.plannedCount,processed:c.completedCount,remaining:c.remaining},diagnostics:c.diagnostics},null,2))}catch{ /* Data remains local if sharing is canceled. */ }}
const courseIssueCount=computed(()=>Object.keys(learningCache.value.issues).filter(k=>k.includes('/')).length);
</script>
<template>
<section class="learning-connection" :class="{compact:props.compact}" aria-label="学习通连接">
 <div class="learning-status"><BookOpen :size="18"/><div><strong>{{status}}</strong><small>{{pending}} 项待交 · {{learningCache.courses.length}} 门课程 · {{updated}}</small></div>
 <button v-if="chaoxingSupported()&&(!learningCache.connected||learningCache.session==='expired'||learningCache.issues.connection==='VERIFY')" class="text-button" :disabled="learningBusy||!learningReady" @click="syncLearning({login:true,force:true})">{{learningCache.issues.connection==='VERIFY'?'完成验证并继续':learningCache.connected?'重新连接学习通':'连接学习通'}}</button><button v-else-if="chaoxingSupported()" class="icon-button" aria-label="刷新学习通" :disabled="learningBusy" @click="syncLearning({force:true})"><RefreshCw :size="16"/></button></div>
 <p v-if="!chaoxingSupported()" class="learning-hint">学习通官方登录与直连请使用 Android 客户端。</p><p v-if="issue" role="status" class="learning-hint">{{issue}}<template v-if="courseIssueCount">（{{courseIssueCount}} 门课程）</template></p><p v-if="learningCache.remaining" class="learning-hint">还剩 {{learningCache.remaining}} 门课程排队更新，已读取的任务可直接查看。</p>
 <details v-if="!props.compact" class="learning-manage-details"><summary>账号与同步管理</summary>
 <div v-if="(learningCache.connected||learningCache.lastAttempt)&&!props.compact" class="learning-manage"><button class="text-button" :disabled="learningBusy" @click="openLearningPortal">打开学习通官方页面</button><button class="text-button danger" :disabled="learningBusy" @click="disconnectLearning">退出学习通连接</button></div>
 <button v-if="!props.compact&&Object.keys(learningCache.issues).length" class="text-button" @click="exportFeedback">导出连接反馈（不含账号或任务内容）</button><p v-if="!props.compact" class="learning-hint">仅查询本人数据；账号在官方页面认证，会话由原生端管理。提交状态以平台为准，计划、备注与提醒只保存在本机。退出将清除该连接的缓存与规划，个人待办和教务数据保留。</p>
 </details>
</section>
</template>
