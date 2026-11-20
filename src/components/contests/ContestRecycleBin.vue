<script setup lang="ts">
import {onMounted,onBeforeUnmount,ref} from 'vue';
import {ChevronRight,ArchiveRestore} from 'lucide-vue-next';
import {contestRequest,contestLabels,type Contest} from '../../services/contests';
import {contestDate} from '../../domain/contests';
import {treeholeError} from '../../services/treehole';
const props=defineProps<{owner:string}>();defineEmits<{open:[id:string]}>();
const rows=ref<Contest[]>([]),busy=ref(false),error=ref(''),more=ref(false);let alive=true;
onBeforeUnmount(()=>alive=false);
async function load(append=false){if(busy.value)return;busy.value=true;error.value='';try{const r=await contestRequest(props.owner,'contests.list',{scope:'trash',offset:append?rows.value.length:0},true);if(!alive)return;more.value=(r.contests?.length||0)>20;rows.value=[...(append?rows.value:[]),...(r.contests||[]).slice(0,20)];}catch(e){if(alive)error.value=treeholeError(e);}finally{if(alive)busy.value=false;}}
onMounted(()=>load());
</script>
<template><section><h2>赛事回收站</h2><p class="ct-subtitle">原始投稿、票和奖项仍然保留，可恢复误删或下架的赛事。</p><p v-if="error" class="ct-error" role="alert">{{error}}<button class="ct-link" @click="load()">重试</button></p><button v-for="c in rows" :key="c.id" class="ct-row" @click="$emit('open',c.id)"><ArchiveRestore :size="21"/><span class="ct-row-copy"><h3>{{c.title}}</h3><small>{{c.visibility==='hidden'?'已下架':'已删除'}} · {{contestLabels[c.state]}}<template v-if="c.removedAt"> · {{contestDate(c.removedAt)}}</template></small><small>{{c.removalReason}}</small></span><ChevronRight :size="16"/></button><p v-if="busy" class="ct-loading" role="status">正在读取回收站…</p><div v-else-if="!rows.length&&!error" class="ct-empty"><h3>回收站是空的</h3><p>删除或下架的赛事会出现在这里。</p></div><button v-if="more" class="ct-secondary" :disabled="busy" @click="load(true)">更多已删除赛事</button></section></template>
