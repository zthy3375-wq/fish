<script setup lang="ts">
import BadgeDetail from './BadgeDetail.vue';
import {computed,ref} from 'vue';
import {badges,visibleBadges,type Badge} from '../../domain/communityHonors';
const props=defineProps<{items:(Badge|null|undefined)[]; full?:boolean; passive?:boolean}>();
const marks=computed(()=>visibleBadges(props.items,props.full));
const detail=ref<InstanceType<typeof BadgeDetail>>();
</script>
<template>
 <span v-if="marks.length" class="hyt-badges">
  <component v-for="b in marks" :key="b.code" :is="passive?'span':'button'" :type="passive?undefined:'button'" class="hyt-badge" :aria-label="badges[b.code].name" :title="badges[b.code].name" :style="{'--ink':badges[b.code].color,'--night':badges[b.code].dark}" @click="!passive&&($event.stopPropagation(),detail?.show(b))">
   <component :is="badges[b.code].icon" :size="13" :stroke-width="1.8" aria-hidden="true"/>{{badges[b.code].short}}
  </component>
  <BadgeDetail v-if="!passive" ref="detail"/>
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
