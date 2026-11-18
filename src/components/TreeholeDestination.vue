<script setup lang="ts">
import {ChevronDown,Layers} from 'lucide-vue-next';
import {treeholeCategories,treeholeCategoryName} from '../domain/treeholeCategories';

defineProps<{category:string;compose?:boolean;disabled?:boolean}>();
const emit=defineEmits<{choose:[category:string]}>();
</script>

<template>
 <label class="destination" :class="{publishing:compose}">
  <Layers :size="17" aria-hidden="true"/><span v-if="compose">发布到</span>
  <strong>{{category==='all'?'全部分区':treeholeCategoryName(category)}}</strong><ChevronDown :size="15" aria-hidden="true"/>
  <select :aria-label="compose?'选择分区':'帖子分区'" :value="category" :disabled="disabled" @change="emit('choose',($event.target as HTMLSelectElement).value)">
   <option v-if="!compose" value="all">全部分区</option>
   <option v-if="category!=='all'&&!treeholeCategories.some(item=>item.id===category)" :value="category" disabled>{{treeholeCategoryName(category)}}（暂不可用）</option>
   <option v-for="item in treeholeCategories" :key="item.id" :value="item.id">{{item.name}}</option>
  </select>
 </label>
</template>

<style scoped>
.destination{position:relative;display:inline-flex;min-height:44px;align-items:center;gap:7px;color:var(--color-muted);font-size:13px}
.destination strong{font-weight:600;color:var(--color-text)}
.destination select{opacity:0;position:absolute;inset:0;width:100%;height:100%;cursor:pointer}
.destination:focus-within{outline:2px solid var(--color-primary);border-radius:8px}
.publishing{display:flex;padding:6px 12px;border-block:1px solid var(--color-divider);margin-bottom:10px}
.publishing strong{margin-left:auto}
</style>
