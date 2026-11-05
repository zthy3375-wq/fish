<script setup lang="ts">
import {House,GraduationCap,UserRound} from 'lucide-vue-next';
import type {Page} from '../composables/navigation';
const props=defineProps<{page:Page}>();defineEmits<{navigate:[page:Page]}>();
const tabs=[{id:'home' as Page,label:'首页',icon:House},{id:'academic' as Page,label:'教务',icon:GraduationCap},{id:'profile' as Page,label:'我的',icon:UserRound}];
</script>
<template><nav class="floating-nav" aria-label="主导航"><span class="nav-indicator" :style="{transform:`translateX(${tabs.findIndex(t=>t.id===props.page)*100}%)`}"/><button v-for="t in tabs" :key="t.id" :class="{active:page===t.id}" :aria-current="page===t.id?'page':undefined" @click="$emit('navigate',t.id)"><component :is="t.icon" :size="22"/><span>{{t.label}}</span></button></nav></template>
