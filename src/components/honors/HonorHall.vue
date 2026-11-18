<script setup lang="ts">
import {computed,onMounted,ref} from 'vue';
import {Check,LockKeyhole,Trophy} from 'lucide-vue-next';
import OfficialBadges from './OfficialBadges.vue';
import {catalog} from '../../domain/globalAchievements';
import {badges,honorDate,specialAwards,type HonorHall,type BadgeCode} from '../../domain/communityHonors';
import {treeholeError,treeholeErrorCode,type TreeholeResult} from '../../services/treehole';
const props=defineProps<{viewer:string;member:string;request:(a:string,b?:Record<string,unknown>)=>Promise<TreeholeResult>;enabled:boolean}>();
const emit=defineEmits<{updated:[TreeholeResult]}>();
const self=computed(()=>props.viewer===props.member),hall=ref<HonorHall>(),busy=ref(false),failure=ref(''),offline=ref(false);
const filter=ref('全部'),selected=ref<string>('arrival'),honor=ref<BadgeCode|null>(null),shelf=ref<string[]>([]);
const awards=computed(()=>catalog.filter(a=>a.source==="community"&&(a.metric!=="days"||hall.value?.progress?.days!==undefined||hall.value?.showcase.includes(a.code))));
const selectedAward=computed(()=>awards.value.find(a=>a.code===selected.value));
const visible=computed(()=>awards.value.filter(a=>(self.value||hall.value?.showcase.includes(a.code))&&(filter.value!=='已解锁'||hall.value?.awards[a.code])&&(filter.value!=='稀有'||a.tier==='稀有')));
const cacheKey=()=> 'hyt-hall-v1:'+props.viewer;
function apply(h:HonorHall){hall.value=h;honor.value=h.badges.worn?.code??null;shelf.value=[...h.showcase];if(!self.value)selected.value=h.showcase[0]||'';}
function persist(h:HonorHall){if(self.value)try{sessionStorage.setItem(cacheKey(),JSON.stringify(h));}catch{/* session storage unavailable */}}
async function load(){if(busy.value||!props.enabled)return;busy.value=true;failure.value='';offline.value=false;
 try{const r=await props.request('honors.hall',{memberId:props.member});if(!r.hall)throw Error('invalid_response');apply(r.hall);persist(r.hall);}
 catch(e){failure.value=treeholeError(e);if(self.value&&!['session_expired','forbidden','not_found'].includes(treeholeErrorCode(e)))try{const h=JSON.parse(sessionStorage.getItem(cacheKey())||'null');if(h?.id===props.viewer){apply(h);offline.value=true;}}catch{/* empty cache */}}
 finally{busy.value=false;}}
async function save(h:BadgeCode|null,items:string[]){if(busy.value||offline.value)return;busy.value=true;failure.value='';
 try{const r=await props.request('honors.wear',{honor:h,showcase:items});if(!r.hall)throw Error('invalid_response');apply(r.hall);persist(r.hall);emit('updated',r);}
 catch(e){failure.value=treeholeError(e);}finally{busy.value=false;}}
function toggle(code:string){const items=shelf.value.includes(code)?shelf.value.filter(s=>s!==code):[...shelf.value,code];if(items.length<=3)void save(honor.value,items);}
onMounted(load);
</script>
<template><main class="hon-page">
 <p v-if="!enabled" class="hon-status">当前社区服务尚未开放荣誉殿堂。下方可查看首批成就。</p>
 <p v-if="failure" role="alert" class="hon-status">{{offline?'显示本次登录最近保存的收藏。 ':''}}{{failure}} <button @click="load">重试</button></p>
 <p v-if="busy&&!hall" role="status">正在读取荣誉殿堂…</p>
 <section v-if="hall" class="hon-panel"><h2>{{self?'我的身份':hall.nickname+'的身份'}}</h2><OfficialBadges :items="[hall.badges.official,...hall.honors]"/><p v-if="!hall.badges.official&&!hall.honors.length">还没有获得官方身份或荣誉。</p>
 <label v-if="self&&hall.honors.length" class="hon-wear">发言时佩戴<select :value="honor||''" :disabled="busy||offline" @change="save((($event.target as HTMLSelectElement).value||null) as BadgeCode|null,shelf)"><option value="">不佩戴荣誉</option><option v-for="h in hall.honors" :key="h.code" :value="h.code">{{badges[h.code].name}}</option></select></label></section>
 <section class="hon-panel"><header><div><h2>{{self?'我的成就':'展示成就'}}</h2><p>{{self?'记录你与邯院通的每一次相遇':'由这位同学亲自挑选'}}</p></div><strong v-if="hall">{{self?hall.total+'/'+awards.length:hall.showcase.length+'/3'}}</strong></header>
 <progress v-if="self&&hall" :value="hall.total" :max="awards.length" aria-label="成就收藏进度"/>
 <nav v-if="self" class="hon-segment" aria-label="成就筛选"><button v-for="f in ['全部','已解锁','稀有']" :key="f" :aria-pressed="filter===f" @click="filter=f;selected=''">{{f}}</button></nav>
 <div class="hon-grid"><button v-for="a in visible" :key="a.code" :class="{earned:hall?.awards[a.code],active:selected===a.code}" :aria-pressed="selected===a.code" @click="selected=a.code"><component :is="hall?.awards[a.code]?a.icon:LockKeyhole" :size="25"/><span>{{a.name}}</span><Check v-if="shelf.includes(a.code)" class="hon-pin" :size="12" aria-label="展示中"/></button></div>
 <p v-if="!visible.length">{{self?'这个分类里还没有收藏。':'这位同学还没有选择展示成就。'}}</p>
 <div v-if="selectedAward&&visible.includes(selectedAward)" class="hon-detail"><component :is="selectedAward.icon" :size="33"/><div><h3>{{selectedAward.name}}</h3><p>{{selectedAward.condition}}</p><small>{{selectedAward.tier}} · {{hall?.awards[selectedAward.code]?(hall.backfilled?.includes(selectedAward.code)?'历史补发于 ':'已解锁 · ')+honorDate(hall.awards[selectedAward.code]):hall?'进度 '+Math.min(hall.progress?.[selectedAward.metric||'']||0,selectedAward.goal)+' / '+selectedAward.goal:'尚未获取进度'}}</small></div></div>
 <button v-if="self&&selectedAward&&hall?.awards[selectedAward.code]&&visible.includes(selectedAward)" class="hon-action" :disabled="busy||offline||(!shelf.includes(selected)&&shelf.length>=3)" @click="toggle(selected)">{{shelf.includes(selected)?'从主页取下':shelf.length>=3?'已展示三枚':'展示到主页'}} · {{shelf.length}}/3</button>
 </section><details v-if="self" class="hon-panel"><summary><Trophy :size="18"/>特别收藏 · 待开放</summary><div class="hon-future" v-for="a in specialAwards" :key="a.name"><LockKeyhole :size="18"/><span>{{a.name}}</span><small>{{a.tier}}{{a.limited?' · 限定':''}} · 隐藏条件</small></div></details>
</main></template>
<style scoped>
.hon-page{display:grid;gap:12px;padding:12px 2px}.hon-panel{border:1px solid var(--color-divider,#e6e3eb);background:var(--color-surface,#fff);border-radius:20px;padding:17px;min-width:0}.hon-panel header,.hon-wear,.hon-future,.hon-detail,.hon-panel summary{display:flex;gap:10px;align-items:center}.hon-panel header,.hon-wear{justify-content:space-between}.hon-panel header strong{font-size:28px;letter-spacing:-1px}.hon-panel h2,.hon-panel h3{margin:0 0 6px;font-size:19px}.hon-panel p,.hon-status{font-size:13px;line-height:1.5;color:var(--color-muted,#655e68);margin:5px 0}.hon-panel progress{width:100%;height:7px;appearance:none;border:0;border-radius:8px;overflow:hidden;background:#eeeaf1;margin:12px 0}.hon-panel progress::-webkit-progress-bar{background:#eeeaf1}.hon-panel progress::-webkit-progress-value{background:#a184df;border-radius:8px}.hon-segment,.hon-grid{display:grid;gap:6px}.hon-segment{grid-template-columns:repeat(3,1fr);margin:8px 0 13px}.hon-segment button{min-height:36px;border-radius:24px;color:var(--color-muted)}.hon-segment button[aria-pressed=true]{background:var(--color-tint,#f1eef5);color:var(--color-text)}.hon-grid{grid-template-columns:repeat(4,minmax(0,1fr))}.hon-grid button{position:relative;display:grid;place-content:center;justify-items:center;gap:7px;min-height:78px;border-radius:14px;border:1px solid var(--color-divider,#eee);color:var(--color-muted,#6f6872);background:var(--color-surface-muted,#f4f3f5);font-size:12px}.hon-grid .earned{background:#fff7e8;color:#895f21}.hon-grid .active{outline:2px solid #a38ad4;outline-offset:-2px;background:#f2edf9;color:#65488b}.hon-pin{position:absolute;top:4px;right:4px}.hon-detail{margin-top:16px;border-top:1px solid var(--color-divider);padding-top:15px}.hon-detail>svg{color:#946833;flex-shrink:0}.hon-panel small{color:var(--color-muted);font-size:12px}.hon-action,.hon-wear select,.hon-status button{border:0;border-radius:10px;padding:8px 12px;color:#66458c;background:#f1eaf8}.hon-action{margin-top:10px}.hon-wear{font-size:13px;margin-top:14px}.hon-future{padding:12px 0;border-bottom:1px solid var(--color-divider)}.hon-future small{margin-left:auto}.hon-panel summary{cursor:pointer;font-weight:600}@media(max-width:335px){.hon-grid{grid-template-columns:repeat(3,1fr)}}
</style>
