<script setup lang="ts">
import {computed,ref} from 'vue';
import {ChevronRight,BookOpen} from 'lucide-vue-next';
import {badges,type Badge} from '../../domain/communityHonors';
import type {Collectible} from '../../domain/globalAchievements';
import BadgeDetail from './BadgeDetail.vue';
const props=defineProps<{medals:Collectible[]; honor?:Badge; latest?:Collectible; fresh?:boolean; personal?:boolean; compact?:boolean; first?:boolean; pinned?:boolean}>();
const emit=defineEmits<{hall:[];medal:[code:string]}>();
const detail=ref<InstanceType<typeof BadgeDetail>>();
const latestOnShelf=computed(()=>props.medals.some(a=>a.code===props.latest?.code));
const firstPage=computed(()=>props.first&&!props.honor);
</script>
<template>
 <section class="honor-case" :class="{'case-first':firstPage,'case-compact':compact}" aria-label="荣誉展柜">
  <header><div class="case-heading"><h2>荣誉殿堂</h2>
   <button v-if="compact&&honor" class="case-signature" :style="{'--ink':badges[honor.code].color,'--night':badges[honor.code].dark}" @click="detail?.show(honor)">
    <component :is="badges[honor.code].icon" :size="14"/>{{badges[honor.code].name}}
   </button></div><button type="button" class="case-all" aria-label="查看全部荣誉殿堂藏品" @click="emit('hall')">查看全部<ChevronRight :size="14" aria-hidden="true"/></button></header>
  <button v-if="honor&&!compact" class="case-honor" @click="detail?.show(honor)" :style="{'--ink':badges[honor.code].color,'--night':badges[honor.code].dark}">
   <span class="case-seal"><component :is="badges[honor.code].icon" :size="23" :stroke-width="1.65"/></span>
   <span><strong>{{badges[honor.code].name}}</strong><small>{{badges[honor.code].description}}</small></span>
  </button>
  <div v-if="medals.length" class="case-rail" :class="{'private-shelf':personal&&pinned}">
   <button v-for="a in medals" :key="a.code" type="button" :aria-label="'查看成就「'+a.name+'」'" @click="emit('medal',a.code)" :style="{'--enamel':a.color}">
    <span class="case-medal"><i v-if="compact&&fresh&&a.code===latest?.code" class="fresh-dot" aria-label="新收藏"/><component :is="a.icon" :size="21" :stroke-width="1.65" aria-hidden="true"/></span>
    <span class="case-label">{{a.name}}<small v-if="firstPage">你的邯院收藏，从这里开始</small></span>
   </button>
  </div>
  <button v-if="personal&&latest&&!firstPage&&(!compact||!latestOnShelf)" class="case-latest" @click="emit('medal',latest.code)"><span v-if="fresh" class="fresh-dot"/>{{fresh?'新收藏':'最近获得'}} · {{latest.name}}<ChevronRight :size="12"/></button>
  <p v-else-if="!medals.length&&!honor" class="case-empty"><BookOpen :size="18"/>{{personal?'校园纪念章会陈列在这里':'这位同学还没有展示藏品'}}</p>
  <BadgeDetail ref="detail"/>
 </section>
</template>
<style scoped>
.honor-case{--case-paper:#fffcf7;--case-edge:#e7dfd1;--case-ink:#332f2a;--case-muted:#736b60;position:relative;isolation:isolate;min-width:0;padding:13px 16px 9px;text-align:left;color:var(--case-ink);border:1px solid var(--case-edge);border-radius:17px;background:linear-gradient(122deg,var(--case-paper),color-mix(in srgb,var(--case-paper) 94%,#baa796));box-shadow:inset 0 1px 0 #ffffff45,0 1px 3px #483c2810}
.honor-case header{display:flex;align-items:center;justify-content:space-between;gap:8px}
.honor-case header h2{margin:0;font-size:18px;line-height:1.4;font-weight:650;letter-spacing:.01em;color:inherit}
.honor-case button{border:0;background:transparent;color:inherit;font-family:inherit;cursor:pointer}.case-all{display:flex;gap:2px;align-items:center;min-height:32px;padding:0;font-size:11px;color:var(--case-muted)!important}
.case-all::after{content:"";position:absolute;inset:0;border-radius:17px}
.case-rail{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));position:relative;margin-top:3px;padding:3px 0 7px;column-gap:4px;border-bottom:1px solid var(--case-edge);box-shadow:0 2px 2px -2px #87775f77;pointer-events:none}
.case-rail button,.case-honor,.case-latest{position:relative;z-index:1;pointer-events:auto}
.case-rail button{display:flex;flex-direction:column;align-items:center;gap:5px;min-width:0;padding:3px 2px;font-size:12px;font-weight:550}
.case-medal,.case-seal{display:grid;place-items:center;flex:none;border-radius:50%}
.case-medal{width:39px;height:39px;background:radial-gradient(circle at 37% 24%,color-mix(in srgb,var(--enamel) 9%,var(--case-paper)),color-mix(in srgb,var(--enamel) 30%,var(--case-paper)));border:1px solid color-mix(in srgb,var(--enamel) 47%,var(--case-paper));box-shadow:inset 0 0 0 2px var(--case-paper),0 2px 2px #3c2d1912;color:color-mix(in srgb,var(--enamel) 73%,var(--case-ink))}
.case-label{max-width:100%;line-height:1.4;overflow-wrap:anywhere}.case-first .case-rail{grid-template-columns:1fr;border:none;box-shadow:none}.case-first .case-rail button{flex-direction:row;text-align:left;gap:12px}.case-first .case-medal{width:43px;height:43px}.case-label small,.case-honor small{display:block;font-size:11px;font-weight:400;line-height:1.55;color:var(--case-muted);margin-top:2px}
.case-honor{display:flex;align-items:center;gap:10px;text-align:left;padding:7px 0 4px}.case-seal{width:38px;height:38px;color:var(--ink);background:color-mix(in srgb,var(--ink) 10%,var(--case-paper));border:1px solid color-mix(in srgb,var(--ink) 28%,var(--case-paper))}.case-honor strong{font-size:14px;font-weight:650}.case-latest,.case-empty{display:flex;align-items:center;gap:5px;color:var(--case-muted)!important;font-size:11px;line-height:1.45}.case-latest{min-height:28px;padding:2px 0 0}.case-empty{margin:8px 0 7px}.fresh-dot{width:5px;height:5px;border-radius:50%;background:#98634d}.honor-case button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px}
:global([data-theme=dark] .honor-case){--case-paper:#28282c;--case-edge:#484449;--case-ink:#f2eae2;--case-muted:#bcb4aa}
:global([data-theme=dark] .case-seal){color:var(--night)}
.case-medal,.case-seal{position:relative;isolation:isolate}.case-rail button{padding-bottom:5px;gap:8px}
.case-medal::after,.case-seal::after{content:"";position:absolute;z-index:-1;bottom:-5px;left:calc(50% - 10px);width:20px;height:7px;background:color-mix(in srgb,var(--enamel,var(--ink)) 55%,var(--case-paper));clip-path:polygon(16% 0,46% 0,43% 100%,23% 70%,0 84%,9% 0,91% 0,100% 84%,77% 70%,57% 100%,54% 0)}
.case-seal{box-shadow:inset 0 0 0 2px var(--case-paper),inset 0 0 0 3px color-mix(in srgb,var(--ink) 20%,var(--case-paper));margin-bottom:3px}
.case-heading{display:flex;align-items:center;gap:8px;flex-wrap:wrap;min-width:0}
.case-compact{padding:5px 13px 9px}
.case-compact header{min-height:40px}
.case-compact header h2{font-size:16px}
.case-compact .case-all{min-height:44px;flex-shrink:0;font-size:12px}
.case-compact .case-signature{position:relative;z-index:1;display:inline-flex;align-items:center;gap:4px;min-height:44px;padding:0 3px;font-size:12px;color:var(--ink)}
:global([data-theme=dark] .case-compact) .case-signature{color:var(--night)}
.case-compact .case-rail{margin:0;padding:2px 0;border:0;box-shadow:none}
.case-compact .case-rail button{min-height:48px}
.case-compact .case-latest{min-height:44px;border-top:1px solid var(--case-edge);width:100%;margin-top:4px}
.case-compact .case-medal .fresh-dot{position:absolute;right:0;top:0;width:7px;height:7px;box-shadow:0 0 0 2px var(--case-paper)}
</style>
