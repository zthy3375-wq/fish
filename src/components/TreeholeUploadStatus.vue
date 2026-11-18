<script setup lang="ts">
import {computed} from 'vue';
import {RefreshCw,AlertCircle,Check} from 'lucide-vue-next';
import type {TreeholeUploadProgress} from '../services/treeholeUpload';
const props=defineProps<{progress:TreeholeUploadProgress;comment?:boolean;disabled?:boolean}>();
defineEmits<{retry:[]}>();
const label=computed(()=>props.progress.phase==='failed'?'发布未完成':props.progress.phase==='publishing'?(props.comment?'正在发布回复…':'正在发布帖子…'):'正在上传图片…');
</script>
<template>
 <div class="th-upload-status" :class="{'is-failed':progress.phase==='failed'}" role="status" aria-live="polite">
  <AlertCircle v-if="progress.phase==='failed'" :size="18"/><Check v-else-if="progress.total&&progress.completed===progress.total" :size="18"/><RefreshCw v-else :size="18" class="th-upload-spin"/>
  <div><strong>{{label}}</strong><span v-if="progress.total">已上传 {{progress.completed}} / {{progress.total}} 张图片<span v-if="progress.phase==='failed'">{{progress.completed?'，重试会复用已上传图片':'，配图与文字已保留'}}</span></span><span v-else-if="progress.phase==='failed'">文字已保留，可以重新发布。</span></div>
  <button v-if="progress.phase==='failed'" type="button" :disabled="disabled" @click="$emit('retry')">{{comment?'重试回复':'重试发布'}}</button>
 </div>
</template>
<style scoped>
.th-upload-status{display:flex;align-items:flex-start;gap:10px;padding:12px 14px;margin:12px 0;border-radius:12px;background:var(--color-highlight);color:var(--color-primary-strong)}
.th-upload-status>svg{flex-shrink:0;margin-top:2px}.th-upload-status strong,.th-upload-status span{display:block;font-size:12px;line-height:1.7}.th-upload-status strong{font-weight:600}.th-upload-status span span{display:inline}.th-upload-status.is-failed{color:var(--color-danger);background:var(--color-bg)}
.th-upload-status>div{flex:1;min-width:0}.th-upload-status>button{min-height:44px;flex-shrink:0;color:var(--color-primary);font-size:12px;font-weight:600;padding:0 4px}
.th-upload-spin{animation:th-upload-spin 1s linear infinite}@keyframes th-upload-spin{to{transform:rotate(360deg)}}@media(prefers-reduced-motion:reduce){.th-upload-spin{animation:none}}
</style>
