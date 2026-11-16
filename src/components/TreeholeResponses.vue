<script setup lang="ts">
import type {TreeholePost,TreeholeResponseKind} from '../services/treehole';
defineProps<{post:TreeholePost;disabled?:boolean}>();
defineEmits<{choose:[kind:TreeholeResponseKind]}>();
const responses:Array<{kind:TreeholeResponseKind;label:string;icon:string}>=[{kind:'same',label:'我也一样',icon:'🤝'},{kind:'hug',label:'抱抱',icon:'🫂'},{kind:'useful',label:'有用',icon:'💡'}];
</script>
<template><div class="th-responses" role="group" aria-label="轻量回应"><button v-for="item in responses" :key="item.kind" type="button" :aria-label="item.label" :aria-pressed="post.myResponse===item.kind" :disabled="disabled" @click.stop="$emit('choose',item.kind)"><span aria-hidden="true">{{item.icon}}</span>{{item.label}}<small v-if="post.responseCounts?.[item.kind]">{{post.responseCounts[item.kind]}}</small></button></div></template>
<style scoped>
.th-responses{display:flex;gap:8px;flex-wrap:wrap;padding:6px 0}.th-responses button{display:inline-flex;align-items:center;justify-content:center;gap:5px;min-height:44px;padding:0 10px;border-radius:22px;background:var(--color-bg);color:var(--color-muted);font-size:max(12px,.75rem);transition:background 140ms,color 140ms}.th-responses button[aria-pressed=true]{background:var(--color-tint);color:var(--color-primary);box-shadow:inset 0 0 0 1px currentColor}.th-responses button>span{font-size:17px}.th-responses small{font-size:inherit;font-variant-numeric:tabular-nums}.th-responses button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}.th-responses button:disabled{opacity:.6}@media(prefers-reduced-motion:reduce){.th-responses button{transition:none}}
</style>
