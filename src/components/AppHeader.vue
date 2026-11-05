<script setup lang="ts">
import {Menu,ArrowLeft,Bell,Download} from 'lucide-vue-next';
defineProps<{title:string;subtitle:string;back?:boolean;academic?:boolean;unread?:boolean}>();
defineEmits<{back:[];menu:[];notifications:[];import:[]}>();
</script>
<template><header class="app-header"><div class="header-leading"><button class="icon-button" :aria-label="back?'返回上一页':'打开侧边栏'" @click="back?$emit('back'):$emit('menu')"><ArrowLeft v-if="back"/><Menu v-else/></button><div><h1>{{title}}</h1><p>{{subtitle}}</p></div></div><div class="header-actions"><button v-if="academic" class="import-button" aria-label="课表导入说明（暂未接入）" @click="$emit('import')"><Download :size="17"/><span>导入<small>待接入</small></span></button><button class="icon-button notification-button" aria-label="查看通知" @click="$emit('notifications')"><Bell/><i v-if="unread"/></button></div></header></template>
