<script setup lang="ts">
import {Lightbulb,Smile,HeartHandshake} from 'lucide-vue-next';
import type {TreeholePost,TreeholeResponseKind} from '../services/treehole';
defineProps<{post:TreeholePost;disabled?:boolean;joyEnabled?:boolean}>();
defineEmits<{choose:[kind:TreeholeResponseKind]}>();
const responses=[{kind:'useful',label:'有用',icon:Lightbulb},{kind:'joy',label:'欢乐',icon:Smile},{kind:'hug',label:'抱抱',icon:HeartHandshake}] as const;
function count(n:number){return n>=10000?(n/10000).toFixed(1).replace(/\.0$/,'')+'万':n>=1000?(n/1000).toFixed(1).replace(/\.0$/,'')+'千':String(n);}
</script>
<template><div class="th-responses" role="group" aria-label="轻量回应"><button v-for="item in responses" :key="item.kind" type="button" :aria-label="item.label" :aria-pressed="post.myResponse===item.kind" :aria-disabled="disabled||item.kind==='joy'&&!joyEnabled" :disabled="disabled" @click.stop="$emit('choose',item.kind)"><component :is="item.icon" :size="18" aria-hidden="true"/><span>{{item.label}}</span><small v-if="post.responseCounts?.[item.kind]" :title="String(post.responseCounts[item.kind])">{{count(post.responseCounts[item.kind]!)}}</small></button></div></template>
<style scoped>
.th-responses{display:flex;align-items:center;gap:2px;flex-wrap:wrap;padding:0}.th-responses button{display:inline-flex;align-items:center;justify-content:center;gap:4px;min-height:44px;min-width:48px;padding:0 5px;border-radius:10px;color:var(--color-muted);font-size:12px;white-space:nowrap;-webkit-tap-highlight-color:transparent;transition:background 160ms ease,color 160ms ease}.th-responses button[aria-pressed=true]{background:var(--color-tint);color:var(--color-primary)}.th-responses small{font-size:11px;font-variant-numeric:tabular-nums}.th-responses button:active:not(:disabled){background:var(--color-bg)}.th-responses button[aria-pressed=true] svg{animation:response-pop 180ms ease-out}.th-responses button:focus{outline:none}.th-responses button:focus-visible{outline:2px solid var(--color-primary);outline-offset:1px}.th-responses button:disabled{opacity:.5}
@keyframes response-pop{50%{transform:scale(1.12)}}@media(prefers-reduced-motion:reduce){.th-responses button,.th-responses svg{transition:none!important;animation:none!important}}
</style>
