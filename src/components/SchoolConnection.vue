<script setup lang="ts">
import {computed} from 'vue';
import {academicCache,academicBusy,academicError,schoolTerm,syncAcademic,disconnectAcademic,selectSchoolTerm} from '../composables/handan-academic';
const props=defineProps<{compact?:boolean}>();
const emit=defineEmits<{connected:[]}>();
const status=computed(()=>academicBusy.value?'正在同步':academicCache.value.session==='expired'?'登录已过期':academicCache.value.connected?(schoolTerm.value?.data?'已连接邯郸学院':'已登录 · 课表尚未同步'):'连接邯郸学院');
const issue=computed(()=>academicError.value||academicCache.value.lastError);
const stamp=(v?:string|null)=>v?new Date(v).toLocaleString('zh-CN',{hour12:false}):'尚未同步';
async function connect(){await syncAcademic(true);if(academicCache.value.connected)emit('connected')}
function termChange(e:Event){const [xnm,xqm]=(e.target as HTMLSelectElement).value.split('-');selectSchoolTerm({xnm,xqm})}
</script>
<template>
 <section class="school-connection" :class="{compact:props.compact}" aria-label="学校连接">
  <div class="school-status"><div><strong>{{status}}</strong><small v-if="!props.compact">{{schoolTerm?.updatedAt?'课表更新 '+stamp(schoolTerm.updatedAt):'首次连接后自动同步本人教务数据'}}</small></div>
   <button v-if="!academicCache.connected||academicCache.session==='expired'" class="primary" :disabled="academicBusy" @click="connect">{{academicCache.connected?'重新登录':'连接邯郸学院'}}</button>
   <button v-else class="secondary" :disabled="academicBusy" @click="syncAcademic()">{{academicBusy?'同步中…':'刷新'}}</button>
  </div>
  <details v-if="issue && props.compact" class="sync-issue"><summary>部分数据暂未更新</summary><p role="status">{{issue}}</p></details>
  <p v-else-if="issue" class="inline-note" role="status">{{issue}}</p>
  <small v-else-if="props.compact && schoolTerm?.updatedAt" class="sync-time">课表更新 {{stamp(schoolTerm.updatedAt)}}</small>
  <template v-if="!props.compact">
   <label v-if="academicCache.semesters.data?.length" class="form-label">学校学期<select :value="academicCache.selectedTerm" :disabled="academicBusy" @change="termChange"><option v-for="t in academicCache.semesters.data" :key="`${t.xnm}-${t.xqm}`" :value="`${t.xnm}-${t.xqm}`">{{t.xnm}}–{{Number(t.xnm)+1}} {{t.xqm==='3'?'秋季':'春季'}}</option></select></label>
   <div v-for="(item,key) in {课表:schoolTerm,成绩:academicCache.grades,考试:academicCache.exams,学籍:academicCache.profile}" :key="key" class="school-module"><strong>{{key}}</strong><span>{{item?.error||stamp(item?.updatedAt)}}</span></div>
   <p class="footnote">数据只保存在本机。学校密码由官方页面处理，会话过期后需重新登录。</p>
   <button v-if="academicCache.connected" class="text-button danger" :disabled="academicBusy" @click="disconnectAcademic">退出学校账号</button>
  </template>
 </section>
</template>
