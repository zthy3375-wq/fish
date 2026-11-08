<script setup lang="ts">
import {onBeforeUnmount, ref} from 'vue';
import {ArrowUpRight, Droplets} from 'lucide-vue-next';
import {openPangguaiOfficial, pangguaiLaunchMessage, pangguaiOfficialSupported, type PangguaiPage} from '../services/pangguai-official';

const supported = pangguaiOfficialSupported();
const opening = ref<PangguaiPage>();
const message = ref('');
let disposed = false;
onBeforeUnmount(() => { disposed = true });
async function open(page: PangguaiPage) {
  if (!supported || opening.value) return;
  opening.value = page;
  message.value = '';
  try {
    const result = await openPangguaiOfficial(page);
    if (!disposed) message.value = pangguaiLaunchMessage(result);
  } catch {
    if (!disposed) message.value = pangguaiLaunchMessage({page, status: 'unavailable'});
  } finally {
    if (!disposed) opening.value = undefined;
  }
}
</script>

<template>
  <section class="pangguai-official" aria-label="胖乖官方钱包与充值页面" :aria-busy="!!opening">
    <div class="pangguai-heading"><Droplets :size="19" aria-hidden="true"/><strong>胖乖生活</strong><span>洗衣 · 饮水</span></div>
    <div class="pangguai-actions">
      <button type="button" :disabled="!supported || !!opening" @click="open('wallet')"><span>官方钱包</span><ArrowUpRight :size="16" aria-hidden="true"/></button>
      <button type="button" :disabled="!supported || !!opening" @click="open('operators')"><span>官方充值页面</span><ArrowUpRight :size="16" aria-hidden="true"/></button>
    </div>
    <p class="pangguai-note">在胖乖官方页面登录、查看余额并选择实际运营商。此处不显示余额，也不判断到账；充值兼容性待手机验证，无法继续时可改用官方 App 或小程序。</p>
    <p class="pangguai-note">官方页面会话可能保留在本机，关闭不等于退出。可在窗口内清除本机胖乖网页数据，不影响教务或官方账号绑定。本应用不读取密码、验证码或支付结果。</p>
    <p v-if="!supported" class="pangguai-status">请在 Android 客户端中打开胖乖官方页面。</p>
    <p v-if="opening || message" class="pangguai-status" role="status" aria-live="polite">{{opening ? '正在请求打开胖乖官方页面…' : message}}</p>
  </section>
</template>

<style scoped>
.pangguai-official{padding:14px 16px;border-top:1px solid var(--color-border)}
.pangguai-heading{display:flex;align-items:center;gap:8px;flex-wrap:wrap;color:var(--color-text)}
.pangguai-heading strong{font-size:14px;font-weight:600}.pangguai-heading>span{font-size:11px;color:var(--color-muted);margin-left:auto}
.pangguai-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:12px}
.pangguai-actions button{display:flex;justify-content:center;align-items:center;gap:6px;min-height:44px;padding:9px 6px;border:1px solid var(--color-border);border-radius:10px;background:var(--color-bg);color:var(--color-text);font-size:13px;font-weight:550}
.pangguai-actions button:disabled{opacity:.55}.pangguai-actions button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}
.pangguai-note,.pangguai-status{font-size:11px;line-height:1.65;margin:10px 0 0;color:var(--color-muted);overflow-wrap:anywhere}
.pangguai-status{color:var(--color-text)}
</style>
