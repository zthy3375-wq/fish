<script setup lang="ts">
import {computed,ref} from 'vue';
import {Lightbulb,Smile,HeartHandshake,SmilePlus} from 'lucide-vue-next';
import type {TreeholePost,TreeholeResponseKind} from '../services/treehole';
const props=defineProps<{post:TreeholePost;disabled?:boolean;joyEnabled?:boolean}>();
const emit=defineEmits<{choose:[kind:TreeholeResponseKind]}>();
const responses=[{kind:'useful',label:'有用',icon:Lightbulb},{kind:'joy',label:'欢乐',icon:Smile},{kind:'hug',label:'抱抱',icon:HeartHandshake}] as const;
const current=computed(()=>responses.find(x=>x.kind===props.post.myResponse));
const total=computed(()=>responses.reduce((sum,x)=>sum+(props.post.responseCounts?.[x.kind]||0),0));
const panel=ref<HTMLDetailsElement>(),motion=ref<TreeholeResponseKind|null>(null);
function choose(kind:TreeholeResponseKind){
 if(!panel.value||props.disabled)return;
 motion.value=props.post.myResponse!==kind?kind:null;
 if(kind!=='joy'||props.joyEnabled){panel.value.open=false;panel.value.querySelector('summary')?.focus({preventScroll:true})}
 emit('choose',kind);
}
</script>
<template>
 <details ref="panel" class="th-responses" role="group" aria-label="轻量回应" @click.stop @keydown.esc.prevent="panel && (panel.open=false)" @focusout="panel && !panel.contains($event.relatedTarget as Node) && (panel.open=false)">
  <summary aria-label="选择回应" :class="{chosen:current}">
   <span :class="motion===current?.kind?'pulse-'+motion:''" @animationend.self="motion=null"><component :is="current?.icon||SmilePlus" :size="18"/></span>{{current?.label||'回应'}}<small v-if="total">{{current?post.responseCounts?.[current.kind]:total}}</small>
  </summary>
  <div class="response-options"><button v-for="item in responses" :key="item.kind" type="button" :aria-label="item.label" :aria-pressed="post.myResponse===item.kind" :aria-disabled="disabled||item.kind==='joy'&&!joyEnabled" :disabled="disabled" @click.stop="choose(item.kind)"><component :is="item.icon" :size="20"/><span>{{item.label}}</span><small v-if="post.responseCounts?.[item.kind]">{{post.responseCounts[item.kind]}}</small></button></div>
 </details>
</template>
<style scoped>
.th-responses{position:relative;color:var(--color-muted);font-size:13px}.th-responses summary{min-height:44px;display:inline-flex;align-items:center;gap:6px;cursor:pointer;list-style:none}.th-responses summary::-webkit-details-marker{display:none}.th-responses summary>span{display:grid;place-items:center}.chosen,button[aria-pressed=true]{color:var(--color-primary-strong)}.response-options{position:absolute;bottom:100%;left:0;z-index:5;display:flex;gap:3px;padding:5px;background:var(--color-surface);border:1px solid var(--color-border);border-radius:14px;box-shadow:0 6px 20px #251b3620}.response-options button{display:grid;grid-template-columns:auto auto;align-items:center;justify-items:center;min-height:50px;min-width:58px;padding:4px;font:inherit}.response-options button svg{grid-column:1/-1}.response-options button span:only-of-type:last-child{grid-column:1/-1}.response-options button[aria-pressed=true]{background:var(--color-tint);border-radius:9px}.th-responses small{font-variant-numeric:tabular-nums}
@media(prefers-reduced-motion:no-preference){.pulse-useful{animation:light 340ms ease-out}.pulse-joy{animation:lift 340ms ease-out}.pulse-hug{animation:embrace 380ms ease-in-out}}
@keyframes light{40%{color:#ad7914;filter:drop-shadow(0 0 3px #d79835)}}@keyframes lift{35%{transform:translateY(-3px) rotate(-12deg)}68%{transform:rotate(6deg)}}@keyframes embrace{40%{transform:scaleX(.84) scaleY(1.08)}}
</style>
