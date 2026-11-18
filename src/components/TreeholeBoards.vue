<script setup lang="ts">
import {computed} from 'vue';
import {ChevronDown} from 'lucide-vue-next';
import {treeholeInterests,treeholeInterestName} from '../domain/treeholeCategories';

const props=defineProps<{category:string;interest:string;topics:boolean;disabled?:boolean}>();
const emit=defineEmits<{choose:[category:string,interest?:string];more:[]}>();
const primary=[
 {id:'all',name:'全部'},
 {id:'daily',name:'校园'},
 {id:'study',name:'学习'},
 {id:'entertainment',name:'兴趣'},
 {id:'buddies',name:'搭子'},
 {id:'treehole',name:'树洞'},
];
const group=computed(()=>props.category==='help'?'daily':props.category);
const extraInterest=computed(()=>treeholeInterests.some(topic=>topic.id===props.interest));
</script>

<template>
 <div class="board-navigation">
  <nav aria-label="帖子分区" class="board-primary">
   <button v-for="entry in primary" :key="entry.id" type="button" :disabled="disabled"
    :aria-pressed="group===entry.id" @click="group!==entry.id&&emit('choose',entry.id)">{{entry.name}}</button>
  </nav>
  <div v-if="group==='daily'" class="board-filters" role="group" aria-label="校园分区">
   <button type="button" :aria-pressed="category==='daily'" :disabled="disabled" @click="emit('choose','daily')">日常</button>
   <button type="button" :aria-pressed="category==='help'" :disabled="disabled" @click="emit('choose','help')">校园互助</button>
  </div>
  <div v-else-if="group==='study'&&topics" class="board-filters" role="group" aria-label="学习分区">
   <button type="button" :aria-pressed="!interest" :disabled="disabled" @click="emit('choose','study')">全部学习</button>
   <button type="button" :aria-pressed="interest==='graduate'" :disabled="disabled" @click="emit('choose','study','graduate')">考研</button>
  </div>
  <div v-else-if="group==='entertainment'" class="board-filters" role="group" aria-label="兴趣分区">
   <button type="button" :aria-pressed="!interest" :disabled="disabled" @click="emit('choose','entertainment')">全部兴趣</button>
   <template v-if="topics">
    <button type="button" :aria-pressed="interest==='reading'" :disabled="disabled" @click="emit('choose','entertainment','reading')">读书</button>
    <button type="button" :aria-pressed="interest==='fitness'" :disabled="disabled" @click="emit('choose','entertainment','fitness')">健身</button>
   </template>
   <button type="button" aria-haspopup="dialog" :class="{'extra-selected':extraInterest}" :disabled="disabled"
    :aria-label="extraInterest?'更多兴趣，当前 '+treeholeInterestName(interest):'更多兴趣'" @click="emit('more')">
    {{extraInterest?treeholeInterestName(interest):'更多'}}<ChevronDown :size="13" aria-hidden="true"/>
   </button>
  </div>
 </div>
</template>

<style scoped>
.board-navigation{margin:0 0 6px;border-bottom:1px solid var(--color-divider)}
.board-primary{display:grid;grid-template-columns:repeat(6,minmax(44px,1fr));gap:3px;overflow-x:auto;scrollbar-width:none}
.board-primary button,.board-filters button{min-height:44px;white-space:nowrap;color:var(--color-muted);font-weight:550}
.board-primary button{position:relative;font-size:14px;border-radius:8px}
.board-primary button[aria-pressed=true]{color:var(--color-primary-strong);font-weight:700}
.board-primary button[aria-pressed=true]::after{position:absolute;bottom:5px;left:calc(50% - 8px);width:16px;height:2px;border-radius:2px;background:var(--color-primary);content:''}
.board-filters{display:flex;align-items:center;gap:6px;padding:4px 0 2px;overflow-x:auto;scrollbar-width:none}
.board-filters button{display:inline-flex;align-items:center;gap:4px;padding:0 9px;border-radius:8px;font-size:13px}
.board-filters button[aria-pressed=true],.board-filters .extra-selected{background:var(--color-tint);color:var(--color-primary-strong);font-weight:650}
.board-primary button:focus-visible,.board-filters button:focus-visible{outline:2px solid var(--color-primary);outline-offset:-2px}
</style>
