<script setup lang="ts">
import {computed,onMounted,onUnmounted,ref} from 'vue';
import type {TreeholePoll} from '../services/treehole';
const props=defineProps<{poll:TreeholePoll;disabled?:boolean;pending?:boolean;locked?:boolean}>();
defineEmits<{vote:[optionId:string|null]}>();
const now=ref(Date.now());let timer:ReturnType<typeof setInterval>|undefined;
onMounted(()=>{timer=setInterval(()=>now.value=Date.now(),15000);});onUnmounted(()=>clearInterval(timer));
const ended=computed(()=>props.poll.closed||Date.parse(props.poll.closesAt)<=now.value);
const deadline=computed(()=>new Date(props.poll.closesAt).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit',hour12:false}));
const percent=(count:number)=>props.poll.total?Math.round(count*100/props.poll.total):0;
</script>
<template>
 <section class="th-poll" aria-label="帖子投票" @click.stop>
  <div class="th-poll-heading"><span>投票 · 单选</span><small>{{ended?'已截止':locked?'已暂停':'进行中'}}</small></div>
  <h3>{{poll.question}}</h3>
  <button v-for="option in poll.options" :key="option.id" type="button" class="th-poll-option" :aria-label="'投票：'+option.text" :aria-pressed="poll.myOptionId===option.id" :disabled="disabled||pending||locked||ended" @click="$emit('vote',option.id)">
   <span class="th-poll-fill" :style="{width:percent(option.count)+'%'}"/><span class="th-poll-label">{{poll.myOptionId===option.id?'✓ ':''}}{{option.text}}</span><span class="th-poll-number">{{option.count}} 票 · {{percent(option.count)}}%</span>
  </button>
  <div class="th-poll-footer"><span>{{pending?'正在提交…':poll.total+' 人参与'}} · {{deadline}} 截止</span><button v-if="poll.myOptionId!==null&&!ended&&!locked" type="button" :disabled="disabled||pending" @click="$emit('vote',null)">撤回投票</button></div>
  <p class="th-poll-note">只展示统计结果，截止前可改选或撤回。</p>
 </section>
</template>
<style scoped>
.th-poll{margin:14px 0;padding:14px;border:1px solid var(--color-divider);border-radius:12px;background:white}.th-poll-heading{display:flex;justify-content:space-between;gap:8px;color:var(--color-primary);font-size:12px}.th-poll-heading small{color:var(--color-muted);font-size:12px}h3{font-size:16px;line-height:1.55;margin:10px 0 12px;overflow-wrap:anywhere}.th-poll-option{isolation:isolate;position:relative;display:flex;align-items:center;gap:10px;width:100%;min-height:48px;margin:8px 0;padding:10px 12px;border:1px solid var(--color-divider);border-radius:9px;text-align:left;overflow:hidden}.th-poll-option[aria-pressed=true]{border-color:var(--color-primary);color:var(--color-primary)}.th-poll-option:disabled{opacity:1}.th-poll-fill{position:absolute;inset:0 auto 0 0;background:var(--color-tint);z-index:-1;transition:width .2s ease}.th-poll-label{flex:1;min-width:0;overflow-wrap:anywhere;font-size:14px;line-height:1.6}.th-poll-number{font-size:11px;white-space:nowrap;font-variant-numeric:tabular-nums}.th-poll-footer{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:4px;color:var(--color-muted);font-size:11px;line-height:1.7}.th-poll-footer button{color:var(--color-primary);min-height:40px}.th-poll-note{font-size:11px;color:var(--color-muted);margin:4px 0 0;line-height:1.6}@media(prefers-reduced-motion:reduce){.th-poll-fill{transition:none}}
</style>
