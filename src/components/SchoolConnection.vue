<script setup lang="ts">
import {computed} from 'vue';
import {GraduationCap,ChevronDown} from 'lucide-vue-next';
import {academicCache,academicBusy,academicError,schoolTerm,syncAcademic,disconnectAcademic,selectSchoolTerm} from '../composables/handan-academic';
import {schoolConnectionSupported} from '../services/handan-academic-client';
const props=defineProps<{compact?:boolean;collapsible?:boolean}>();
const emit=defineEmits<{connected:[]}>();
const supported=schoolConnectionSupported();
const status=computed(()=>!supported?'网页版 · 学校直连待适配':academicBusy.value?'正在同步':academicCache.value.session==='expired'?'登录已过期':academicCache.value.connected?(schoolTerm.value?.data?'已连接邯郸学院':'已登录 · 课表尚未同步'):'连接邯郸学院');
const accountStatus=computed(()=>!supported?'请在 Android 应用内连接':academicBusy.value?'正在同步':academicCache.value.session==='expired'?'登录已过期':academicCache.value.connected?(schoolTerm.value?.data?'已连接 · 课表已缓存':'已登录 · 等待同步'):'登录后同步课表与成绩');
const issue=computed(()=>academicError.value||academicCache.value.lastError||academicCache.value.grades.error||academicCache.value.exams.error);
const stamp=(v?:string|null)=>v?new Date(v).toLocaleString('zh-CN',{hour12:false}):'尚未同步';
async function connect(){await syncAcademic(true);if(academicCache.value.connected)emit('connected')}
function termChange(e:Event){const [xnm,xqm]=(e.target as HTMLSelectElement).value.split('-');selectSchoolTerm({xnm,xqm})}
</script>
<template>
 <section class="school-connection" :class="{compact:props.compact,'school-collapsible':props.collapsible}" aria-label="学校连接">
  <div class="school-status"><GraduationCap v-if="props.collapsible" class="school-account-icon" :size="22" aria-hidden="true"/><div><strong>{{props.collapsible?'邯郸学院':status}}</strong><small v-if="props.collapsible" class="school-account-state" :class="{connected:academicCache.connected&&academicCache.session!=='expired'}">{{accountStatus}}</small><small v-else-if="!props.compact">{{!supported?'个人课表和文件导入仍可使用':schoolTerm?.updatedAt?'课表更新 '+stamp(schoolTerm.updatedAt):'首次连接后自动同步本人教务数据'}}</small><span v-if="props.compact&&schoolTerm?.updatedAt" class="sync-time">课表更新 {{stamp(schoolTerm.updatedAt)}}</span></div>
   <button v-if="supported&&(!academicCache.connected||academicCache.session==='expired')" class="primary" :disabled="academicBusy" @click="connect">{{academicCache.connected?'重新登录':props.collapsible?'连接':'连接邯郸学院'}}</button>
   <button v-else-if="supported" class="secondary" :disabled="academicBusy" @click="syncAcademic()">{{academicBusy?'同步中…':'刷新'}}</button>
  </div>
  <p v-if="!supported" class="inline-note" role="status">网页版暂不能直接登录邯郸学院教务系统或自动同步真实课表。可以手动维护、导入个人课程；学校账号请通过官方教务网站访问。</p>
  <p v-if="academicError&&!props.compact&&!props.collapsible" class="inline-note" role="status">{{academicError}}</p>
  <p v-if="academicCache.lastError&&!props.compact&&!props.collapsible" class="inline-note" role="status">{{academicCache.lastError}}</p>
  <details v-if="(props.compact||props.collapsible)&&issue" class="sync-issue"><summary>部分数据暂未更新</summary><p>{{issue}}</p></details>
  <component :is="props.collapsible?'details':'div'" v-if="!props.compact" class="school-account-details">
   <summary v-if="props.collapsible">账号与同步详情<ChevronDown :size="15" aria-hidden="true"/></summary>
   <label v-if="academicCache.semesters.data?.length" class="form-label">学校学期<select :value="academicCache.selectedTerm" :disabled="academicBusy" @change="termChange"><option v-for="t in academicCache.semesters.data" :key="`${t.xnm}-${t.xqm}`" :value="`${t.xnm}-${t.xqm}`">{{t.xnm}}–{{Number(t.xnm)+1}} {{t.xqm==='3'?'秋季':'春季'}}</option></select></label>
   <div v-for="(item,key) in {课表:schoolTerm,成绩:academicCache.grades,考试:academicCache.exams,学籍:academicCache.profile}" :key="key" class="school-module"><strong>{{key}}</strong><span>{{item?.error||stamp(item?.updatedAt)}}</span></div>
   <p class="footnote">{{supported?'数据只保存在本机。学校密码由官方页面处理，会话过期后需重新登录。':'网页版个人课表保存在本机浏览器；请定期导出备份，避免清理浏览器数据后丢失。'}}</p>
   <button v-if="academicCache.connected" class="text-button danger" :disabled="academicBusy" @click="disconnectAcademic">退出学校账号</button>
  </component>
 </section>
</template>

<style scoped>
.school-collapsible{padding:0;margin:0;overflow:hidden;border:0;background:transparent}.school-collapsible .school-status{padding:14px;gap:10px}.school-account-icon{color:var(--color-primary);flex-shrink:0}.school-collapsible .school-status>div{flex:1}.school-collapsible .school-status strong{font-size:14px}.school-collapsible .school-status button{min-height:36px;padding:7px 12px;font-size:12px}.school-account-state{font-size:11px;margin-top:4px}.school-account-state.connected::before{content:'';display:inline-block;width:5px;height:5px;border-radius:50%;background:var(--color-success);margin-right:5px;vertical-align:middle}.school-account-details>summary{display:flex;align-items:center;justify-content:space-between;list-style:none;padding:10px 14px;min-height:40px;border-top:1px solid var(--color-divider);font-size:11px;color:var(--color-muted);cursor:pointer}.school-account-details>summary::-webkit-details-marker{display:none}.school-account-details[open]>summary svg{transform:rotate(180deg)}.school-collapsible .school-account-details>*:not(summary){margin-inline:14px}.school-collapsible .school-account-details>.footnote{font-size:11px;line-height:1.6}.school-collapsible .school-account-details>.danger{min-height:44px;margin-bottom:6px}.school-collapsible .inline-note,.school-collapsible .sync-issue{margin:0 14px 10px;font-size:11px}.school-collapsible .school-module{font-size:11px}.school-collapsible .form-label{margin-top:12px}
</style>
