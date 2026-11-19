<script setup lang="ts">
import {onMounted,ref} from 'vue';
import {Trophy} from 'lucide-vue-next';
import {contestRequest,awardLabels,type ContestResult} from '../../services/contests';
import {treeholeError} from '../../services/treehole';
const props=defineProps<{owner:string;memberId:string;personal?:boolean}>();
const emit=defineEmits<{open:[id:string]}>();
const data=ref<ContestResult>({}),error=ref(''),busy=ref(false),more=ref(false);
async function load(append=false){busy.value=true;try{const r=await contestRequest(props.owner,'contests.profile',{memberId:props.memberId,offset:append?data.value.awards?.length||0:0});more.value=(r.awards?.length||0)>20;const awards=r.awards?.slice(0,20)||[];data.value={...r,awards:append?[...(data.value.awards||[]),...awards]:awards};error.value='';}catch(e){error.value=treeholeError(e)}finally{busy.value=false}}
async function wear(id:string){busy.value=true;try{await contestRequest(props.owner,'contests.wear',{awardId:data.value.worn===id?null:id});await load();}catch(e){error.value=treeholeError(e)}finally{busy.value=false}}
onMounted(()=>load());
</script>
<template>
 <section class="contest-honors" aria-label="赛事荣誉"><h3><Trophy :size="18"/>赛事荣誉</h3><p v-if="error" role="alert">{{error}} <button @click="load()">重试</button></p><template v-if="data.stats"><div class="honor-counts"><span>参赛 <b>{{data.stats.participations}}</b></span><span>冠军 <b>{{data.stats.champions}}</b></span><span>前三 <b>{{data.stats.podiums}}</b></span></div><p class="earned"><span v-if="data.stats.champions>=1">初露锋芒</span><span v-if="data.stats.champions>=5">常胜将军</span><span v-if="data.stats.champions>=20">不败传说</span><span v-if="data.stats.participations>=100">百战老兵</span><span v-if="data.stats.podiums>=10">民间艺术家</span><span v-for="year in data.annual" :key="year">{{year}} 年度赛事之王</span></p></template>
  <p v-if="!busy&&!data.awards?.length" class="quiet">参赛和获奖经历会收藏在这里。</p>
  <article v-for="a in data.awards" :key="a.id"><button @click="emit('open',a.contest_id!)"><Trophy :size="19"/><span><strong>{{a.title}} {{a.edition}}</strong><small>{{awardLabels[a.kind]}} {{a.rank?'· 并列规则第 '+a.rank+' 名':''}} · {{new Date(a.awarded_at!).toLocaleDateString('zh-CN')}}</small></span></button><button v-if="personal" :disabled="busy" :aria-pressed="data.worn===a.id" @click="wear(a.id)">{{data.worn===a.id?'已佩戴':'佩戴'}}</button></article><button v-if="more" :disabled="busy" @click="load(true)">更多赛事荣誉</button>
 </section>
</template>
<style scoped>
.contest-honors{padding:18px 0;border-top:1px solid var(--color-divider)}h3{display:flex;align-items:center;gap:8px;font-size:15px;color:var(--color-primary)}.honor-counts{display:flex;gap:20px;margin:14px 0;font-size:12px}.honor-counts b{font-size:20px;margin-left:5px}.earned{display:flex;flex-wrap:wrap;gap:6px}.earned span{font-size:11px;padding:5px 8px;background:var(--color-tint);border-radius:6px}article{display:flex;align-items:center;border-bottom:1px solid var(--color-divider);padding:7px 0}article>button:first-child{display:flex;align-items:center;gap:10px;text-align:left;flex:1}button{min-height:44px;font-size:12px;color:var(--color-primary)}strong,small{display:block}strong{font-size:13px;color:var(--color-text)}small,.quiet{color:var(--color-muted);font-size:12px;line-height:1.7}.quiet{padding:12px 0}
</style>
