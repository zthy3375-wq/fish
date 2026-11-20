<script setup lang="ts">
import {computed,onMounted,onBeforeUnmount,ref,watch} from 'vue';
import {ChevronRight} from 'lucide-vue-next';
import {contestRequest,awardLabels,type ContestResult,type ContestAward} from '../../services/contests';
import {treeholeError,type TreeholeResult} from '../../services/treehole';
import {contestDate} from '../../domain/contests';
import ContestMedal from './ContestMedal.vue';
import ContestDialog from './ContestDialog.vue';
const props=defineProps<{owner:string;memberId:string;personal?:boolean;collection?:boolean;backendSchema?:number}>();
const emit=defineEmits<{open:[id:string,entryId?:string];updated:[result:TreeholeResult]}>();
const data=ref<ContestResult>({}),error=ref(''),busy=ref(false),more=ref(false),kind=ref('champion'),chosen=ref<ContestAward>();
const kinds=Object.keys(awardLabels);let revision=0,offset=0;
onBeforeUnmount(()=>revision++);
const shown=computed(()=>data.value.awards?.filter(a=>a.kind===kind.value)||[]);
const counts=computed(()=>data.value.stats?.medalCounts);
async function load(append=false){const rev=++revision;busy.value=true;error.value='';try{const next=append?offset+20:0;const r=await contestRequest(props.owner,'contests.profile',{memberId:props.memberId,offset:next,...((props.backendSchema||13)>=15?{kind:kind.value}:{})});if(rev!==revision)return;offset=next;more.value=(r.awards?.length||0)>20;data.value={...r,awards:[...(append?data.value.awards||[]:[]),...(r.awards||[]).slice(0,20)]};}catch(e){if(rev===revision)error.value=treeholeError(e);}finally{if(rev===revision)busy.value=false;}}
function select(k:string){if(busy.value)return;kind.value=k;void load();}
async function wear(){if(!chosen.value||busy.value)return;busy.value=true;error.value='';try{const id=data.value.worn===chosen.value.id?null:chosen.value.id;const r=await contestRequest(props.owner,'contests.wear',{awardId:id});data.value.worn=id;emit('updated',{updatedIdentity:r.updatedIdentity});}catch(e){error.value=treeholeError(e);}finally{busy.value=false;}}
function requestBack(){if(chosen.value){if(!busy.value)chosen.value=undefined;return true;}return busy.value;}
defineExpose({requestBack});
onMounted(()=>load());watch(()=>[props.owner,props.memberId],()=>{data.value={};chosen.value=undefined;void load();});
</script>
<template><section class="contest-honors" aria-label="赛事奖牌">
  <div v-if="data.stats" class="medal-career"><span><b>{{data.stats.champions}}</b>冠军</span><span><b>{{data.stats.podiums}}</b>前三</span><span><b>{{data.stats.participations}}</b>有效参赛</span></div>
  <nav class="medal-shelf" aria-label="奖牌种类"><button v-for="k in kinds" :key="k" :aria-pressed="kind===k" :disabled="busy" @click="select(k)"><ContestMedal :kind="k" :size="44"/><strong>{{awardLabels[k]}}</strong><small v-if="counts">× {{counts[k]||0}}</small><small v-else>查看记录</small></button></nav>
  <h3 class="medal-history-title">{{awardLabels[kind]}} · 获得记录</h3>
  <p v-if="error" role="alert" class="ct-error">{{error}}<button @click="load()">重试</button></p>
  <p v-if="busy" role="status" class="ct-loading">正在读取奖牌…</p>
  <button v-for="a in shown" :key="a.id" class="medal-history-row" @click="chosen=a"><ContestMedal :kind="a.kind" :size="35"/><span><strong>{{a.title}} <small>{{a.edition}}</small></strong><small>{{a.rank?'第 '+a.rank+' 名 · ':''}}{{a.awarded_at?contestDate(a.awarded_at,true):''}}{{data.worn===a.id?' · 佩戴中':''}}</small></span><ChevronRight :size="16"/></button>
  <div v-if="!busy&&!error&&!shown.length" class="medal-empty"><ContestMedal :kind="kind" :size="38"/><div><h3>{{more?'这页没有该类奖牌':'还没有这枚奖牌'}}</h3><p>{{more?'继续读取较早的赛事记录。':'参加校园赛事，留下你的作品与纪念。'}}</p></div></div>
  <button v-if="more" class="ct-link" :disabled="busy" @click="load(true)">更多获奖记录</button>
  <details v-if="data.stats" class="medal-milestones"><summary>累计成就与年度记录</summary><p>累计成绩按有效赛事统计，与上方单场获奖记录分别保存。</p><ul><li v-if="data.stats.champions>=1">初露锋芒 · 首次夺冠</li><li v-if="data.stats.champions>=5">常胜将军 · 累计5冠</li><li v-if="data.stats.champions>=20">不败传说 · 累计20冠</li><li v-if="data.stats.participations>=100">百战老兵 · 有效参赛100场</li><li v-if="data.stats.podiums>=10">民间艺术家 · 累计10次前三</li><li v-for="year in data.annual" :key="year">{{year}} 年度赛事之王</li></ul><p v-if="!data.stats.champions&&!data.annual?.length">下一段荣誉经历，从参与开始。</p></details>
  <ContestDialog :open="!!chosen" :title="awardLabels[chosen?.kind||'']||'赛事奖牌'" confirm="查看比赛与作品" @cancel="chosen=undefined" @confirm="chosen?.contest_id&&emit('open',chosen.contest_id,chosen.entry_id)"><div v-if="chosen" class="medal-detail"><ContestMedal :kind="chosen.kind" :size="78"/><h3>{{chosen.title}}</h3><p>{{chosen.edition}}</p><dl><dt>最终名次</dt><dd>{{chosen.rank?'第 '+chosen.rank+' 名（同票并列）':awardLabels[chosen.kind]}}</dd><dt>获奖日期</dt><dd>{{chosen.awarded_at?contestDate(chosen.awarded_at,true):'—'}} · 北京时间</dd></dl><button v-if="personal" class="ct-secondary" :disabled="busy" :aria-pressed="data.worn===chosen.id" @click="wear">{{data.worn===chosen.id?'取下代表荣誉':'佩戴为代表荣誉'}}</button><p v-if="error" role="alert" class="ct-error">{{error}}</p></div></ContestDialog>
</section></template>
<style scoped>
.contest-honors button{cursor:pointer}.contest-honors button:disabled{cursor:default;opacity:.5}.medal-history-row:hover{background:var(--color-background)}

.contest-honors{padding:4px 0}.medal-career{display:flex;gap:28px;padding:8px 0 18px;color:var(--color-muted);font-size:11px}.medal-career span{display:grid;gap:2px}.medal-career b{font-size:23px;color:var(--color-text);font-weight:650;line-height:1.35}.medal-shelf{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:4px;padding:13px 0;border-top:1px solid var(--color-divider);border-bottom:1px solid var(--color-divider)}.medal-shelf button{min-width:0;display:grid;justify-items:center;gap:7px;padding:9px 1px;border-radius:10px;color:var(--color-muted);background:transparent}.medal-shelf button[aria-pressed=true]{background:var(--color-background);color:var(--color-text)}.medal-shelf strong{font-size:11px;font-weight:550;white-space:nowrap}.medal-shelf small{font-size:10px;font-variant-numeric:tabular-nums}.medal-history-title{font-size:13px;font-weight:600;margin:20px 0 6px}.medal-history-row{width:100%;display:flex;align-items:center;text-align:left;gap:12px;padding:14px 0;border-bottom:1px solid var(--color-divider);color:var(--color-text)}.medal-history-row>span:nth-child(2){flex:1;min-width:0}.medal-history-row strong{display:block;font-size:13px;line-height:1.5;overflow-wrap:anywhere}.medal-history-row small{font-size:11px;color:var(--color-muted);line-height:1.6}.medal-empty{display:flex;gap:14px;align-items:center;padding:24px 0}.medal-empty h3{font-size:13px;margin:0 0 3px}.medal-empty p,.medal-milestones p,.medal-milestones li{font-size:12px;line-height:1.6;color:var(--color-muted);margin:0}.medal-milestones{margin-top:18px}.medal-milestones summary{min-height:44px;font-size:12px;cursor:pointer;color:var(--color-muted)}.medal-detail{text-align:center;padding:12px 0 4px}.medal-detail h3{font-size:21px;margin:16px 0 3px;overflow-wrap:anywhere}.medal-detail p{font-size:13px;color:var(--color-muted)}.medal-detail dl{display:grid;grid-template-columns:auto 1fr;text-align:left;gap:12px;font-size:12px;margin:20px 0}.medal-detail dt{color:var(--color-muted)}.medal-detail dd{margin:0}.medal-shelf button:focus-visible,.medal-history-row:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}
</style>
