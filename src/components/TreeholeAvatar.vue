<script setup lang="ts">
import {computed} from 'vue';
import {VenetianMask} from 'lucide-vue-next';
const props=withDefaults(defineProps<{name:string;anonymous?:boolean;size?:number}>(),{anonymous:false,size:42});
const palette=['#ece6fb','#e0eee9','#f8e8df','#e3edf8','#f5e3ec'];
const ink=['#685298','#3f7566','#976a48','#4f7197','#985978'];
const tone=computed(()=>Array.from(props.name).reduce((n,c)=>(n*31+c.codePointAt(0)!)>>>0,0)%palette.length);
const initial=computed(()=>Array.from(props.name.trim())[0]||'同');
</script>
<template><span class="treehole-avatar" :class="{'is-anonymous':anonymous}" :style="{width:size+'px',height:size+'px','--avatar-bg':palette[tone],'--avatar-ink':ink[tone]}" aria-hidden="true"><VenetianMask v-if="anonymous" :size="size*.51"/><span v-else>{{initial}}</span><i v-if="anonymous"/></span></template>
<style scoped>
.treehole-avatar{position:relative;flex-shrink:0;display:inline-flex;align-items:center;justify-content:center;border-radius:35%;background:var(--avatar-bg);color:var(--avatar-ink);font-size:17px;font-weight:650;letter-spacing:0;box-shadow:inset 0 0 0 1px #ffffff50}.treehole-avatar.is-anonymous{border-radius:50%;background:var(--avatar-bg)}.treehole-avatar i{position:absolute;right:-1px;bottom:1px;width:10px;height:10px;border:2px solid var(--color-surface);border-radius:50%;background:var(--avatar-ink)}
</style>
