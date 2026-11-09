<script setup lang="ts">
import {ref} from 'vue';
import {Capacitor, registerPlugin} from '@capacitor/core';
import {UsersRound, ArrowUpRight, Copy} from 'lucide-vue-next';
const group = '434217654';
const native = registerPlugin<{open():Promise<{opened:boolean}>;copy():Promise<void>}>('CommunityGroup');
const message=ref('');
const busy=ref(false);
async function join(){
  if(busy.value)return;
  busy.value=true;
  try{
    if(Capacitor.getPlatform()!=='android'||!Capacitor.isPluginAvailable('CommunityGroup')){
      message.value='请在 Android 应用内打开 QQ，或复制群号搜索加入。';return;
    }
    const result=await native.open();
    message.value=result.opened?'已请求打开 QQ。如未进入群资料页，请复制群号搜索加入。':'暂时无法打开 QQ，请安装或打开 QQ 后搜索群号加入。';
  }catch{message.value='暂时无法打开 QQ，可以复制群号搜索加入。'}
  finally{busy.value=false}
}
async function copy(){
  try{
    if(Capacitor.getPlatform()==='android'&&Capacitor.isPluginAvailable('CommunityGroup'))await native.copy();
    else await navigator.clipboard.writeText(group);
    message.value='群号已复制，打开 QQ 搜索 434217654 即可。';
  }catch{message.value='复制失败，请长按群号 434217654 手动复制。'}
}
</script>
<template>
<section class="community-group" aria-label="QQ 交流群">
  <button class="community-join" type="button" :disabled="busy" @click="join">
    <UsersRound :size="23" aria-hidden="true"/><span><strong>加入 QQ 交流群</strong><small>交流使用体验 · 反馈问题与建议</small></span><ArrowUpRight :size="19" aria-hidden="true"/>
  </button>
  <div class="community-number"><span>群号 <b>{{group}}</b></span><button type="button" @click="copy"><Copy :size="14" aria-hidden="true"/>复制群号</button></div>
  <p v-if="message" role="status">{{message}}</p>
</section>
</template>
<style scoped>
.community-group{border:1px solid var(--color-border);background:var(--color-surface);border-radius:18px;margin:14px 0;overflow:hidden;color:var(--color-text)}
.community-join{width:100%;display:flex;align-items:center;gap:12px;text-align:left;padding:16px;background:transparent;color:inherit;border:0;min-height:70px}.community-join>svg:first-child{color:var(--color-primary)}.community-join>svg:last-child{margin-left:auto;flex-shrink:0}.community-join span{display:grid;gap:5px}.community-join strong{font-size:15px}.community-join small{font-size:12px;color:var(--color-muted)}
.community-number{display:flex;align-items:center;justify-content:space-between;gap:8px;border-top:1px solid var(--color-border);padding:0 16px;font-size:12px;color:var(--color-muted)}.community-number b{color:var(--color-text);user-select:text;-webkit-user-select:text;letter-spacing:.5px}.community-number button{display:flex;align-items:center;gap:5px;border:0;background:transparent;color:var(--color-primary);min-height:44px;font-size:12px}.community-group p{font-size:12px;line-height:1.6;margin:0;padding:0 16px 12px}.community-group button:focus-visible{outline:2px solid var(--color-primary);outline-offset:-3px}
</style>
