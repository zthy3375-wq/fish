<script setup lang="ts">
import { ArrowLeft, Bell, Plus } from 'lucide-vue-next';
defineProps<{title:string;subtitle:string;back?:boolean;add?:boolean;unread?:boolean}>();
defineEmits<{back:[];notifications:[];add:[]}>();
</script>
<template>
  <header class="app-header">
    <div class="header-leading">
      <button v-if="back" class="icon-button" aria-label="返回上一页" @click="$emit('back')"><ArrowLeft /></button>
      <div><h1>{{title}}</h1><p>{{subtitle}}</p></div>
    </div>
    <div class="header-actions">
      <button v-if="add" class="icon-button add-event" aria-label="添加个人事项" @click="$emit('add')"><Plus /></button>
      <button class="icon-button notification-button" aria-label="查看通知" @click="$emit('notifications')"><Bell /><i v-if="unread" /></button>
    </div>
  </header>
</template>
