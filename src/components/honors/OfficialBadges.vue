<script setup lang="ts">
import {ref} from 'vue';
import {badges,honorDate,type Badge} from '../../domain/communityHonors';
defineProps<{items:(Badge|null|undefined)[]}>();
const detail=ref<Badge|null>(null),dialog=ref<HTMLDialogElement>();
function show(b:Badge){detail.value=b;dialog.value?.showModal();}
</script>
<template><span class="hyt-badges">
 <template v-for="b in items" :key="b?.code"><button v-if="b&&badges[b.code]" type="button" class="hyt-badge" :style="{background:badges[b.code].tint,color:badges[b.code].color}" @click.stop="show(b)"><component :is="badges[b.code].icon" :size="13"/>{{badges[b.code].name}}</button></template>
 <Teleport to="body"><dialog ref="dialog" class="hyt-badge-detail" @click.self="dialog?.close()" @close="detail=null"><template v-if="detail"><component :is="badges[detail.code].icon" :size="34" :color="badges[detail.code].color"/><h3>{{badges[detail.code].name}}</h3><p>{{badges[detail.code].description}}</p><p>{{badges[detail.code].method}}</p><small>获得日期 · {{honorDate(detail.at)}}</small><form method="dialog"><button>完成</button></form></template></dialog></Teleport>
</span></template>
<style scoped>
.hyt-badges{display:inline-flex;align-items:center;gap:4px;flex-wrap:wrap;vertical-align:middle}.hyt-badge{border:0;border-radius:99px;display:inline-flex;align-items:center;gap:3px;padding:3px 6px;font-size:10.5px;font-weight:650;white-space:nowrap}.hyt-badge-detail{width:min(85vw,330px);box-sizing:border-box;border:1px solid #e6e2eb;border-radius:22px;padding:24px;color:#262329;background:#fff}.hyt-badge-detail::backdrop{background:#201c284f}.hyt-badge-detail p{line-height:1.65}.hyt-badge-detail small{color:#645c67}.hyt-badge-detail button{margin-top:16px;width:100%;border:0;border-radius:12px;background:#f1edf5;color:#513a69;padding:12px}
</style>
