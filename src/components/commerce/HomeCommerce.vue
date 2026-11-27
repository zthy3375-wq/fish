<script setup lang="ts">
import {onMounted,ref} from 'vue';
import CommerceAds from './CommerceAds.vue';
import {commerceRequest,type Ad,type Media} from '../../services/commerce';
const emit=defineEmits<{select:[shopId:string];report:[ad:Ad]}>();
const ads=ref<Ad[]>([]),media=ref<Media['media']>();
onMounted(async()=>{
 try {const r=await commerceRequest<Media&{ads:Ad[]}>('home');ads.value=r.ads;media.value=r.media;}
 catch {/* The optional home placement can be absent or turned off. */}
});
</script>
<template>
 <CommerceAds v-if="ads.length" :ads="ads" :media="media" label="校园福利广告" rotate @select="emit('select',$event.shopId)" @report="emit('report',$event)"/>
</template>
