<script setup lang="ts">
import {nextTick,onMounted,onUnmounted,ref,watch} from 'vue';
import {RefreshCw} from 'lucide-vue-next';

const props=defineProps<{pageKey:string;loading:boolean;error:string;disabled:boolean}>();
const emit=defineEmits<{load:[]}>();
const element=ref<HTMLElement>();
let observer:IntersectionObserver|undefined,frame=0,lastAttempt='';
function load(automatic=false){
 if(props.disabled||props.loading||(automatic&&props.error))return;
 if(automatic&&lastAttempt===props.pageKey)return;
 lastAttempt=props.pageKey;emit('load');
}
async function checkPosition(){
 await nextTick();cancelAnimationFrame(frame);
 frame=requestAnimationFrame(()=>{
  const bounds=element.value?.getBoundingClientRect();
  if(bounds&&bounds.top<window.innerHeight+280&&bounds.bottom>0)load(true);
 });
}
watch(()=>[props.pageKey,props.loading,props.disabled],checkPosition,{flush:'post'});
onMounted(()=>{
 if(typeof IntersectionObserver==='undefined')return;
 observer=new IntersectionObserver(entries=>{if(entries.some(entry=>entry.isIntersecting))void checkPosition();},{rootMargin:'280px 0px'});
 if(element.value)observer.observe(element.value);
});
onUnmounted(()=>{observer?.disconnect();cancelAnimationFrame(frame);});
</script>
<template>
 <div ref="element" class="th-page-end" :aria-busy="loading" aria-live="polite">
  <span v-if="loading" class="th-page-loading"><RefreshCw :size="15"/>正在加载更多帖子…</span>
  <template v-else-if="error"><p>{{error}}，已保留当前帖子。</p><button :disabled="disabled" @click="load()">重试加载</button></template>
  <button v-else :disabled="disabled" @click="load()">加载更多帖子</button>
 </div>
</template>
<style scoped>
.th-page-end{text-align:center;padding:18px 12px 30px;min-height:88px;font-size:12px;color:var(--color-muted)}
.th-page-end p{font-size:12px;line-height:1.7;margin:0 0 5px}.th-page-end button{min-height:44px;padding:0 18px;color:var(--color-primary)}
.th-page-loading{display:flex;align-items:center;justify-content:center;gap:7px;padding-top:12px}.th-page-loading svg{animation:th-page-spin 1s linear infinite}
@keyframes th-page-spin{to{transform:rotate(360deg)}}@media(prefers-reduced-motion:reduce){.th-page-loading svg{animation:none}}
</style>
