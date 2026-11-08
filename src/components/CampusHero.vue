<script setup lang="ts">
import {ref,onMounted,onUnmounted,computed} from 'vue';
import {Bell,Pause,Play} from 'lucide-vue-next';
import {Capacitor,type PluginListenerHandle} from '@capacitor/core';
import {App} from '@capacitor/app';
defineProps<{date:string;week:string;unread:boolean;obscured:boolean}>();
defineEmits<{notifications:[]}>();
const scene=ref<HTMLElement>(),visible=ref(false),foreground=ref(!document.hidden),scrolling=ref(false),paused=ref(false),reduced=ref(false);
const running=computed(()=>visible.value&&foreground.value&&!scrolling.value&&!paused.value&&!reduced.value);
let observer:IntersectionObserver|undefined,listener:PluginListenerHandle|undefined,timer:ReturnType<typeof setTimeout>,disposed=false;
const media=window.matchMedia('(prefers-reduced-motion: reduce)');
function motion(){reduced.value=media.matches}
function visibility(){foreground.value=!document.hidden}
function scroll(){scrolling.value=true;clearTimeout(timer);timer=setTimeout(()=>scrolling.value=false,180)}
onMounted(()=>{
 motion();media.addEventListener('change',motion);document.addEventListener('visibilitychange',visibility);document.addEventListener('scroll',scroll,true);
 if(scene.value&&typeof IntersectionObserver!=='undefined'){observer=new IntersectionObserver(([entry])=>visible.value=entry?.isIntersecting??false,{threshold:.1});observer.observe(scene.value)}
 else visible.value=true;
 if(Capacitor.isNativePlatform())void App.addListener('appStateChange',state=>{foreground.value=state.isActive}).then(handle=>{if(disposed)void handle.remove();else listener=handle}).catch(()=>{});
});
onUnmounted(()=>{disposed=true;observer?.disconnect();void listener?.remove();clearTimeout(timer);media.removeEventListener('change',motion);document.removeEventListener('visibilitychange',visibility);document.removeEventListener('scroll',scroll,true)});
</script>
<template>
 <header ref="scene" class="campus-hero" :class="{'fish-running':running&&!obscured}">
  <img class="campus-art" src="/art/campus-autumn.webp" alt="" width="1200" height="800" fetchpriority="high"/>
  <div class="campus-hero-top"><div><h1>邯院通</h1><p>学习 · 生活 · 校园</p></div><button class="hero-notifications" aria-label="查看通知" @click="$emit('notifications')"><Bell :size="21"/><i v-if="unread"/></button></div>
  <p class="campus-motto">校园里的事，<br/>简单一点。</p>
  <div class="fish-pool" aria-hidden="true"><div class="fish-swim"><svg class="campus-fish" viewBox="0 0 180 112" fill="none"><g class="fish-bob" stroke="#30243b" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path class="fish-flag" d="M84 39 91 9C103 3 111 17 125 10L120 32C106 40 101 24 88 30" fill="#fff9ed"/><path d="M18 66C29 43 56 34 81 39C105 40 115 51 130 55C145 40 158 35 158 46C158 53 150 61 148 64C156 70 162 80 155 84C148 88 137 78 130 76C108 88 86 99 60 93C40 90 22 81 18 66Z" fill="#fff6e9"/><circle cx="43" cy="62" r="3.2" fill="#30243b" stroke="none"/><path d="M63 73q7 5 13 0" stroke-width="2.5"/><path d="M19 38 11 29M32 30 28 18M45 27 47 15" stroke-width="3"/></g></svg><span class="fish-ripple"/></div></div>
  <div class="hero-date"><span>{{date}}</span><span>{{week}}</span></div>
  <button v-if="!reduced" class="fish-motion" :aria-label="paused?'播放小鱼动画':'暂停小鱼动画'" :aria-pressed="paused" @click="paused=!paused"><Play v-if="paused" :size="13"/><Pause v-else :size="13"/></button>
 </header>
</template>
