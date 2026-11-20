<script setup lang="ts">
import {ref,watch} from 'vue';
import {treeholeRequest} from '../../services/treehole';
import type {Contest} from '../../services/contests';
const props=defineProps<{contest:Contest}>();
const renewed=ref<string>(),failed=ref(false);let attempted=false;
watch(()=>props.contest.cover?.url,()=>{renewed.value=undefined;failed.value=false;attempted=false;});
async function renew(){if(attempted){failed.value=true;return;}attempted=true;try{const r=await treeholeRequest(props.contest.coverImageId?'contests.image':'media.url',props.contest.coverImageId?{contestId:props.contest.id,cover:true,imageId:props.contest.cover!.id}:{postId:props.contest.coverPostId,imageId:props.contest.cover!.id});if(r.image?.url)renewed.value=r.image.url;else failed.value=true;}catch{failed.value=true;}}
</script>
<template><img v-if="!failed" :src="renewed||contest.cover?.url||undefined" :style="{objectPosition:'50% '+(contest.coverPosition??50)+'%'}" alt="赛事封面" @error="renew"/><div v-else class="ct-cover-failed">{{contest.title}}</div></template>
<style scoped>.ct-cover-failed{display:grid;place-items:center;background:var(--color-background);color:var(--color-muted);font-size:13px}</style>
