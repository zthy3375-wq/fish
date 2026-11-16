<script setup lang="ts">
import type {TreeholePollDraft} from '../services/treehole';
const props=defineProps<{modelValue:TreeholePollDraft;disabled?:boolean}>();
const emit=defineEmits<{'update:modelValue':[value:TreeholePollDraft];remove:[]}>();
function update(part:Partial<TreeholePollDraft>){emit('update:modelValue',{...props.modelValue,...part});}
function option(index:number,value:string){const options=[...props.modelValue.options];options[index]=value;update({options});}
</script>
<template>
 <section class="th-poll-editor" aria-label="编辑投票"><header><strong>发起投票</strong><button type="button" :disabled="disabled" @click="$emit('remove')">移除投票</button></header>
  <input :value="modelValue.question" @input="update({question:($event.target as HTMLInputElement).value})" aria-label="投票问题" placeholder="想问大家什么？" maxlength="80" required :disabled="disabled"/>
  <div v-for="(item,index) in modelValue.options" :key="index" class="th-poll-editor-option"><input :value="item" @input="option(index,($event.target as HTMLInputElement).value)" :aria-label="'投票选项 '+(index+1)" :placeholder="'选项 '+(index+1)" maxlength="40" required :disabled="disabled"/><button v-if="modelValue.options.length>2" type="button" :aria-label="'移除选项 '+(index+1)" :disabled="disabled" @click="update({options:modelValue.options.filter((_,i)=>i!==index)})">移除</button></div>
  <button v-if="modelValue.options.length<6" type="button" :disabled="disabled" @click="update({options:[...modelValue.options,'']})">＋ 添加选项</button>
  <label>投票时长<select :value="modelValue.durationHours" aria-label="投票时长" :disabled="disabled" @change="update({durationHours:Number(($event.target as HTMLSelectElement).value)})"><option :value="24">1 天</option><option :value="72">3 天</option><option :value="168">7 天</option></select></label>
  <small>单选，发布后选项固定；时长从成功发布开始计算。</small>
 </section>
</template>
<style scoped>
.th-poll-editor{padding:14px;background:var(--color-bg);border-radius:12px;margin:12px 0;display:flex;flex-direction:column;gap:8px}header,.th-poll-editor-option,label{display:flex;align-items:center;gap:8px;justify-content:space-between}strong{font-size:14px}input{min-width:0;width:100%;background:white;border-radius:8px;padding:12px;font-size:14px;min-height:44px}.th-poll-editor button{color:var(--color-primary);font-size:12px;min-height:40px;flex-shrink:0}label{font-size:13px}select{padding:10px;background:white;border-radius:8px;min-height:44px}small{color:var(--color-muted);font-size:11px;line-height:1.6}
</style>
