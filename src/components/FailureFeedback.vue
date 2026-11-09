<script setup lang="ts">
import {ref} from 'vue';
import {FileDown,ChevronRight} from 'lucide-vue-next';
import {Capacitor,registerPlugin} from '@capacitor/core';
import {version} from '../../package.json';
import {academicCache,initAcademic} from '../composables/handan-academic';
import {learningCache,initLearning} from '../composables/learning';
import {buildFailureFeedback} from '../services/failure-feedback';
import {saveFile} from '../services/files';
const busy=ref(false),message=ref('');
const native=registerPlugin<{sendToQQ(options:{report:string}):Promise<{target:string}>}>('FeedbackShare');
async function exportFeedback(system=false){
 if(busy.value)return;
 busy.value=true;message.value='';
 try{
  const initialized=await Promise.allSettled([initAcademic(),initLearning()]);
  const report={...buildFailureFeedback(academicCache.value,learningCache.value,version,Capacitor.getPlatform()),cacheRead:{academic:initialized[0].status,learning:initialized[1].status}};
  const text=JSON.stringify(report,null,2);
  if(!system&&Capacitor.getPlatform()==='android'&&Capacitor.isPluginAvailable('FeedbackShare')){
   const result=await native.sendToQQ({report:text});
   message.value=result.target==='qq'?'已请求打开 QQ，请选择联系人或交流群并确认发送。':'QQ 暂不可用，已打开系统分享，请选择接收人。';
  }else{
   await saveFile('hanyuantong-failure-feedback.json',text);
   message.value=Capacitor.isNativePlatform()?'反馈文件已生成，请在分享窗口选择 QQ 和接收人。':'反馈文件已下载，请通过 QQ 发送给开发者。';
  }
 }catch{message.value='导出未完成。若取消了分享，可重新点击导出；原数据保留。'}
 finally{busy.value=false}
}
</script>
<template>
<section class="failure-feedback" aria-label="故障反馈">
 <button type="button" :disabled="busy" @click="exportFeedback(false)"><FileDown :size="21" aria-hidden="true"/><span><strong>{{busy?'正在生成反馈…':'导出并发送到 QQ'}}</strong><small>课表、学习通失败时，发送给联系人或交流群</small></span><ChevronRight :size="17" aria-hidden="true"/></button>
 <p>仅导出故障诊断，不含账号、密码及课程作业正文。</p>
 <p v-if="message" role="status">{{message}}</p>
 <button class="feedback-system" type="button" :disabled="busy" @click="exportFeedback(true)">其他分享方式</button>
</section>
</template>
<style scoped>
.failure-feedback{background:var(--color-surface);border:1px solid var(--color-border);border-radius:16px;margin:12px 0;overflow:hidden}.failure-feedback button{display:flex;align-items:center;gap:12px;width:100%;min-height:68px;padding:14px 16px;border:0;text-align:left;background:transparent;color:var(--color-text)}.failure-feedback button>svg:first-child{color:var(--color-primary);flex-shrink:0}.failure-feedback button>svg:last-child{margin-left:auto;flex-shrink:0}.failure-feedback span{display:grid;gap:5px}.failure-feedback strong{font-size:14px}.failure-feedback small,.failure-feedback p{font-size:11px;line-height:1.6;color:var(--color-muted)}.failure-feedback p{margin:0;padding:0 16px 12px}.failure-feedback button:focus-visible{outline:2px solid var(--color-primary);outline-offset:-3px}
.failure-feedback .feedback-system{min-height:44px;padding:8px 16px;color:var(--color-primary);font-size:12px;border-top:1px solid var(--color-border)}
</style>
