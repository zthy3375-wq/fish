<script setup lang="ts">
import {computed,ref} from 'vue';
import {Check,ChevronDown,X} from 'lucide-vue-next';
import {treeholeInterests,treeholeNewTopics} from '../domain/treeholeCategories';

const props=defineProps<{mode:'compose'|'interests';category:string;interest:string;topics:boolean}>();
const emit=defineEmits<{choose:[category:string,interest:string];close:[]}>();
const expand=ref(treeholeInterests.some(topic=>topic.id===props.interest));
const olderInterests=treeholeInterests.map(topic=>({name:topic.name,category:'entertainment',interest:topic.id}));
const newTopics=treeholeNewTopics.map(topic=>({name:topic.name,category:topic.category,interest:topic.id}));
const groups=computed(()=>[
 {name:'校园',entries:[{name:'校园日常',category:'daily',interest:''},{name:'校园互助',category:'help',interest:''}]},
 {name:'学习',entries:[{name:'学习交流',category:'study',interest:''},...newTopics.filter(topic=>props.topics&&topic.category==='study')]},
 {name:'兴趣',entries:[{name:'兴趣闲聊',category:'entertainment',interest:''},...newTopics.filter(topic=>props.topics&&topic.category==='entertainment')]},
 {name:'搭子与树洞',entries:[{name:'找搭子',category:'buddies',interest:''},{name:'匿名树洞',category:'treehole',interest:''}]},
]);
const visibleGroups=computed(()=>props.mode==='interests'?[{name:'兴趣',entries:olderInterests}]:groups.value);
</script>

<template>
 <div class="board-picker">
  <header><h3>{{mode==='compose'?'选择分区':'更多兴趣'}}</h3><button type="button" aria-label="关闭分区面板" @click="emit('close')"><X :size="20"/></button></header>
  <div v-for="section in visibleGroups" :key="section.name" class="picker-group">
   <h4 v-if="mode==='compose'">{{section.name}}</h4>
   <div class="picker-options">
    <button v-for="entry in section.entries" :key="entry.name" type="button"
     :aria-pressed="category===entry.category&&interest===entry.interest"
     @click="emit('choose',entry.category,entry.interest)">
     <span>{{entry.name}}</span><Check v-if="category===entry.category&&interest===entry.interest" :size="15" aria-hidden="true"/>
    </button>
   </div>
   <template v-if="mode==='compose'&&section.name==='兴趣'">
    <button type="button" class="picker-expand" :aria-expanded="expand" aria-controls="board-older-interests" @click="expand=!expand">更多兴趣<ChevronDown :size="14"/></button>
    <div v-show="expand" id="board-older-interests" class="picker-options">
     <button v-for="entry in olderInterests" :key="entry.interest" type="button"
      :aria-pressed="interest===entry.interest" @click="emit('choose',entry.category,entry.interest)">
      <span>{{entry.name}}</span><Check v-if="interest===entry.interest" :size="15" aria-hidden="true"/>
     </button>
    </div>
   </template>
  </div>
 </div>
</template>

<style scoped>
.board-picker header{display:flex;align-items:center;justify-content:space-between;margin-bottom:6px}
.board-picker header h3{margin:0;font-size:20px}
.board-picker header button{display:grid;place-items:center;width:44px;height:44px;color:var(--color-muted);border-radius:10px}
.picker-group{padding:12px 0;border-top:1px solid var(--color-divider)}
.picker-group h4{margin:0 0 6px;font-size:12px;font-weight:600;color:var(--color-muted)}
.picker-options{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,88px),1fr));gap:6px}
.picker-options button{display:flex;justify-content:center;align-items:center;flex-wrap:wrap;gap:4px;min-height:44px;padding:6px;background:var(--color-bg);color:var(--color-text);border-radius:8px;font-size:14px}
.picker-options button[aria-pressed=true]{background:var(--color-tint);color:var(--color-primary-strong);font-weight:650}
.picker-expand{display:inline-flex;align-items:center;gap:6px;min-height:44px;color:var(--color-primary-strong);font-size:13px}
.picker-expand[aria-expanded=true] svg{transform:rotate(180deg)}
.board-picker button:focus-visible{outline:2px solid var(--color-primary);outline-offset:-2px}
</style>
