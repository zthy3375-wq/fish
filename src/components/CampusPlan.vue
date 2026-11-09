<script setup lang="ts">
import {onMounted,onUnmounted,ref,watch} from 'vue';
import * as L from 'leaflet';
import 'leaflet/dist/leaflet.css';
const campus=ref<'east'|'west'>('west'),element=ref<HTMLElement>(),imageFailed=ref(false);
let map:L.Map|undefined,overlay:L.ImageOverlay|undefined,resize:ResizeObserver|undefined;
function fullView(){if(!map)return;const h=campus.value==='west'?1222:1536,w=campus.value==='west'?864:709;map.fitBounds([[0,0],[h,w]],{animate:false,padding:[8,8]})}
function load(){if(!map)return;overlay?.remove();imageFailed.value=false;const west=campus.value==='west',width=west?864:709,height=west?1222:1536;overlay=L.imageOverlay(`/campus/${campus.value}-plan.jpg`,[[0,0],[height,width]]).on('error',()=>{imageFailed.value=true}).addTo(map);fullView()}
watch(campus,load);
onMounted(()=>{if(!element.value)return;map=L.map(element.value,{crs:L.CRS.Simple,zoomAnimation:false,fadeAnimation:false,zoomSnap:.1,minZoom:-3,maxZoom:3,attributionControl:false});load();resize=new ResizeObserver(()=>map?.invalidateSize({pan:false}));resize.observe(element.value)});
onUnmounted(()=>{resize?.disconnect();map?.remove()});
</script>
<template><section class="plan"><div class="plan-switch"><button :class="{active:campus==='west'}" @click="campus='west'">西校区平面图</button><button :class="{active:campus==='east'}" @click="campus='east'">东校区平面图</button></div><div ref="element" class="canvas" aria-label="校园平面图，可双指缩放"/><p v-if="imageFailed" role="status">平面图加载失败，<button @click="load">重新加载</button></p><div class="plan-tools"><button @click="fullView">显示全图</button></div><p>双指缩放、拖动查看校园平面图。</p><details><summary>图源说明</summary><p>平面图由用户提供，版本日期待核对，楼名与道路以现场标识为准。</p></details></section></template>
<style scoped>.plan-switch,.plan-tools{display:flex;gap:8px;margin:12px 0}.plan-switch button,.plan-tools button{flex:1;min-height:42px;padding:10px;border:1px solid var(--color-border);border-radius:10px;background:var(--color-surface);color:var(--color-text);font-size:12px}.plan-switch .active{background:var(--color-primary);color:#fff}.canvas{height:48vh;height:48dvh;min-height:300px;isolation:isolate;background:#f6f5ed;border-radius:14px}.plan p,.plan details{font-size:11px;color:var(--color-muted);line-height:1.65}</style>
