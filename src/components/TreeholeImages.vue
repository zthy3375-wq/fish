<script setup lang="ts">
import {ref} from 'vue';
import {ImageOff} from 'lucide-vue-next';
import {treeholeRequest,type TreeholeImage} from '../services/treehole';
const props=defineProps<{images:TreeholeImage[];postId:string;full?:boolean}>();
defineEmits<{open:[index:number]}>();
const renewed=ref<Record<string,string|null>>({}),attempted=new Set<string>();
async function retry(image:TreeholeImage){if(attempted.has(image.id)){renewed.value[image.id]=null;return;}attempted.add(image.id);try{renewed.value[image.id]=(await treeholeRequest('media.url',{postId:props.postId,imageId:image.id})).image?.url||null;}catch{renewed.value[image.id]=null;}}
function url(image:TreeholeImage){return image.id in renewed.value?renewed.value[image.id]:image.url;}
</script>
<template><div v-if="images.length" class="th-images" :class="{'single':images.length===1,'two':images.length===2,'full':full}"><button v-for="(image,index) in images.slice(0,full?9:3)" :key="image.id" type="button" :aria-label="'查看图片 '+(index+1)+'，共 '+images.length+' 张'" @click="$emit('open',index)"><img v-if="url(image)" :src="url(image)!" :width="image.width" :height="image.height" :alt="'帖子配图 '+(index+1)" loading="lazy" referrerpolicy="no-referrer" @error="retry(image)"/><span v-else class="th-image-missing"><ImageOff :size="22"/>点开重试</span><b v-if="!full&&index===2&&images.length>3">+{{images.length-3}}</b></button></div></template>
<style scoped>
.th-images{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:5px;margin:12px 0 16px}.th-images button{position:relative;aspect-ratio:1;border-radius:6px;background:var(--color-bg);overflow:hidden;min-width:0}.th-images img{display:block;width:100%;height:100%;object-fit:cover}.th-images.single{grid-template-columns:minmax(0,200px)}.th-images.single button{aspect-ratio:auto;max-height:270px;min-height:100px}.th-images.single img{height:auto;max-height:270px;object-fit:cover;object-position:top}.th-images.two{grid-template-columns:repeat(2,minmax(0,1fr));max-width:320px}.th-images.full.single{grid-template-columns:1fr}.th-images.full.single button,.th-images.full.single img{max-height:500px}.th-images b{position:absolute;inset:0;display:grid;place-items:center;background:#0007;color:white;font-size:28px}.th-image-missing{display:flex;flex-direction:column;gap:7px;align-items:center;justify-content:center;min-height:100px;color:var(--color-muted);font-size:11px}
</style>
