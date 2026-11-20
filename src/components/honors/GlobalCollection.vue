<script setup lang="ts">
import {computed,nextTick,onMounted,onUnmounted,ref,shallowRef,watch} from 'vue';
import {Bookmark,Check,ChevronRight,HelpCircle,LockKeyhole,RefreshCw,Trophy,X} from 'lucide-vue-next';
import {catalog,groups,lifeCodes,sourceNames,type Group} from '../../domain/globalAchievements';
import {communityAchievementCards,type AchievementCard} from '../../domain/communityAchievementCards';
import type {CollectionProfile} from '../../domain/honorCollection';
import {clearHonorCollectionCache,getHonorCollection} from '../../services/honorCollectionCache';
import {cachedHall,feedback,localQueue,localStamps,privatePins,viewHidden,scopes,storageIssue,togglePrivate} from '../../services/achievementJournal';
import {treeholeRequest,treeholeError,treeholeErrorCode} from '../../services/treehole';
import {honorDate,type HonorHall} from '../../domain/communityHonors';
import {pendingAwards,markPresented} from '../../services/achievementDelivery';
import AchievementNotice from './AchievementNotice.vue';
import OfficialBadges from './OfficialBadges.vue';

const emit=defineEmits<{account:[]}>();
const category=ref<Group>('全部'),selectedCode=ref(''),detail=ref<HTMLDialogElement>();
const hall=ref<HonorHall>(),loading=ref(false),failure=ref(''),fromCache=ref(false),signedIn=ref(false);
const cloud=shallowRef<CollectionProfile>();
const pending=ref<string[]>([]);
let active=true;
function seen(code:string){
  const owner=hall.value?.id;if(!owner)return;
  markPresented(owner,code);delivered.add(code);pending.value=pending.value.filter(k=>k!==code);
  if(!pending.value.length&&delivered.size){const codes=[...delivered];delivered.clear();void treeholeRequest('honors.ack',{codes}).catch(()=>{});}
}
const delivered=new Set<string>();
const earned=computed(()=>({...Object.fromEntries(Object.entries(localStamps.value).map(([k,v])=>[k,v.at])),...hall.value?.awards,...cloud.value?.baseAwards}));
const allCards=computed<AchievementCard[]>(()=>[...catalog,...communityAchievementCards(cloud.value?.items,!!cloud.value)]);
const selected=computed(()=>allCards.value.find(card=>card.code===selectedCode.value));
watch(selected,card=>{if(!card&&detail.value?.open)detail.value.close();});
const activeCards=computed(()=>allCards.value.filter(a=>a.group!=='已停发'));
const count=computed(()=>activeCards.value.filter(isEarned).length);
const percent=computed(()=>Math.round(100*count.value/activeCards.value.length));
const cards=computed(()=>category.value==='全部'?activeCards.value:allCards.value.filter(a=>a.group===category.value));
const availableGroups=computed(()=>groups.filter(group=>group!=='已停发'||allCards.value.some(a=>a.group===group)));
function isEarned(a:AchievementCard){return Boolean(earned.value[a.code]||a.cloud?.awardId);}
const concealed=(a:AchievementCard)=>a.hidden&&!isEarned(a);
function unknown(a:AchievementCard){return a.needsSync===true||(a.source==='community'?!a.cloud&&!hall.value&&!cloud.value:a.source!=='device'&&!scopes.value[a.source]);}
function stateLabel(a:AchievementCard){return isEarned(a)?'已解锁':unknown(a)?(a.source==='community'?'待同步':'待连接'):concealed(a)?'尚未发现':'未解锁';}
const communityPins=computed(()=>cloud.value?.showcase??hall.value?.showcase??[]);
const pinKey=(a:AchievementCard)=>a.cloud?.awardId??a.code;
const pinned=(a:AchievementCard)=>a.source==='community'?communityPins.value.includes(pinKey(a)):privatePins.value.includes(a.code);
const pinCount=(a:AchievementCard)=>a.source==='community'?(cloud.value?.showcase?.length??hall.value?.showcaseUsed??communityPins.value.length):privatePins.value.length;
const privateCommunity=(a:AchievementCard)=>a.cloud?.category==='hidden'&&!a.cloud.publicHidden;
function progress(a:AchievementCard){
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
  const owner=cache.owner?.id ?? cache.hall?.id ?? cache.collection?.id;
  signedIn.value=cache.signedIn;
  hall.value=cache.signedIn&&cache.hall?.id===owner?cache.hall:undefined;
  cloud.value=cache.signedIn&&cache.collection?.id===owner?cache.collection:undefined;
  fromCache.value=!!(hall.value||cloud.value);
  if(!cache.signedIn)return;
  if(!online.value){if(!hall.value&&!cloud.value)failure.value='离线中，本机还没有这个社区账号的收藏缓存。';return;}
  const age=Date.now()-(cache.cachedAt||0);
  if(force||cache.dirty||!hall.value||age<0||age>=300000){
    const result=await treeholeRequest('honors.hall');if(!active)return;
    if(!result.hall?.progress)throw Error('invalid_response');
    hall.value=result.hall;
    if(cloud.value?.id!==result.hall.id)cloud.value=undefined;
    const fresh=pendingAwards(result,result.hall.id);
    if(result.awardOwner===result.hall.id)for(const code of result.unlocks||[])if(!fresh.includes(code))delivered.add(code);
    pending.value=fresh;
    if(!fresh.length&&delivered.size){const codes=[...delivered];delivered.clear();void treeholeRequest('honors.ack',{codes}).catch(()=>{});}
  }
  const id=hall.value.id;
  try {
    const first=await getHonorCollection(id,id,treeholeRequest,force||cache.dirty);
    if(!active)return;
    const items=first.items.slice(0,40);
    let more=first.items.length>40;
    while(more){
      const result=await treeholeRequest('collection.profile',{memberId:id,offset:items.length});
      if(!active)return;
      if(!result.collection||result.collection.id!==id)throw Error('invalid_response');
      items.push(...result.collection.items.slice(0,40));
      more=result.collection.items.length>40;
    }
    cloud.value={...first,items};
  } catch(error) {
    if(!['not_found','invalid_request'].includes(treeholeErrorCode(error)))throw error;
  }
  fromCache.value=false;
 }catch(e){if(active){if(['session_expired','forbidden'].includes(treeholeErrorCode(e))){hall.value=undefined;cloud.value=undefined;signedIn.value=false;fromCache.value=false;}else failure.value=treeholeError(e);}}
 finally{if(active)loading.value=false;}
}
async function show(a:AchievementCard){
 selectedCode.value=a.code;
 if(isEarned(a))viewHidden(a.code);
 await nextTick();
 if(active&&detail.value&&!detail.value.open)detail.value.showModal();
}
function closeDetail(){if(!detail.value?.open)return false;detail.value.close();return true;}
function openMedal(code:string){
 const medal=allCards.value.find(a=>a.code===code||a.cloud?.awardId===code);if(medal)void show(medal);
}
defineExpose({closeDetail,openMedal});
const online=ref(navigator.onLine);
function networkChanged(){
 online.value=navigator.onLine;
 if(online.value&&signedIn.value)void load();
}
async function pin(a:AchievementCard){
 if(loading.value||!isEarned(a)||privateCommunity(a))return;
 if(a.source!=='community'){await togglePrivate(a.code);return;}
 if(!hall.value||!navigator.onLine)return;
 const old=hall.value,key=pinKey(a),items=pinned(a)?communityPins.value.filter(k=>k!==key):[...communityPins.value,key];
 if(!pinned(a)&&pinCount(a)>=3)return;
 loading.value=true;failure.value='';
 try{
   if((cloud.value?.layoutVersion??0)>=2){
     const r=await treeholeRequest('collection.showcase',{items});
     if(active&&r.updatedIdentity&&cloud.value?.id===r.updatedIdentity.id){
       cloud.value={...cloud.value,showcase:r.updatedIdentity.showcase};clearHonorCollectionCache();fromCache.value=false;
     }
   }else if(!a.cloud){
     const r=await treeholeRequest('honors.wear',{honor:old.badges.worn?.code??null,showcase:items});
     if(active&&r.hall){hall.value=r.hall;fromCache.value=false;}
   }
 }
 catch(e){if(active){failure.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired'){hall.value=undefined;cloud.value=undefined;signedIn.value=false;}}}
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
  <div class="progress-heading"><div><strong>{{count}}</strong><span> / {{activeCards.length}}</span><small>{{hall||cloud?'已解锁成就':'本机已确认成就'}}</small></div><b>{{percent}}% 完成</b></div>
  <progress :max="activeCards.length" :value="count" aria-label="成就收藏进度"/>
  <nav aria-label="成就分类"><button v-for="g in availableGroups" :key="g" :aria-pressed="category===g" @click="category=g">{{g}}</button></nav>
  <div class="cabinet-grid">
   <button v-for="a in cards" :key="a.code" :data-code="a.code" :class="{unlocked:isEarned(a)}" :style="{'--medal':a.color}" @click="show(a)">
    <span class="medallion"><component :is="concealed(a)?HelpCircle:isEarned(a)?a.icon:LockKeyhole" :size="25" :stroke-width="1.8" aria-hidden="true"/></span>
    <strong>{{concealed(a)?'隐藏成就':a.name}}</strong><small class="achievement-state"><Check v-if="isEarned(a)" :size="12" aria-hidden="true"/>{{stateLabel(a)}}</small><Bookmark v-if="pinned(a)" class="pin" :size="11" aria-label="展示中"/>
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
  <div class="hero-medal" :class="{locked:!isEarned(selected)}" :style="{'--medal':selected.color}"><component :is="concealed(selected)?HelpCircle:isEarned(selected)?selected.icon:LockKeyhole" :size="39" :stroke-width="1.65" aria-hidden="true"/></div>
  <small class="eyebrow">{{selected.group}} · {{concealed(selected)?stateLabel(selected):selected.tier+' · '+stateLabel(selected)}}</small><h2 id="medal-title">{{concealed(selected)?'隐藏成就':selected.name}}</h2>
  <p>{{concealed(selected)?'有些校园回忆，会在意想不到的时候出现。':selected.description}}</p>
  <div class="details-meta"><template v-if="!concealed(selected)&&selected.condition"><span>获取条件</span><strong>{{selected.condition}}</strong></template>
  <span>收藏归属</span><strong>{{sourceNames[selected.source]}}</strong>
  <template v-if="isEarned(selected)"><span>{{localStamps[selected.code]?.historical||hall?.backfilled?.includes(selected.code)?'历史记录核实':'解锁日期'}}</span><strong>{{honorDate(selected.cloud?.at??earned[selected.code])}}</strong></template>
  <template v-else-if="!concealed(selected)&&!selected.cloud"><span>当前进度</span><strong>{{progress(selected)===null?'待账号同步':progress(selected)+' / '+selected.goal}}</strong></template></div>
  <p v-if="privateCommunity(selected)">这项隐藏成就仅自己可见，可在社区荣誉收藏中设置公开。</p>
  <button v-else-if="isEarned(selected)&&(!selected.cloud||(cloud?.layoutVersion??0)>=2)" class="wear" :disabled="loading||(selected.source==='community'&&!online)||(!pinned(selected)&&pinCount(selected)>=3)" @click="pin(selected)"><component :is="pinned(selected)?Check:Bookmark" :size="16"/>{{selected.source==='community'&&!online?(pinned(selected)?'已展示 · 离线':'离线，稍后展示'):pinned(selected)?'取下':selected.source==='community'?'展示到社区主页':'展示到我的页面'}} · {{pinCount(selected)}}/3</button>
  <p v-if="failure&&selected.source==='community'" role="alert">{{failure}}</p>
  </template>
 </dialog>
</div>
</template>
<style scoped>
.collection{display:grid;gap:12px;max-width:660px;margin:auto;padding-bottom:14px;color:var(--color-text)}.cabinet,.collection-account{border:1px solid var(--color-divider,#e6e4e9);background:var(--color-surface,#fff);border-radius:20px;padding:18px}.collection header,.progress-heading,.account-more{display:flex;align-items:center;justify-content:space-between;gap:8px}.collection h2,.collection h3,.collect-detail h2{margin:0;font-weight:720;letter-spacing:-.035em}.collection header>svg{color:#b29560}.collection p{font-size:13px;color:var(--color-muted);line-height:1.55;margin:5px 0}.progress-heading{align-items:flex-end;margin:18px 0 12px}.progress-heading strong{font-size:37px;line-height:1;letter-spacing:-2px;font-variant-numeric:tabular-nums}.progress-heading span{color:var(--color-muted);font-size:16px}.progress-heading small,.cabinet-grid small{display:block;color:var(--color-muted);font-size:11px;margin-top:4px}.progress-heading b{align-self:center;background:#e4f3e9;color:#326a4c;border-radius:20px;padding:4px 9px;font-size:12px}.cabinet progress{width:100%;height:7px;appearance:none;border:0;border-radius:8px;overflow:hidden;background:#ece9ef}.cabinet progress::-webkit-progress-bar{background:#ece9ef}.cabinet progress::-webkit-progress-value{background:#ac92d9;border-radius:8px}.cabinet nav{display:flex;flex-wrap:wrap;gap:6px;margin:13px 0 15px}.cabinet nav button{border:1px solid var(--color-divider);color:var(--color-muted);background:var(--color-surface);border-radius:99px;padding:6px 12px;min-height:34px;font-size:13px}.cabinet nav button[aria-pressed=true]{color:var(--color-surface);background:var(--color-text);border-color:var(--color-text)}.cabinet-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px}.cabinet-grid button{min-width:0;position:relative;text-align:center;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:95px;padding:8px 2px;border-radius:14px;background:var(--color-surface-muted,#f4f3f5);border:1px solid transparent;color:var(--color-muted)}.cabinet-grid button.unlocked{background:color-mix(in srgb,var(--medal) 8%,var(--color-surface));color:var(--color-text)}.medallion,.hero-medal{display:grid;place-items:center}.medallion{width:37px;height:37px;margin-bottom:5px;color:#9897a1}.unlocked .medallion{color:var(--medal)}.cabinet-grid strong{font-weight:620;font-size:clamp(10px,2.85vw,13px);line-height:1.4;overflow-wrap:anywhere}.cabinet-grid small{margin-top:2px;font-size:10px}.cabinet-grid .pin{position:absolute;right:6px;top:5px;color:var(--medal)}.collection-account summary{font-weight:650;cursor:pointer}.collection-account label{display:flex;gap:8px;align-items:center;min-height:40px;font-size:14px}.collection-account label input{width:17px;height:17px;accent-color:#795aab}.account-more{margin-top:10px;font-size:13px;font-weight:620;color:var(--color-primary);padding:6px 0}.refresh,.detail-close{display:grid;place-items:center;min-width:40px;min-height:40px}.collect-detail{position:fixed;width:min(88vw,360px);max-height:78dvh;overflow:auto;box-sizing:border-box;padding:24px;border-radius:24px;border:1px solid var(--color-divider);background:var(--color-surface,#fff);color:var(--color-text);box-shadow:0 20px 80px #28203322}.collect-detail::backdrop{background:#24212c59}.detail-close{position:absolute;right:8px;top:8px}.hero-medal{height:72px;width:72px;background:color-mix(in srgb,var(--medal) 12%,var(--color-surface));color:var(--medal);border-radius:22px;margin:3px 0 16px}.hero-medal.locked{filter:grayscale(1)}.eyebrow{font-size:12px;color:var(--color-muted)}.details-meta{display:grid;grid-template-columns:auto 1fr;gap:10px 16px;border-top:1px solid var(--color-divider);margin-top:14px;padding-top:14px;font-size:13px}.details-meta span{color:var(--color-muted)}.details-meta strong{font-weight:550}.wear{display:flex;gap:8px;align-items:center;justify-content:center;background:#f1eaf9;color:#684990;border-radius:12px;padding:11px;width:100%;margin-top:17px}.wear:disabled{opacity:.55}@media(max-width:340px){.cabinet{padding:13px}.cabinet-grid{gap:4px}}@media(prefers-reduced-motion:no-preference){.collect-detail[open]:not(.quiet){animation:medal-in .2s ease-out}@keyframes medal-in{from{opacity:0;transform:translateY(8px) scale(.98)}}}
.cabinet-grid button {border:1px dashed color-mix(in srgb,var(--color-muted) 38%,var(--color-surface));}
.cabinet-grid button.unlocked {border:1px solid color-mix(in srgb,var(--medal) 58%,var(--color-surface));}
.cabinet-grid .achievement-state {display:inline-flex;align-items:center;justify-content:center;gap:2px;padding:2px 4px;border-radius:4px;font-weight:650;}
.cabinet-grid .unlocked .achievement-state {color:var(--color-text);background:color-mix(in srgb,var(--medal) 20%,var(--color-surface));}
</style>
