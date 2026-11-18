<script setup lang="ts">
import {computed,onMounted,ref,watch} from 'vue';
import {badges,capNames,honorDate,operations,type BadgeCode,type AdminMember,type HonorLog} from '../../domain/communityHonors';
import {treeholeError,type TreeholeResult,type TreeholeUser} from '../../services/treehole';
const props=defineProps<{user:TreeholeUser;request:(a:string,b?:Record<string,unknown>)=>Promise<TreeholeResult>}>();
const emit=defineEmits<{changed:[TreeholeResult]}>();
const owner=computed(()=>props.user.badges?.official?.code==='developer');
const query=ref(''),members=ref<AdminMember[]>([]),audit=ref<HonorLog[]>([]),subject=ref<AdminMember>(),reason=ref(''),caps=ref<string[]>([]),kind=ref<BadgeCode>('contributor'),op=ref(''),busy=ref(false),error=ref(''),notice=ref(''),confirmation=ref(''),requestId=ref('');
const options=computed(()=>{
 const m=subject.value;if(!m)return [];
 const items:string[]=[];
 if(owner.value){items.push('grant');if(m.honors.some(h=>h!=='seed'))items.push('revoke');if(m.recommendation)items.push('decline');if(!m.official||m.official.code!=='developer'){items.push('appoint');if(m.official?.code==='moderator')items.push('dismiss');}}
 if((owner.value||props.user.caps?.includes('recommend'))&&!m.honors.includes('creator'))items.push('recommend');
 if((owner.value||props.user.caps?.includes('users'))&&m.id!==props.user.id&&(!m.official||owner.value&&m.official.code!=='developer'))items.push(m.bannedUntil&&new Date(m.bannedUntil)>new Date()?'unmute':'mute');
 return items;
});
const kinds=computed(()=>op.value==='revoke'?subject.value?.honors.filter(k=>k!=='seed')||[]:(['seed','creator','contributor'] as BadgeCode[]).filter(k=>!subject.value?.honors.includes(k)&&(k!=='creator'||subject.value?.recommendation)));
function choose(m:AdminMember){subject.value=m;caps.value=[...m.caps];op.value=options.value[0]||'';reason.value='';notice.value='';confirmation.value='';kind.value=kinds.value[0]||'contributor';}
watch([op,kind,reason,caps],()=>{confirmation.value='';requestId.value='';},{deep:true});
watch(op,()=>{if(!kinds.value.includes(kind.value))kind.value=kinds.value[0]||'contributor';});
async function list(){const r=await props.request('honors.manage',{query:query.value.trim()});members.value=r.members||[];audit.value=r.audit||[];}
async function search(){if(busy.value)return;busy.value=true;error.value='';subject.value=undefined;try{await list();}catch(e){error.value=treeholeError(e);}finally{busy.value=false;}}
async function submit(){if(!subject.value||busy.value||reason.value.trim().length<2)return;
 if(!confirmation.value){requestId.value=crypto.randomUUID();confirmation.value='确认对「'+subject.value.nickname+'」执行「'+operations[op.value]+'」？';return;}
 busy.value=true;error.value='';try{const r=await props.request('honors.change',{memberId:subject.value.id,operation:op.value,kind:kind.value,caps:caps.value,reason:reason.value.trim(),requestId:requestId.value});subject.value=undefined;confirmation.value='';notice.value='操作已记录';emit('changed',r);await list();}catch(e){error.value=treeholeError(e);}finally{busy.value=false;}}
onMounted(search);
</script>
<template><section class="hon-admin"><h2>身份与荣誉管理</h2><form @submit.prevent="search"><label>查找社区成员<input v-model="query" placeholder="完整昵称或社区成员 ID" maxlength="64"/></label><button :disabled="busy">查找</button></form>
 <p v-if="error" role="alert">{{error}}</p><p v-if="notice" role="status">{{notice}}</p><p v-if="busy" role="status">正在处理…</p>
 <p v-if="!busy&&!members.length">没有匹配成员或待审核推荐。</p><button v-for="m in members" :key="m.id" class="hon-person" :disabled="busy" @click="choose(m)"><strong>{{m.nickname}}</strong><small>{{m.recommendation?'待审核推荐':m.official?badges[m.official.code].name:'社区成员'}}</small></button>
 <form v-if="subject" @submit.prevent="submit"><h3>{{subject.nickname}}</h3><small class="hon-id">{{subject.id}}</small><p v-if="subject.recommendation">推荐理由 · {{subject.recommendation}}</p><label>操作<select v-model="op"><option v-for="o in options" :key="o" :value="o">{{operations[o]}}</option></select></label>
 <label v-if="op==='grant'||op==='revoke'">荣誉<select v-model="kind"><option v-for="k in kinds" :key="k" :value="k">{{badges[k].name}}</option></select></label>
 <fieldset v-if="op==='appoint'"><legend>管理权限</legend><label v-for="(label,k) in capNames" :key="k"><input type="checkbox" v-model="caps" :value="k"/>{{label}}</label></fieldset>
 <label>操作理由<textarea v-model="reason" minlength="2" maxlength="200" required/></label><p v-if="confirmation">{{confirmation}}</p><button :disabled="busy||!op||reason.trim().length<2||(['grant','revoke'].includes(op)&&!kinds.includes(kind))">{{confirmation?'确认执行':'核对操作'}}</button></form>
 <details v-if="owner"><summary>最近授权记录</summary><p v-if="!audit.length">暂无授权记录。</p><div v-for="(log,i) in audit" :key="i"><strong>{{operations[log.change.operation]}} · {{log.target}}</strong><p>{{log.change.reason}}</p><small>{{log.actor}} · {{honorDate(log.at)}}</small></div></details></section></template>
<style scoped>
.hon-admin{display:grid;gap:12px;padding:15px 4px}.hon-admin form,.hon-admin details,.hon-person{display:grid;gap:10px;padding:15px;text-align:left;border:1px solid var(--color-divider);background:var(--color-surface,#fff);border-radius:15px}.hon-admin h2,.hon-admin h3,.hon-admin p{margin:0}.hon-admin label{display:grid;gap:5px;font-size:13px}.hon-admin input:not([type=checkbox]),.hon-admin textarea,.hon-admin select{font:inherit;color:inherit;min-width:0;padding:10px;border:1px solid var(--color-divider);border-radius:9px;background:var(--color-surface)}.hon-admin form button{padding:11px;border-radius:12px;background:#6d4e91;color:white}.hon-admin :disabled{opacity:.55}.hon-person{display:flex;align-items:center;justify-content:space-between}.hon-admin small{color:var(--color-muted)}.hon-id{user-select:all}.hon-admin fieldset label{display:inline-flex;align-items:center;padding:5px}.hon-admin details div{padding:10px 0}
</style>
