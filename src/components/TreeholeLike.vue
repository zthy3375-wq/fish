<script setup lang="ts">
import {ref} from 'vue';
import {Heart} from 'lucide-vue-next';

const props = withDefaults(defineProps<{liked:boolean; count:number; disabled?:boolean; detail?:boolean}>(), {disabled:false, detail:false});
const emit = defineEmits<{toggle:[]}>();
const animating = ref(false);
function toggle() {
  animating.value = !props.liked;
  emit('toggle');
}
</script>

<template>
  <button type="button" class="th-like" :class="{'is-activating': animating && liked}"
    :aria-label="liked ? '取消点赞' : '点赞'" :aria-pressed="liked" :disabled="disabled" @click="toggle">
    <span class="th-like-mark" aria-hidden="true" @animationend.self="animating=false">
      <Heart :size="detail ? 21 : 19" :fill="liked ? 'currentColor' : 'none'"/>
    </span>
    <span>{{count || (detail ? '点赞' : '赞')}}</span>
  </button>
</template>

<style scoped>
button.th-like[aria-pressed=true]{color:var(--color-primary-strong)}
.th-like-mark{position:relative;display:inline-grid;place-items:center;flex:none}
.th-like-mark svg{display:block}
@media(prefers-reduced-motion:no-preference){
  .is-activating .th-like-mark{animation:fish-heart-beat 320ms cubic-bezier(.2,.75,.25,1)}
  .is-activating .th-like-mark::after{content:'';position:absolute;inset:-2px;border:1.5px solid currentColor;border-radius:50%;pointer-events:none;animation:fish-heart-ring 320ms ease-out both}
}
@keyframes fish-heart-beat{0%{transform:scale(.82)}45%{transform:scale(1.24)}75%{transform:scale(.97)}}
@keyframes fish-heart-ring{from{transform:scale(.65);opacity:.55}to{transform:scale(1.54);opacity:0}}
</style>
