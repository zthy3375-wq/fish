<script setup lang="ts">
import {onBeforeUnmount, ref} from 'vue';
import {ArrowUpRight, PackageCheck} from 'lucide-vue-next';
import {openParcelShortcut, parcelLaunchMessage, parcelProviders, parcelShortcutsSupported, type ParcelProvider, type ParcelOpenMode} from '../services/parcel-shortcuts';

const supported = parcelShortcutsSupported();
const opening = ref<ParcelProvider>();
const message = ref('');
const lastProvider = ref<ParcelProvider>();
let disposed = false;
onBeforeUnmount(() => { disposed = true });
async function open(provider: ParcelProvider, mode: ParcelOpenMode = 'app') {
  if (!supported || opening.value) return;
  opening.value = provider;
  lastProvider.value = provider;
  message.value = '';
  try {
    const result = await openParcelShortcut(provider, mode);
    if (!disposed) message.value = parcelLaunchMessage(result);
  } catch {
    if (!disposed) message.value = parcelLaunchMessage({provider, status: 'unavailable'});
  } finally {
    if (!disposed) opening.value = undefined;
  }
}
</script>

<template>
  <section class="parcel-shortcuts" aria-label="菜鸟驿站出库码" :aria-busy="!!opening">
    <div class="parcel-heading"><PackageCheck :size="19" aria-hidden="true"/><strong>菜鸟驿站取件</strong><span>官方 App 快捷入口</span></div>
    <div class="parcel-actions">
      <button v-for="provider in parcelProviders" :key="provider.id" type="button" :disabled="!supported || !!opening" @click="open(provider.id)">
        <span>{{provider.label}}</span><ArrowUpRight :size="16" aria-hidden="true"/>
      </button>
    </div>
    <p class="parcel-note">跳转淘宝或拼多多，使用该 App 内的登录账号。本应用不读取、保存或生成出库身份码。</p>
    <button v-if="supported && lastProvider" type="button" class="parcel-compat" :disabled="!!opening" @click="open(lastProvider, 'system')">没有跳转？系统兼容打开{{lastProvider==='taobao'?'淘宝':'拼多多'}}</button>
    <p v-if="supported && lastProvider" class="parcel-note">兼容方式由系统选择打开的应用，部分鸿蒙环境可能进入官方网页。</p>
    <p v-if="!supported" class="parcel-status">请在 Android 客户端中使用出库码快捷入口。</p>
    <p v-if="opening || message" class="parcel-status" role="status" aria-live="polite">{{opening ? '正在请求打开官方 App…' : message}}</p>
  </section>
</template>

<style scoped>
.parcel-shortcuts{padding:14px 16px;border-top:1px solid var(--color-border)}
.parcel-heading{display:flex;align-items:center;gap:8px;flex-wrap:wrap;color:var(--color-text)}
.parcel-heading strong{font-size:14px;font-weight:600}.parcel-heading>span{font-size:11px;color:var(--color-muted);margin-left:auto}
.parcel-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:12px}
.parcel-actions button{display:flex;justify-content:center;align-items:center;gap:6px;min-height:44px;padding:9px 6px;border:1px solid var(--color-border);border-radius:10px;background:var(--color-bg);color:var(--color-text);font-size:13px;font-weight:550}
.parcel-actions button:disabled{opacity:.55}.parcel-actions button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}
.parcel-note,.parcel-status{font-size:11px;line-height:1.65;margin:10px 0 0;color:var(--color-muted);overflow-wrap:anywhere}
.parcel-status{color:var(--color-text)}
.parcel-compat{min-height:44px;margin-top:8px;padding:8px 0;color:var(--color-primary);font-size:12px;text-align:left}.parcel-compat:disabled{opacity:.55}
</style>
