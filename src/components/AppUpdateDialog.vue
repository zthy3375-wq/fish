<script setup lang="ts">
import {computed,nextTick,onMounted,onUnmounted,ref,watch} from 'vue';
import {App} from '@capacitor/app';
import {updateState as state,updatesOpen,updateHint,updateActionBusy,updateDeferred,updateDeferredReason,checkUpdates,dismissUpdate,downloadUpdate,installUpdate,refreshUpdateState} from '../composables/updates';
const dialog=ref<HTMLElement>();
const busy=computed(()=>updateActionBusy.value||['checking','downloading'].includes(state.value.stage));
let timer:ReturnType<typeof setInterval>;
onMounted(()=>{timer=setInterval(()=>{if(state.value.stage==='downloading')void refreshUpdateState()},800)});
onUnmounted(()=>clearInterval(timer));
watch(updatesOpen,async open=>{if(open){await nextTick();dialog.value?.focus()}});
function key(e:KeyboardEvent){
 if(e.key==='Escape'){e.stopPropagation();e.preventDefault();dismissUpdate()}
 if(e.key==='Tab'){
  const items=[...dialog.value!.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
  if(e.shiftKey&&(document.activeElement===items[0]||document.activeElement===dialog.value)){e.preventDefault();items.at(-1)?.focus()}
  else if(!e.shiftKey&&document.activeElement===items.at(-1)){e.preventDefault();items[0]?.focus()}
 }
}
</script>
<template><Teleport to="body"><div v-if="updatesOpen" class="update-overlay" @keydown="key"><section ref="dialog" class="update-dialog" role="dialog" aria-modal="true" aria-labelledby="update-title" tabindex="-1">
<img src="/icon.svg" alt="" width="52" height="52"/><p class="update-eyebrow">邯院通 · 应用更新</p>
<h2 id="update-title">{{state.mandatory?'需要更新后继续使用':state.available?'发现新版本':state.stage==='checking'?'正在检查更新':state.error?'检查更新失败':'检查更新'}}</h2>
<p v-if="state.available&&state.release">{{state.currentVersion}} → {{state.release.versionName}} <span>· {{(state.release.sizeBytes/1048576).toFixed(1)}} MB</span></p>
<p v-else-if="state.stage!=='checking'&&!state.error&&!updateHint">当前版本 {{state.currentVersion}}，已是最新版本</p>
<ul v-if="state.available"><li v-for="(line,index) in state.release?.notes" :key="index">{{line}}</li></ul>
<p v-if="updateDeferred" role="status" class="update-note">{{updateDeferredReason||'当前正在编辑或处理接水、支付，可以查看更新；请完成当前操作后再下载和安装。'}}</p>
<p v-else-if="state.mandatory" class="update-note">此版本已停止支持，请安装新版本。更新会保留本机数据。</p>
<div v-if="state.stage==='downloading'" role="status"><progress :value="state.progress" max="100" aria-label="更新下载进度"/><p>正在下载 {{state.progress}}% · 请保持应用打开</p></div>
<p v-if="state.error" role="alert" class="update-error">{{state.error}}</p><p v-if="updateHint" role="status">{{updateHint}}</p>
<button v-if="state.available&&state.stage==='ready'" class="primary" :disabled="busy||updateDeferred" @click="installUpdate">安装更新</button>
<button v-else-if="state.available" class="primary" :disabled="busy||updateDeferred" @click="downloadUpdate">{{state.stage==='downloading'?'正在下载…':'下载更新'}}</button>
<button class="text-button" :disabled="busy" @click="checkUpdates(true)">{{state.stage==='checking'?'正在检查…':'重新检查'}}</button>
<button v-if="!state.mandatory||updateDeferred" class="text-button" @click="dismissUpdate">{{updateDeferred?'返回应用':state.available?'稍后再说':'关闭'}}</button>
<button v-else class="text-button" @click="App.exitApp()">退出应用</button>
</section></div></Teleport></template>
<style scoped>
.update-overlay{position:fixed;inset:0;z-index:3000;background:#18243d70;display:flex;align-items:center;justify-content:center;padding:24px 20px;padding-top:max(24px,var(--safe-top));padding-bottom:max(24px,var(--safe-bottom));overflow:auto;overscroll-behavior:contain}.update-dialog{width:100%;max-width:390px;max-height:100%;overflow:auto;background:var(--color-surface,#fff);color:var(--color-text,#18243d);border-radius:24px;padding:24px;box-sizing:border-box;box-shadow:0 18px 70px #14213d30;outline:none}.update-dialog img{border-radius:14px}.update-eyebrow{font-size:12px;color:var(--color-muted);margin:14px 0 6px}.update-dialog h2{font-size:22px;margin:0 0 12px}.update-dialog p,.update-dialog li{font-size:13px;line-height:1.7;overflow-wrap:anywhere}.update-dialog ul{padding-left:18px}.update-dialog button{width:100%;min-height:44px;margin-top:8px}.update-dialog progress{width:100%;accent-color:#3158ba}.update-note{background:var(--color-surface-soft,#f2f5fc);padding:12px;border-radius:12px}.update-error{color:#b04444}
</style>
