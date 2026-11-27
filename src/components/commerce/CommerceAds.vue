<script setup lang="ts">
import {computed,onBeforeUnmount,onMounted,ref,watch} from 'vue';
import {ChevronLeft,ChevronRight,Flag} from 'lucide-vue-next';
import {trackCommerce,type Ad} from '../../services/commerce';
const props=defineProps<{ads:Ad[];media?:Record<string,string>;label:string;rotate?:boolean}>();
const emit=defineEmits<{select:[ad:Ad];report:[ad:Ad]}>();
const host=ref<HTMLElement>(),index=ref(0),visible=ref(false),clock=ref(Date.now()),paused=ref(false);
const live=computed(()=>props.ads.filter(ad=>Date.parse(ad.endsAt)>clock.value));
const selected=computed(()=>live.value[index.value%Math.max(1,live.value.length)]);
const slides=computed(()=>props.rotate?(selected.value?[selected.value]:[]):live.value);
const focused=ref(false);
let observer:IntersectionObserver|undefined,rotation:ReturnType<typeof setInterval>|undefined,deadline:ReturnType<typeof setTimeout>|undefined;
const motion=window.matchMedia('(prefers-reduced-motion: reduce)');
function shift(step:number){index.value=(index.value+step+live.value.length)%live.value.length;}
function refreshClock(){clock.value=Date.now();}
function observeClock(){
 clearTimeout(deadline);
 if(live.value.length)deadline=setTimeout(refreshClock,Math.max(1,Math.min(2_147_483_647,...live.value.map(ad=>Date.parse(ad.endsAt)-Date.now()+5))));
}
watch([live,visible,index],()=>{if(visible.value&&!document.hidden)for(const ad of slides.value)trackCommerce('impression',ad.id);observeClock();},{immediate:true});
watch(host,(element,previous)=>{if(previous)observer?.unobserve(previous);if(element)observer?.observe(element);});
onMounted(()=>{
 if('IntersectionObserver' in window){
  observer=new IntersectionObserver(entries=>{visible.value=entries.some(entry=>entry.isIntersecting&&entry.intersectionRatio>=0.5);},{threshold:0.5});
  if(host.value)observer.observe(host.value);
 }
 if(props.rotate)rotation=setInterval(()=>{
  if(!document.hidden&&visible.value&&!focused.value&&!paused.value&&!motion.matches&&live.value.length>1)shift(1);
 },6500);
 document.addEventListener('visibilitychange',refreshClock);
});
onBeforeUnmount(()=>{observer?.disconnect();clearTimeout(deadline);clearInterval(rotation);document.removeEventListener('visibilitychange',refreshClock);});
</script>

<template>
 <section v-if="slides.length" ref="host" class="commerce-ads" :aria-label="label"
   @mouseenter="paused=true" @mouseleave="paused=false" @focusin="focused=true" @focusout="focused=false">
  <article v-for="ad in slides" :key="ad.id" class="commerce-ad">
   <button class="commerce-ad-main" type="button" @click="emit('select',ad)">
    <img v-if="media?.[ad.image]" :src="media[ad.image]" alt="" loading="lazy" referrerpolicy="no-referrer"/>
    <span><small>广告</small><strong>{{ad.title}}</strong><span v-if="ad.subtitle">{{ad.subtitle}}</span></span>
    <ChevronRight :size="16"/>
   </button>
   <button type="button" class="commerce-ad-report" aria-label="举报广告" @click="emit('report',ad)"><Flag :size="16"/></button>
  </article>
  <div v-if="rotate&&live.length>1" class="commerce-ad-controls">
   <button type="button" aria-label="上一张广告" @click="shift(-1)"><ChevronLeft :size="16"/></button>
   <span>{{index%live.length+1}} / {{live.length}}</span>
   <button type="button" aria-label="下一张广告" @click="shift(1)"><ChevronRight :size="16"/></button>
  </div>
 </section>
</template>

<style scoped>
.commerce-ads{display:grid;gap:8px;min-width:0}.commerce-ad{display:flex;align-items:center;min-width:0;border:1px solid var(--color-border,#dfe4eb);border-radius:14px;background:var(--color-surface,#fff);padding:3px 3px 3px 0;overflow:hidden}
.commerce-ad-main{display:flex;align-items:center;gap:10px;min-height:74px;flex:1;min-width:0;padding:8px 12px;text-align:left;color:inherit}.commerce-ad-main img{width:64px;height:54px;object-fit:cover;border-radius:8px;flex:none}.commerce-ad-main>span{display:grid;gap:2px;min-width:0;flex:1}.commerce-ad-main strong,.commerce-ad-main span span{overflow-wrap:anywhere}.commerce-ad-main small{width:max-content;border:1px solid currentColor;border-radius:4px;padding:0 4px;font-size:10px;color:var(--color-muted,#545c68)}.commerce-ad-main span span{font-size:12px;color:var(--color-muted,#545c68)}
.commerce-ad-report,.commerce-ad-controls button{display:grid;place-items:center;width:44px;height:44px;color:var(--color-muted,#545c68);flex:none}.commerce-ad-controls{display:flex;align-items:center;justify-content:flex-end;font-size:12px;color:var(--color-muted,#545c68);margin-block:-4px}
</style>
