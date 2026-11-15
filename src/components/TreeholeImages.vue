<script setup lang="ts">
import {computed,ref,watch} from 'vue';
import {ImageOff} from 'lucide-vue-next';
import {treeholeRequest,type TreeholeImage} from '../services/treehole';
const props=defineProps<{images:TreeholeImage[];postId:string;full?:boolean}>();
defineEmits<{open:[index:number]}>();
const renewed=ref<Record<string,string|null>>({}),attempted=new Set<string>(),page=ref(0);
watch(()=>props.postId,()=>{renewed.value={};attempted.clear();page.value=0;});
const ratio=computed(()=>{const i=props.images[0];return i?.width>0&&i?.height>0?i.width/i.height:1;});
const singleStyle=computed(()=>props.full?{'aspect-ratio':String(ratio.value)}:{'aspect-ratio':String(Math.max(.75,Math.min(1.8,ratio.value))),'max-width':ratio.value<.85?'240px':ratio.value<1.15?'300px':'100%'});
async function retry(image:TreeholeImage){if(attempted.has(image.id)){renewed.value[image.id]=null;return;}attempted.add(image.id);try{renewed.value[image.id]=(await treeholeRequest('media.url',{postId:props.postId,imageId:image.id})).image?.url||null;}catch{renewed.value[image.id]=null;}}
function url(image:TreeholeImage){return image.id in renewed.value?renewed.value[image.id]:image.url;}
function scrolled(event:Event){const el=event.target as HTMLElement;page.value=Math.min(props.images.length-1,Math.round(el.scrollLeft/el.clientWidth));}
</script>
<template>
 <div v-if="images.length" class="th-media" :class="{'is-full':full}"><div class="th-images" :class="{single:images.length===1,two:images.length===2||images.length===4,carousel:full&&images.length>1}" @scroll.passive="scrolled"><button v-for="(image,index) in images.slice(0,9)" :key="image.id" type="button" :style="images.length===1?singleStyle:undefined" :aria-label="(full?'查看图片 ':'查看配图 ')+(index+1)+'，共 '+images.length+' 张'" @click="$emit('open',index)"><img v-if="url(image)" :src="url(image)!" :width="image.width" :height="image.height" :alt="'帖子配图 '+(index+1)" loading="lazy" referrerpolicy="no-referrer" @error="retry(image)"/><span v-else class="th-image-missing"><ImageOff :size="22"/>点开重试</span><span v-if="!full&&images.length===1&&ratio<.6" class="th-long-image">长图</span></button></div><div v-if="full&&images.length>1" class="th-media-pagination"><span>左右滑动查看</span><strong>{{page+1}} / {{images.length}}</strong></div></div>
</template>
<style scoped>
.th-media{margin:9px 0 12px;min-width:0}.th-images{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px}.th-images button{position:relative;aspect-ratio:1;border-radius:9px;background:var(--color-bg);overflow:hidden;min-width:0;padding:0;display:block;min-height:0}.th-images img{display:block;width:100%;height:100%;object-fit:cover;object-position:center}.th-images.single{display:block}.th-images.single button{width:100%}.th-images.single img{object-position:top}.th-images.two{grid-template-columns:repeat(2,minmax(0,1fr));max-width:360px}.is-full .single button{border-radius:3px}.is-full .single img{object-fit:contain}
.th-images.carousel{display:flex;gap:0;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;max-width:none}.carousel button{flex:0 0 100%;scroll-snap-align:center;aspect-ratio:4/3;border-radius:3px}.carousel img{object-fit:contain}.th-image-count{position:absolute;inset:0;display:grid;place-items:center;background:#0007;color:white;font-size:26px;font-weight:600}.th-long-image{position:absolute;right:6px;bottom:6px;color:white;background:#0008;border-radius:3px;padding:2px 5px;font-size:11px}.th-image-missing{position:absolute;inset:0;display:flex;flex-direction:column;gap:7px;align-items:center;justify-content:center;color:var(--color-muted);font-size:11px}.th-media-pagination{display:flex;justify-content:space-between;margin-top:8px;font-size:11px;color:var(--color-muted)}.th-media-pagination strong{font-weight:500;font-variant-numeric:tabular-nums}
</style>
