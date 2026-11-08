<script setup lang="ts">
import {onMounted,onUnmounted,ref,watch} from 'vue';
import * as L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type {PlanTarget} from '../services/campus-plan';
const props=defineProps<{target?:PlanTarget}>();
const campus=ref<'east'|'west'>(props.target?.campus||'west'),element=ref<HTMLElement>();
let map:L.Map|undefined,pin:L.CircleMarker|undefined,overlay:L.ImageOverlay|undefined,resize:ResizeObserver|undefined;
function load(){if(!map)return;overlay?.remove();pin?.unbindTooltip();pin?.remove();pin=undefined;const west=campus.value==='west';const width=west?864:709,height=west?1222:1536;overlay=L.imageOverlay(`/campus/${campus.value}-plan.jpg`,[[0,0],[height,width]]).addTo(map);map.fitBounds(west?[[height-740,45],[height-150,820]]:[[height-1200,0],[height-350,709]],{animate:false,padding:[8,8]});const target=props.target;if(target&&target.campus===campus.value){pin=L.circleMarker([height-target.y,target.x],{radius:12,color:"#d34f37",weight:3,fillOpacity:.15}).addTo(map);const label=document.createElement("span");label.textContent=target.name+" · 楼栋参考点";pin.bindTooltip(label,{permanent:true,direction:"top"});map.setView([height-target.y,target.x],0,{animate:false})}}
watch(campus,load);
onMounted(()=>{if(!element.value)return;map=L.map(element.value,{crs:L.CRS.Simple,zoomAnimation:false,fadeAnimation:false,zoomSnap:0.1,minZoom:-3,maxZoom:3,attributionControl:false});load();resize=new ResizeObserver(()=>{map?.invalidateSize();load()});resize.observe(element.value)});
onUnmounted(()=>{resize?.disconnect();map?.remove()});
</script>
<template><section class="plan"><div class="plan-switch"><button :class="{active:campus==='west'}" @click="campus='west'">西校区平面图</button><button :class="{active:campus==='east'}" @click="campus='east'">东校区平面图</button></div><div ref="element" class="canvas" aria-label="校园平面图，可双指缩放"/><p>双指缩放、拖动查看楼名。平面图由用户提供，版本日期待核对。</p><p>这是校园布局示意图，未标定经纬度；个人定位不会叠加到这张图上。</p><button class="reset" @click="load">显示全图</button></section></template>
<style scoped>.plan-switch{display:flex;gap:8px;margin:12px 0}.plan-switch button,.reset{flex:1;padding:11px;border:1px solid var(--color-border);border-radius:10px;background:var(--color-surface);color:var(--color-text);font-size:12px}.plan-switch .active{background:var(--color-primary);color:#fff}.canvas{height:60dvh;min-height:340px;isolation:isolate;background:#f6f5ed;border-radius:14px}.plan p{font-size:11px;color:var(--color-muted);line-height:1.65}.reset{width:100%}</style>
