<script setup lang="ts">
import {DoorOpen,ChevronRight} from 'lucide-vue-next';
defineEmits<{select:[]}>();
</script>
<template>
 <button class="classroom-entry" aria-label="空闲教室" @click="$emit('select')">
  <span class="classroom-entry-icon"><DoorOpen :size="24" /></span>
  <span class="classroom-entry-copy"><strong>空闲教室</strong><small>找自习地点 · 查看全天占用</small></span>
  <ChevronRight :size="19" />
 </button>
</template>
