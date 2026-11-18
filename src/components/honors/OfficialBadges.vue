<script setup lang="ts">
import {computed,nextTick,ref} from 'vue';
import {badges,honorDate,visibleBadges,type Badge} from '../../domain/communityHonors';
const props=defineProps<{items:(Badge|null|undefined)[]; full?:boolean; passive?:boolean}>();
const marks=computed(()=>visibleBadges(props.items,props.full));
const detail=ref<Badge|null>(null), dialog=ref<HTMLDialogElement>();
async function show(badge:Badge){
  detail.value=badge;
  await nextTick();
  if(dialog.value&&!dialog.value.open)dialog.value.showModal();
}
</script>
<template>
 <span v-if="marks.length" class="hyt-badges">
  <component v-for="b in marks" :key="b.code" :is="passive?'span':'button'" :type="passive?undefined:'button'" class="hyt-badge" :aria-label="badges[b.code].name" :title="badges[b.code].name" :style="{'--ink':badges[b.code].color,'--night':badges[b.code].dark}" @click="!passive&&($event.stopPropagation(),show(b))">
   <component :is="badges[b.code].icon" :size="13" :stroke-width="1.8" aria-hidden="true"/>{{badges[b.code].short}}
  </component>
  <Teleport to="body"><dialog v-if="detail" ref="dialog" class="hyt-badge-detail" :aria-label="badges[detail.code].name" @click.self="dialog?.close()" @close="!dialog?.open&&(detail=null)">
    <component :is="badges[detail.code].icon" :size="32" aria-hidden="true"/><h3>{{badges[detail.code].name}}</h3><p>{{badges[detail.code].description}}</p><p>{{badges[detail.code].method}}</p><small>获得日期 · {{honorDate(detail.at)}}</small><form method="dialog"><button>完成</button></form>
  </dialog></Teleport>
 </span>
</template>
<style>
.honor-byline{display:flex;align-items:center;gap:6px;min-width:0;max-width:100%}
.honor-byline>.honor-name{display:block;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.hyt-badges{display:inline-flex;align-items:center;flex-wrap:wrap;gap:2px 7px;vertical-align:middle;flex:none;max-width:100%}
.hyt-badges .hyt-badge{border:0;box-shadow:none;background:transparent;color:var(--ink);display:inline-flex;align-items:center;justify-content:center;gap:3px;padding:0;min-width:0;min-height:24px;line-height:1.2;font-family:inherit;font-size:11px;font-weight:500;white-space:nowrap}
.hyt-badge svg{flex:none}.hyt-badge:focus-visible{outline:2px solid currentColor;outline-offset:2px}
[data-theme=dark] .hyt-badges .hyt-badge{color:var(--night)}
.hyt-badge-detail{width:min(85vw,330px);border:1px solid var(--color-divider);border-radius:20px;padding:24px;color:var(--color-text);background:var(--color-surface)}
.hyt-badge-detail::backdrop{background:#201c284f}.hyt-badge-detail p{line-height:1.65}.hyt-badge-detail small{color:var(--color-muted)}.hyt-badge-detail button{margin-top:16px;width:100%;border:0;border-radius:12px;background:var(--color-tint);color:var(--color-text);padding:12px}
</style>
