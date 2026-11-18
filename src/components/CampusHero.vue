<script setup lang="ts">
import {ref,watch,onMounted,onUnmounted,computed} from 'vue';
import {tapSequence} from '../domain/discoveryGestures';
import {discover,moment} from '../services/hiddenDiscovery';
import {feedback} from '../services/achievementJournal';
import {Bell,Pause,Play} from 'lucide-vue-next';
import {Capacitor,type PluginListenerHandle} from '@capacitor/core';
import {App} from '@capacitor/app';
const props=defineProps<{date:string;week:string;unread:boolean;obscured:boolean}>();
defineEmits<{notifications:[]}>();
const scene=ref<HTMLElement>(),visible=ref(false),foreground=ref(!document.hidden),scrolling=ref(false),paused=ref(false),reduced=ref(false);
const running=computed(()=>visible.value&&foreground.value&&!scrolling.value&&!paused.value&&!reduced.value);
let observer:IntersectionObserver|undefined,listener:PluginListenerHandle|undefined,timer:ReturnType<typeof setTimeout>,disposed=false;
const media=window.matchMedia('(prefers-reduced-motion: reduce)');
function motion(){reduced.value=media.matches}
function visibility(){foreground.value=!document.hidden}
function scroll(){scrolling.value=true;clearTimeout(timer);timer=setTimeout(()=>scrolling.value=false,180)}
const taps=tapSequence(5);
const holding=ref(false);
let holdTimer:ReturnType<typeof setTimeout>|undefined;
let origin:{x:number;y:number;id:number}|undefined,skipClick=false;
function release(){clearTimeout(holdTimer);holding.value=false;origin=undefined;}
function cancel(){release();taps.reset();skipClick=true;}
function begin(){
  release();holding.value=true;skipClick=false;
  holdTimer=setTimeout(()=>{skipClick=true;taps.reset();void discover('dream');},3000);
}
function press(e:PointerEvent){
  if(!e.isPrimary||e.button!==0)return;
  begin();origin={x:e.clientX,y:e.clientY,id:e.pointerId};
  (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
}
function move(e:PointerEvent){
  if(origin?.id===e.pointerId&&Math.hypot(e.clientX-origin.x,e.clientY-origin.y)>12)cancel();
}
function tap(){if(!skipClick&&taps.tap())void discover('puff');skipClick=false;}
function keydown(e:KeyboardEvent){if(e.key===' '){e.preventDefault();if(!e.repeat)begin();}}
function keyup(e:KeyboardEvent){if(e.key===' '){e.preventDefault();if(holding.value){release();tap();}}}
watch(()=>props.obscured||!foreground.value||!visible.value,hidden=>{if(hidden)cancel();});
onUnmounted(cancel);
onMounted(()=>{
 motion();media.addEventListener('change',motion);document.addEventListener('visibilitychange',visibility);document.addEventListener('scroll',scroll,true);
 if(scene.value&&typeof IntersectionObserver!=='undefined'){observer=new IntersectionObserver(([entry])=>visible.value=entry?.isIntersecting??false,{threshold:.1});observer.observe(scene.value)}
 else visible.value=true;
 if(Capacitor.isNativePlatform())void App.addListener('appStateChange',state=>{foreground.value=state.isActive}).then(handle=>{if(disposed)void handle.remove();else listener=handle}).catch(()=>{});
});
onUnmounted(()=>{disposed=true;observer?.disconnect();void listener?.remove();clearTimeout(timer);media.removeEventListener('change',motion);document.removeEventListener('visibilitychange',visibility);document.removeEventListener('scroll',scroll,true)});
</script>
<template>
 <header ref="scene" class="campus-hero" :class="{'fish-running':running&&!obscured&&!holding&&!moment}">
  <img class="campus-art" src="/art/campus-autumn.webp" alt="" width="1200" height="800" fetchpriority="high"/>
  <div class="campus-hero-top"><div><h1>邯院通</h1><p>学习 · 生活 · 校园</p></div><button class="hero-notifications" aria-label="查看通知" @click="$emit('notifications')"><Bell :size="21"/><i v-if="unread"/></button></div>
  <p class="campus-motto">校园里的事，<br/>简单一点。</p>
  <div class="fish-pool"><button type="button" class="fish-swim mascot-touch" aria-label="首页小金鱼" :class="{'fish-puff':moment==='puff','fish-dream':moment==='dream','fish-quiet':!feedback.motion}" @pointerdown="press" @pointermove="move" @pointerup="release" @pointercancel="cancel" @keydown="keydown" @keyup="keyup" @blur="cancel" @click="tap" @contextmenu.prevent><svg class="campus-fish" viewBox="0 0 180 112" fill="none"><g class="fish-bob" stroke="#30243b" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path class="fish-flag" d="M84 39 91 9C103 3 111 17 125 10L120 32C106 40 101 24 88 30" fill="#fff9ed"/><path d="M18 66C29 43 56 34 81 39C105 40 115 51 130 55C145 40 158 35 158 46C158 53 150 61 148 64C156 70 162 80 155 84C148 88 137 78 130 76C108 88 86 99 60 93C40 90 22 81 18 66Z" fill="#fff6e9"/><path v-if="moment==='dream'" d="M38 62q5 6 11 0"/><circle v-else cx="43" cy="62" r="3.2" fill="#30243b" stroke="none"/><g v-if="moment==='puff'"><path d="m36 53 11 4"/><circle cx="46" cy="74" r="7" fill="#efb99d" stroke="none"/><circle cx="14" cy="55" r="5" stroke="#88b9c9"/></g><g v-if="moment==='dream'" fill="#fbf6ff" stroke="#9985ae" stroke-width="2"><circle cx="54" cy="32" r="3"/><circle cx="60" cy="25" r="4"/><path d="M62 17q-5-10 6-10 4-8 12-3 10-2 11 6 5 9-7 10H69Z"/></g><path d="M63 73q7 5 13 0" stroke-width="2.5"/><path d="M19 38 11 29M32 30 28 18M45 27 47 15" stroke-width="3"/></g></svg><span class="fish-ripple"/></button></div>
  <div class="hero-date"><span>{{date}}</span><span>{{week}}</span></div>
  <button v-if="!reduced" class="fish-motion" :aria-label="paused?'播放小鱼动画':'暂停小鱼动画'" :aria-pressed="paused" @click="paused=!paused"><Play v-if="paused" :size="13"/><Pause v-else :size="13"/></button>
 </header>
</template>

<style scoped>.mascot-touch{pointer-events:auto;touch-action:manipulation;border:0;background:none;padding:0;user-select:none;-webkit-touch-callout:none}.mascot-touch:focus-visible{outline:2px solid var(--color-primary);border-radius:50%}.fish-puff:not(.fish-quiet) .campus-fish{animation:cheeks .55s ease-out}@keyframes cheeks{45%{transform:scale(1.07,.95)}}@media(prefers-reduced-motion:reduce){.fish-puff .campus-fish{animation:none!important}}</style>
