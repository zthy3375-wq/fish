<script setup lang="ts">
import {computed,onMounted,shallowRef} from 'vue';
import {cachedHall,localStamps,privatePins,seenHidden} from '../../services/achievementJournal';
import type {HonorHall} from '../../domain/communityHonors';
import {featuredHonor,personalDisplay,type ShowcaseOwner} from '../../domain/honorShowcase';
import HonorShowcase from './HonorShowcase.vue';
defineEmits<{hall:[];medal:[code:string]}>();
const hall=shallowRef<HonorHall>(),owner=shallowRef<ShowcaseOwner>();
onMounted(async()=>{try{
  const cache=await cachedHall();
  if(cache.signedIn){hall.value=cache.hall;owner.value=cache.owner??cache.hall;}
}catch{/* The private device collection remains available. */}});
const display=computed(()=>personalDisplay({
  ...Object.fromEntries(Object.entries(localStamps.value).map(([k,v])=>[k,v.at])),...hall.value?.awards
},privatePins.value,owner.value?.showcase??[]));
</script>
<template><HonorShowcase personal class="collection-entry" :medals="display.medals" :pinned="display.pinned" :honor="featuredHonor(owner?.badges)??hall?.honors?.[0]" :latest="display.latest" :fresh="!!display.latest?.hidden&&display.latest.code!==seenHidden&&!localStamps[display.latest.code]?.historical" @hall="$emit('hall')" @medal="$emit('medal',$event)"/></template>
