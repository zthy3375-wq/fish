<script setup lang="ts">
import {ref,computed,onMounted,onUnmounted} from 'vue';
import {MapPin,Clock3,Users} from 'lucide-vue-next';
import type {TreeholeBuddy} from '../services/treehole';
import {buddyTimeLabel} from '../domain/treeholeBuddies';
const props=defineProps<{buddy:TreeholeBuddy;mine:boolean;locked?:boolean;disabled?:boolean;pending?:boolean}>();
defineEmits<{join:[enabled:boolean];close:[closed:boolean];members:[]}>();
const now=ref(Date.now());let timer:ReturnType<typeof setInterval>|undefined;
onMounted(()=>{timer=setInterval(()=>now.value=Date.now(),15000);});onUnmounted(()=>clearInterval(timer));
const expired=computed(()=>props.buddy.expired||Date.parse(props.buddy.startsAt)<=now.value);
const status=computed(()=>props.buddy.closed?'已结束招募':expired.value?'活动已开始':props.locked?'暂缓招募':props.buddy.count>=props.buddy.capacity?'已招满':'正在找搭子');
const blocked=computed(()=>props.buddy.closed||expired.value||props.locked||props.buddy.count>=props.buddy.capacity);
</script>
<template><section class="th-buddy" aria-label="搭子招募"><header><strong><Users :size="16"/>{{status}}</strong><span>{{buddy.count}} / {{buddy.capacity}} 人已报名</span></header><p><Clock3 :size="15"/>{{buddyTimeLabel(buddy.startsAt)}}</p><p><MapPin :size="15"/><span>{{buddy.location}}</span></p><div class="th-buddy-actions"><template v-if="mine"><button :disabled="disabled||pending" @click="$emit('members')">查看报名</button><button :disabled="disabled||pending||buddy.closed&&(expired||locked)" @click="$emit('close',!buddy.closed)">{{pending?'处理中…':buddy.closed?'重新开放':'结束招募'}}</button></template><button v-else class="th-buddy-join" :class="{joined:buddy.joined}" :disabled="disabled||pending||!buddy.joined&&blocked" @click="$emit('join',!buddy.joined)">{{pending?'处理中…':buddy.joined?'已报名 · 退出':blocked?status:'一起去 · 报名'}}</button></div><small>{{mine?'名额不含发起人；报名名单仅你可见。':buddy.joined?'已加入，可在「我报名的」回来继续聊。':'报名后昵称和头像仅发起人可见，可随时退出。'}}</small><small v-if="disabled">报名服务暂不可用，请稍后再试。</small></section></template>
<style scoped>
.th-buddy{padding:14px;border:1px solid var(--color-divider);background:var(--color-bg);border-radius:12px;margin:12px 0}header{display:flex;align-items:center;justify-content:space-between;gap:8px}strong{display:flex;align-items:center;gap:6px;font-size:13px;color:var(--color-primary)}header>span{font-size:11px;color:var(--color-muted)}p{display:flex;align-items:flex-start;gap:7px;font-size:13px;line-height:1.6;margin:10px 0;overflow-wrap:anywhere}p svg{flex-shrink:0;margin-top:3px}.th-buddy-actions{display:flex;gap:8px;margin-top:12px}button{flex:1;min-height:44px;border-radius:9px;background:var(--color-surface);font-size:13px;font-weight:600;color:var(--color-primary);transition:transform 120ms,background 120ms}.th-buddy-join{background:var(--color-primary);color:white}.th-buddy-join.joined{background:var(--color-surface);color:var(--color-primary)}button:active:not(:disabled){transform:scale(.98)}button:disabled{opacity:.55}small{display:block;color:var(--color-muted);font-size:11px;line-height:1.6;margin-top:8px}@media(prefers-reduced-motion:reduce){button{transition:none}}
</style>
