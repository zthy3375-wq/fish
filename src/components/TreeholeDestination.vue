<script setup lang="ts">
import {computed} from 'vue';
import {ChevronDown,Layers} from 'lucide-vue-next';
import {treeholeCategories,treeholeInterests,treeholeCategoryName} from '../domain/treeholeCategories';
const props=defineProps<{category:string;interest:string;discovery:boolean;compose?:boolean;disabled?:boolean}>();
const emit=defineEmits<{choose:[category:string,interest:string]}>();
const value=computed(()=>props.category==='entertainment'&&props.interest?'interest/'+props.interest:props.category);
const groups=computed(()=>props.discovery?[
 {name:'校园',items:[{id:'daily',name:props.compose?'日常分享':'全部校园'},{id:'help',name:'提问求助'},{id:'study',name:'学习交流'}]},
 {name:'兴趣',items:[{id:'entertainment',name:props.compose?'兴趣闲聊':'全部兴趣'},...treeholeInterests.map(x=>({id:'interest/'+x.id,name:x.name}))]},
 {name:'找搭子',items:[{id:'buddies',name:'找搭子'}]},
 {name:'树洞',items:[{id:'treehole',name:'匿名树洞'}]}
]:[{name:'校园',items:treeholeCategories}]);
const selected=computed(()=>groups.value.flatMap(g=>g.items.map(i=>({id:i.id,text:g.name===i.name?i.name:g.name+' › '+i.name}))).find(i=>i.id===value.value)?.text);
function change(event:Event){const id=(event.target as HTMLSelectElement).value;emit('choose',id.startsWith('interest/')?'entertainment':id,id.startsWith('interest/')?id.slice(9):'')}
</script>
<template><label class="destination" :class="{publishing:compose}">
 <Layers :size="17"/><span v-if="compose">发布到</span><strong>{{category==='all'?'全部分区':selected||treeholeCategoryName(category)}}</strong><ChevronDown :size="15"/>
 <select :aria-label="compose?'选择分区':'帖子分区'" :value="value" :disabled="disabled" @change="change">
  <option v-if="!compose" value="all">全部分区</option>
  <option v-if="category!=='all'&&!selected" :value="value" disabled>{{treeholeCategoryName(category)}}（暂不可用）</option>
  <optgroup v-for="g in groups" :key="g.name" :label="g.name"><option v-for="item in g.items" :key="item.id" :value="item.id">{{item.name}}</option></optgroup>
 </select>
</label></template>
<style scoped>
.destination{position:relative;display:inline-flex;min-height:44px;align-items:center;gap:7px;color:var(--color-muted);font-size:13px}.destination strong{font-weight:600;color:var(--color-text)}.destination select{opacity:0;position:absolute;inset:0;width:100%;height:100%;cursor:pointer}.destination:focus-within{outline:2px solid var(--color-primary);border-radius:7px}.publishing{display:flex;padding:6px 12px;border-block:1px solid var(--color-divider);margin-bottom:10px}.publishing strong{margin-left:auto}
</style>
