<script setup lang="ts">
import {computed,nextTick,onMounted,onUnmounted,ref,shallowRef} from 'vue';
import {Bookmark,Check,ChevronRight,HelpCircle,LockKeyhole,RefreshCw,Trophy,X} from 'lucide-vue-next';
import {byCode,catalog,groups,lifeCodes,sourceNames,type Collectible,type Group} from '../../domain/globalAchievements';
import {cachedHall,feedback,localQueue,localStamps,privatePins,viewHidden,scopes,storageIssue,togglePrivate} from '../../services/achievementJournal';
import {treeholeRequest,treeholeError,treeholeErrorCode} from '../../services/treehole';
import {honorDate,type HonorHall} from '../../domain/communityHonors';
import {pendingAwards,markPresented} from '../../services/achievementDelivery';
import AchievementNotice from './AchievementNotice.vue';
import OfficialBadges from './OfficialBadges.vue';

const emit=defineEmits<{account:[]}>();
const category=ref<Group>('全部'),selected=shallowRef<Collectible>(),detail=ref<HTMLDialogElement>();
const hall=ref<HonorHall>(),loading=ref(false),failure=ref(''),fromCache=ref(false),signedIn=ref(false);
const pending=ref<string[]>([]);
let active=true;
function seen(code:string){
  const owner=hall.value?.id;if(!owner)return;
  markPresented(owner,code);delivered.add(code);pending.value=pending.value.filter(k=>k!==code);
  if(!pending.value.length&&delivered.size){const codes=[...delivered];delivered.clear();void treeholeRequest('honors.ack',{codes}).catch(()=>{});}
}
const delivered=new Set<string>();
const earned=computed(()=>({...Object.fromEntries(Object.entries(localStamps.value).map(([k,v])=>[k,v.at])),...hall.value?.awards}));
const count=computed(()=>catalog.filter(a=>earned.value[a.code]).length);
const percent=computed(()=>Math.round(100*count.value/catalog.length));
const cards=computed(()=>catalog.filter(a=>category.value==='全部'||a.group===category.value));
const concealed=(a:Collectible)=>a.hidden&&!earned.value[a.code];
function unknown(a:Collectible){return a.source==='community'?!hall.value:a.source!=='device'&&!scopes.value[a.source];}
function stateLabel(a:Collectible){return earned.value[a.code]?'已解锁':unknown(a)?(a.source==='community'?'待同步':'待连接'):'未解锁';}
const pinned=(a:Collectible)=>a.source==='community'?!!hall.value?.showcase.includes(a.code):privatePins.value.includes(a.code);
const pinCount=(a:Collectible)=>a.source==='community'?hall.value?.showcaseUsed??hall.value?.showcase.length??0:privatePins.value.length;
function progress(a:Collectible){
 if(earned.value[a.code])return a.goal;
 if(unknown(a))return null;
 if(a.code==='life')return lifeCodes.filter(k=>earned.value[k]).length;
 if(a.source==='community')return a.metric&&hall.value?.progress?.[a.metric]!==undefined?Math.min(a.goal,hall.value.progress[a.metric]):null;
 return 0;
}
async function load(force=false){
 if(loading.value)return;
 loading.value=true;failure.value='';
 try{
  const cache=await cachedHall();if(!active)return;
  signedIn.value=cache.signedIn;hall.value=cache.signedIn?cache.hall:undefined;fromCache.value=!!hall.value;
  if(!cache.signedIn)return;
  if(!online.value){if(!hall.value)failure.value='离线中，本机还没有这个社区账号的收藏缓存。';return;}
  if(!force&&!cache.dirty&&cache.hall&&Date.now()-(cache.cachedAt||0)>=0&&Date.now()-(cache.cachedAt||0)<300000)return;
  const result=await treeholeRequest('honors.hall');if(!active)return;
  if(!result.hall?.progress)throw Error('invalid_response');
  hall.value=result.hall;fromCache.value=false;
  const fresh=pendingAwards(result,result.hall.id);
  if(result.awardOwner===result.hall.id)for(const code of result.unlocks||[])if(!fresh.includes(code))delivered.add(code);
  pending.value=fresh;
  if(!fresh.length&&delivered.size){const codes=[...delivered];delivered.clear();void treeholeRequest('honors.ack',{codes}).catch(()=>{});}
 }catch(e){if(active){if(['session_expired','forbidden','not_found'].includes(treeholeErrorCode(e))){hall.value=undefined;signedIn.value=false;fromCache.value=false;}else failure.value=treeholeError(e);}}
 finally{if(active)loading.value=false;}
}
async function show(a:Collectible){
 selected.value=a;
 if(earned.value[a.code])viewHidden(a.code);
 await nextTick();
 if(active&&detail.value&&!detail.value.open)detail.value.showModal();
}
function closeDetail(){if(!detail.value?.open)return false;detail.value.close();return true;}
function openMedal(code:string){
 const medal=byCode.get(code);if(medal)void show(medal);
}
defineExpose({closeDetail,openMedal});
const online=ref(navigator.onLine);
function networkChanged(){online.value=navigator.onLine;}
async function pin(a:Collectible){
 if(loading.value||!earned.value[a.code])return;
 if(a.source!=='community'){await togglePrivate(a.code);return;}
 if(!hall.value||!navigator.onLine)return;
 const old=hall.value,items=pinned(a)?old.showcase.filter(k=>k!==a.code):[...old.showcase,a.code];
 if(!pinned(a)&&pinCount(a)>=3)return;
 loading.value=true;failure.value='';
 try{const r=await treeholeRequest('honors.wear',{honor:old.badges.worn?.code??null,showcase:items});if(active&&r.hall){hall.value=r.hall;fromCache.value=false;}}
 catch(e){if(active){failure.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired'){hall.value=undefined;signedIn.value=false;}}}
 finally{if(active)loading.value=false;}
}
onMounted(()=>{window.addEventListener('online',networkChanged);window.addEventListener('offline',networkChanged);void load();});
onUnmounted(()=>{active=false;window.removeEventListener('online',networkChanged);window.removeEventListener('offline',networkChanged);});
</script>
<template>
<div class="collection">
 <AchievementNotice :codes="localQueue.length?[]:pending" can-open @open="openMedal" v-bind="feedback" @shown="hall && markPresented(hall.id,$event)" @seen="seen"/>
 <section class="cabinet">
  <header><div><h2>成就收藏馆</h2><p>你的每一段校园经历，都值得被记住</p></div><Trophy :size="23" aria-hidden="true"/></header>
  <div class="progress-heading"><div><strong>{{count}}</strong><span> / {{catalog.length}}</span><small>{{hall?'已解锁成就':'本机已确认成就'}}</small></div><b>{{percent}}% 完成</b></div>
  <progress :max="catalog.length" :value="count" aria-label="成就收藏进度"/>
  <nav aria-label="成就分类"><button v-for="g in groups" :key="g" :aria-pressed="category===g" @click="category=g">{{g}}</button></nav>
  <div class="cabinet-grid">
   <button v-for="a in cards" :key="a.code" :data-code="a.code" :class="{unlocked:earned[a.code]}" :style="{'--medal':a.color}" @click="show(a)">
    <span class="medallion"><component :is="concealed(a)?HelpCircle:earned[a.code]?a.icon:LockKeyhole" :size="25" :stroke-width="1.8"/></span>
    <strong>{{concealed(a)?'隐藏成就':a.name}}</strong><small>{{stateLabel(a)}}</small><Bookmark v-if="pinned(a)" class="pin" :size="11" aria-label="展示中"/>
   </button>
  </div>
 </section>
 <p v-if="storageIssue" class="collection-status" role="alert">{{storageIssue}}</p>
 <section class="collection-account"><header><div><h3>{{hall?.nickname||'社区身份与荣誉'}}</h3><p>{{hall?(fromCache?'上次同步的账号收藏':'已同步邯院通账号'):loading?'正在读取社区收藏…':signedIn?'社区收藏暂未同步':'登录社区后可同步身份与社区成就'}}</p></div><button v-if="signedIn" class="refresh" aria-label="刷新社区收藏" :disabled="loading" @click="load(true)"><RefreshCw :size="17"/></button></header>
 <OfficialBadges full v-if="hall" :items="[hall.badges.official,...hall.honors]"/>
 <p v-if="failure" role="alert">{{failure}}</p>
 <button class="account-more" @click="emit('account')">{{signedIn?'社区主页与荣誉管理':'前往社区账号'}}<ChevronRight :size="16"/></button>
 </section>
 <details class="collection-account"><summary>收藏与解锁提醒</summary><p>本机、教务与学习通收藏仅自己可见。社区收藏随邯院通账号同步，可选三枚展示给其他同学。</p>
 <label><input type="checkbox" v-model="feedback.haptics"/>轻微震动</label><label><input type="checkbox" v-model="feedback.sound"/>解锁提示音</label><label><input type="checkbox" :checked="!feedback.motion" @change="feedback.motion=!($event.target as HTMLInputElement).checked"/>减少动态效果</label>
 </details>
 <dialog ref="detail" class="collect-detail" :class="{quiet:!feedback.motion}" aria-labelledby="medal-title" @click.self="detail?.close()">
  <template v-if="selected"><button class="detail-close" aria-label="关闭成就详情" autofocus @click="detail?.close()"><X :size="20"/></button>
  <div class="hero-medal" :class="{locked:!earned[selected.code]}" :style="{'--medal':selected.color}"><component :is="concealed(selected)?HelpCircle:selected.icon" :size="39" :stroke-width="1.65"/></div>
  <small class="eyebrow">{{selected.group}} · {{selected.tier}}</small><h2 id="medal-title">{{concealed(selected)?'隐藏成就':selected.name}}</h2>
  <p>{{concealed(selected)?'有些校园回忆，会在意想不到的时候出现。':selected.description}}</p>
  <div class="details-meta"><template v-if="!concealed(selected)"><span>获取条件</span><strong>{{selected.condition}}</strong></template>
  <span>收藏归属</span><strong>{{sourceNames[selected.source]}}</strong>
  <template v-if="earned[selected.code]"><span>{{localStamps[selected.code]?.historical||hall?.backfilled?.includes(selected.code)?'历史记录核实':'解锁日期'}}</span><strong>{{honorDate(earned[selected.code])}}</strong></template>
  <template v-else-if="!concealed(selected)"><span>当前进度</span><strong>{{progress(selected)===null?'待账号同步':progress(selected)+' / '+selected.goal}}</strong></template></div>
  <button v-if="earned[selected.code]" class="wear" :disabled="loading||(selected.source==='community'&&!online)||(!pinned(selected)&&pinCount(selected)>=3)" @click="pin(selected)"><component :is="pinned(selected)?Check:Bookmark" :size="16"/>{{selected.source==='community'&&!online?(pinned(selected)?'已展示 · 离线':'离线，稍后展示'):pinned(selected)?'取下':selected.source==='community'?'展示到社区主页':'展示到我的页面'}} · {{pinCount(selected)}}/3</button>
  <p v-if="failure&&selected.source==='community'" role="alert">{{failure}}</p>
  </template>
 </dialog>
</div>
</template>
<style scoped>
.collection{display:grid;gap:12px;max-width:660px;margin:auto;padding-bottom:14px;color:var(--color-text)}.cabinet,.collection-account{border:1px solid var(--color-divider,#e6e4e9);background:var(--color-surface,#fff);border-radius:20px;padding:18px}.collection header,.progress-heading,.account-more{display:flex;align-items:center;justify-content:space-between;gap:8px}.collection h2,.collection h3,.collect-detail h2{margin:0;font-weight:720;letter-spacing:-.035em}.collection header>svg{color:#b29560}.collection p{font-size:13px;color:var(--color-muted);line-height:1.55;margin:5px 0}.progress-heading{align-items:flex-end;margin:18px 0 12px}.progress-heading strong{font-size:37px;line-height:1;letter-spacing:-2px;font-variant-numeric:tabular-nums}.progress-heading span{color:var(--color-muted);font-size:16px}.progress-heading small,.cabinet-grid small{display:block;color:var(--color-muted);font-size:11px;margin-top:4px}.progress-heading b{align-self:center;background:#e4f3e9;color:#326a4c;border-radius:20px;padding:4px 9px;font-size:12px}.cabinet progress{width:100%;height:7px;appearance:none;border:0;border-radius:8px;overflow:hidden;background:#ece9ef}.cabinet progress::-webkit-progress-bar{background:#ece9ef}.cabinet progress::-webkit-progress-value{background:#ac92d9;border-radius:8px}.cabinet nav{display:flex;flex-wrap:wrap;gap:6px;margin:13px 0 15px}.cabinet nav button{border:1px solid var(--color-divider);color:var(--color-muted);background:var(--color-surface);border-radius:99px;padding:6px 12px;min-height:34px;font-size:13px}.cabinet nav button[aria-pressed=true]{color:var(--color-surface);background:var(--color-text);border-color:var(--color-text)}.cabinet-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px}.cabinet-grid button{min-width:0;position:relative;text-align:center;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:95px;padding:8px 2px;border-radius:14px;background:var(--color-surface-muted,#f4f3f5);border:1px solid transparent;color:var(--color-muted)}.cabinet-grid button.unlocked{background:color-mix(in srgb,var(--medal) 8%,var(--color-surface));color:var(--color-text)}.medallion,.hero-medal{display:grid;place-items:center}.medallion{width:37px;height:37px;margin-bottom:5px;color:#9897a1}.unlocked .medallion{color:var(--medal)}.cabinet-grid strong{font-weight:620;font-size:clamp(10px,2.85vw,13px);line-height:1.4;overflow-wrap:anywhere}.cabinet-grid small{margin-top:2px;font-size:10px}.cabinet-grid .pin{position:absolute;right:6px;top:5px;color:var(--medal)}.collection-account summary{font-weight:650;cursor:pointer}.collection-account label{display:flex;gap:8px;align-items:center;min-height:40px;font-size:14px}.collection-account label input{width:17px;height:17px;accent-color:#795aab}.account-more{margin-top:10px;font-size:13px;font-weight:620;color:var(--color-primary);padding:6px 0}.refresh,.detail-close{display:grid;place-items:center;min-width:40px;min-height:40px}.collect-detail{position:fixed;width:min(88vw,360px);max-height:78dvh;overflow:auto;box-sizing:border-box;padding:24px;border-radius:24px;border:1px solid var(--color-divider);background:var(--color-surface,#fff);color:var(--color-text);box-shadow:0 20px 80px #28203322}.collect-detail::backdrop{background:#24212c59}.detail-close{position:absolute;right:8px;top:8px}.hero-medal{height:72px;width:72px;background:color-mix(in srgb,var(--medal) 12%,var(--color-surface));color:var(--medal);border-radius:22px;margin:3px 0 16px}.hero-medal.locked{filter:grayscale(1)}.eyebrow{font-size:12px;color:var(--color-muted)}.details-meta{display:grid;grid-template-columns:auto 1fr;gap:10px 16px;border-top:1px solid var(--color-divider);margin-top:14px;padding-top:14px;font-size:13px}.details-meta span{color:var(--color-muted)}.details-meta strong{font-weight:550}.wear{display:flex;gap:8px;align-items:center;justify-content:center;background:#f1eaf9;color:#684990;border-radius:12px;padding:11px;width:100%;margin-top:17px}.wear:disabled{opacity:.55}@media(max-width:340px){.cabinet{padding:13px}.cabinet-grid{gap:4px}}@media(prefers-reduced-motion:no-preference){.collect-detail[open]:not(.quiet){animation:medal-in .2s ease-out}@keyframes medal-in{from{opacity:0;transform:translateY(8px) scale(.98)}}}
</style>
