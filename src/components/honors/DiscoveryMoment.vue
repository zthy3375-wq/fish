<script setup lang="ts">
import {cues,moment} from '../../services/hiddenDiscovery';
import {feedback} from '../../services/achievementJournal';
import {byCode} from '../../domain/globalAchievements';
</script>
<template><Teleport to="body"><div v-if="moment" :key="moment" class="discovery-moment" :class="{still:!feedback.motion}" role="status"><component :is="byCode.get(moment)?.icon" :size="18" aria-hidden="true"/>{{cues[moment]}}<i aria-hidden="true"/></div></Teleport></template>
<style scoped>
.discovery-moment{pointer-events:none;position:fixed;z-index:9999;bottom:calc(env(safe-area-inset-bottom) + 88px);left:50%;transform:translateX(-50%);max-width:90vw;white-space:nowrap;display:flex;align-items:center;gap:8px;padding:9px 15px;border-radius:18px;background:var(--color-surface);border:1px solid var(--color-divider);color:var(--color-text);box-shadow:0 3px 14px #18162d19;font-size:13px;animation:ripple .85s ease-out both}.discovery-moment svg{color:#aa7751}.discovery-moment i{height:6px;width:6px;border:1px solid #86acae;border-radius:50%;animation:bubble .85s ease-out both}@keyframes ripple{from{opacity:0;transform:translate(-50%,4px) scale(.97)}20%,83%{opacity:1}to{opacity:0}}@keyframes bubble{to{transform:translate(1px,-5px);opacity:.2}}.still,.still i{animation:none}@media(prefers-reduced-motion:reduce){.discovery-moment,.discovery-moment i{animation:none}}
</style>
