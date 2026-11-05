<script setup lang="ts">
import {computed,ref,onMounted,onUnmounted} from 'vue';
import {ShieldCheck,ExternalLink,RefreshCw,LogIn,LogOut} from 'lucide-vue-next';
import {type AcademicSyncSnapshot} from '../services/academic-connection';
import {getAuthorizedAcademicConnector,getAcademicConnectionController} from '../services/authorized-connector-registry';

const emit=defineEmits<{synced:[snapshot:AcademicSyncSnapshot];disconnected:[]}>();
const provider=getAuthorizedAcademicConnector();
const controller=getAcademicConnectionController();
const phase=ref(controller?.state.phase??'disconnected');
const error=ref('');
const busy=ref(false);
const syncedAt=ref<string|null>(null);
const status=computed(()=>!provider?'未接入学校授权接口':({
  disconnected:'尚未绑定',authorizing:'正在等待学校认证',
  ready:'已获得学校授权',syncing:'正在同步本人教务数据',
  expired:'学校登录状态已失效',error:'连接发生错误'
} as Record<string,string>)[phase.value]);
function syncState(){if(controller){phase.value=controller.state.phase;syncedAt.value=controller.state.syncedAt;error.value=controller.state.error||''}}
async function connect(){if(!controller||busy.value)return;busy.value=true;error.value='';try{
  const connected=await controller.connect();syncState();
  if(!connected&&phase.value==='disconnected')error.value='尚未收到学校授权确认；完成学校认证后可再次检查连接状态';
}catch(e){error.value=String(e)}finally{busy.value=false;syncState()}
if(controller.state.phase==='ready')await refresh();}
async function refresh(){if(!controller||busy.value)return;busy.value=true;try{
  const snapshot=await controller.refresh();syncState();if(snapshot)emit('synced',snapshot);
}finally{busy.value=false;syncState()}}
async function disconnect(){if(!controller||busy.value)return;busy.value=true;try{
  await controller.disconnect();emit('disconnected');
}finally{busy.value=false;syncState()}}
function resume(){if(controller&&!busy.value&&document.visibilityState==='visible'&&phase.value==='ready')void refresh()}
onMounted(()=>document.addEventListener('visibilitychange',resume));
onUnmounted(()=>document.removeEventListener('visibilitychange',resume));
</script>
<template>
<section class="academic-connection">
  <span class="icon-tile"><ShieldCheck :size="26"/></span>
  <h2>教务账号连接</h2>
  <p class="muted">仅同步学生本人有权访问、且学校允许第三方使用的数据。fish 不收集或保存学校密码。</p>
  <div class="connection-status" role="status">
    <strong>{{status}}</strong>
    <small v-if="syncedAt">上次同步：{{new Date(syncedAt).toLocaleString('zh-CN')}}</small>
    <small v-else>个人课表与演示数据仍可独立使用</small>
  </div>
  <p v-if="error" class="form-error" role="alert">{{error}}</p>
  <template v-if="provider">
    <p class="muted">授权服务：{{provider.displayName}}。请在学校提供的认证页面完成验证。</p>
    <div class="connection-actions">
      <button v-if="phase==='disconnected'||phase==='expired'||phase==='error'" class="primary" :disabled="busy" @click="connect"><LogIn :size="17"/>使用学校官方认证</button>
      <button v-if="phase==='ready'||phase==='syncing'" class="secondary" :disabled="busy" @click="refresh"><RefreshCw :size="17"/>同步我的教务数据</button>
      <button v-if="phase==='ready'||phase==='expired'||phase==='error'" class="text-button" :disabled="busy" @click="disconnect"><LogOut :size="17"/>解除绑定</button>
    </div>
  </template>
  <p v-else class="inline-note">当前版本尚未获得邯郸学院对第三方认证及教务数据接口的技术确认，因此不能直接通过学校账号同步。下面的官方入口仅用于学生自己查看信息，并不代表已完成绑定。</p>
  <a class="official-link" href="https://jwgl.hdc.edu.cn/xtgl/login_slogin.html" target="_blank" rel="noopener noreferrer">
    <span><strong>打开邯郸学院教务平台</strong><small>由学校网站处理账号、密码和验证码</small></span>
    <ExternalLink :size="19"/>
  </a>
  <p class="footnote">未使用模拟登录、网页 Cookie 提取或后台账号密码代登。未来启用真实连接器后，认证和数据来源必须单独验证。</p>
</section>
</template>
<style scoped>
.academic-connection{display:flex;flex-direction:column;gap:12px}
.academic-connection h2{margin:0;font-size:20px}
.academic-connection p{line-height:1.65;margin:0}
.connection-status{border:1px solid var(--color-border);background:var(--color-surface);border-radius:14px;padding:15px;display:flex;flex-direction:column;gap:6px}
.connection-status small{color:var(--color-muted)}
.connection-actions{display:flex;flex-wrap:wrap;gap:10px}
.connection-actions button{display:inline-flex;align-items:center;gap:7px;padding:11px}
</style>
