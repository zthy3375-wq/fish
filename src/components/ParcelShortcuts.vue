<script setup lang="ts">
import {onBeforeUnmount, ref} from 'vue';
import {ArrowUpRight, PackageCheck} from 'lucide-vue-next';
import {openEmbeddedParcel, openParcelShortcut, parcelLaunchMessage, parcelProviders, parcelShortcutsSupported, type ParcelProvider} from '../services/parcel-shortcuts';

const supported = parcelShortcutsSupported();
const opening = ref<ParcelProvider>();
const embeddedOpening = ref(false);
const message = ref('');
let disposed = false;
onBeforeUnmount(() => { disposed = true });
async function open(provider: ParcelProvider) {
  if (!supported || opening.value) return;
  opening.value = provider;
  embeddedOpening.value = false;
  message.value = '';
  try {
    const result = await openParcelShortcut(provider);
    if (!disposed) message.value = parcelLaunchMessage(result);
  } catch {
    if (!disposed) message.value = parcelLaunchMessage({provider, status: 'unavailable'});
  } finally {
    if (!disposed) opening.value = undefined;
  }
}
async function embedded(provider: ParcelProvider) {
  if (!supported || opening.value) return;
  opening.value = provider; embeddedOpening.value = true; message.value = '';
  const opened = await openEmbeddedParcel(provider);
  if (disposed) return;
  message.value = opened ? '已打开应用内取件页面，请在官方网页登录并查看实际取件信息。' : '暂时无法打开应用内页面，请使用下方官方 App 入口。';
  opening.value = undefined;
}
</script>

<template>
  <section class="parcel-shortcuts" aria-label="菜鸟驿站出库码" :aria-busy="!!opening">
    <div class="parcel-heading"><PackageCheck :size="19" aria-hidden="true"/><strong>我的快递</strong><span>应用内查看</span></div>
    <p class="parcel-note">首次在官方网页登录。进入后点“全部待取”，按平台和驿站集中查看已读取的取件码；身份码在对应平台查看。</p>
    <div class="parcel-actions parcel-embedded">
      <button type="button" :disabled="!supported || !!opening" @click="embedded('taobao')">淘宝取件页面</button>
      <button type="button" :disabled="!supported || !!opening" @click="embedded('pinduoduo')">拼多多取件页面</button>
    </div>
    <p class="parcel-note">也可使用官方 App：</p>
    <div class="parcel-actions">
      <button v-for="provider in parcelProviders" :key="provider.id" type="button" :disabled="!supported || !!opening" @click="open(provider.id)">
        <span>{{provider.label}}</span><ArrowUpRight :size="16" aria-hidden="true"/>
      </button>
    </div>
    <p class="parcel-note">取件信息来自官方页面，仅在本机展示；登录、验证码在官方网页完成。拼多多网页登录可能使官方 App 需要重新登录。</p>
    <p v-if="!supported" class="parcel-status">请在 Android 客户端中使用出库码快捷入口。</p>
    <p v-if="opening || message" class="parcel-status" role="status" aria-live="polite">{{opening ? (embeddedOpening ? '正在打开应用内取件页面…' : '正在请求打开官方 App…') : message}}</p>
  </section>
</template>

<style scoped>
.parcel-shortcuts{padding:14px 16px;border-top:1px solid var(--color-border)}
.parcel-heading{display:flex;align-items:center;gap:8px;flex-wrap:wrap;color:var(--color-text)}
.parcel-heading strong{font-size:14px;font-weight:600}.parcel-heading>span{font-size:11px;color:var(--color-muted);margin-left:auto}
.parcel-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:12px}
.parcel-actions button{display:flex;justify-content:center;align-items:center;gap:6px;min-height:44px;padding:9px 6px;border:1px solid var(--color-border);border-radius:10px;background:var(--color-bg);color:var(--color-text);font-size:13px;font-weight:550}
.parcel-actions button:disabled{opacity:.55}.parcel-actions button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}
.parcel-embedded button{background:var(--color-primary);color:white;border-color:transparent;min-height:48px}
.parcel-note,.parcel-status{font-size:11px;line-height:1.65;margin:10px 0 0;color:var(--color-muted);overflow-wrap:anywhere}
.parcel-status{color:var(--color-text)}
</style>
