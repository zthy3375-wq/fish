<script setup lang="ts">
import {onMounted,onUnmounted,ref} from 'vue';
import {discover} from '../services/hiddenDiscovery';
defineEmits<{back:[]}>();
const entries=[
 ['1.3.0','校园社区上线，支持发帖、评论和私信。在「我的」可以查看荣誉收藏，也可以直接加入 QQ 交流群。'],
 ['1.3.0-test.30','在「我的」和社区主页翻看荣誉展柜，点开徽章可以看看它的来历。'],
 ['1.3.0-test.29','昵称旁的身份标识变小了。校园各处多了几段可以收入收藏馆的小插曲。'],
 ['1.3.0-test.28','在「我的」进入荣誉殿堂，可以分类翻看全局成就，也可以挑出喜欢的收藏。'],
 ['1.3.0-test.26','社区加入官方身份、荣誉称号和成就展示。'],
 ['1.2.4','学校课程可以按周调整时间和地点，支持确认冲突和恢复原安排。'],
 ['1.2.1','改善学习通作业读取与单课程刷新，修复部分旧接水记录影响扫码的问题。'],
 ['1.2','加入桌面课表小组件和洗澡码，校园地图改为东、西校区平面图。'],
 ['1.1','调整课程管理入口，作业、考试更好找了。首页迎来了校园小鱼。'],
 ['1.0.1','可以在应用内查看新版说明，下载并校验安装包。'],
 ['1.0.0','邯院通有了自己的名字和图标。']
];
const pane=ref<HTMLElement>(),atEnd=ref(false);
function check(){const el=pane.value;if(el)atEnd.value=el.scrollTop+el.clientHeight>=el.scrollHeight-3;}
let resize:ResizeObserver|undefined;
onMounted(()=>{check();if(pane.value){resize=new ResizeObserver(check);resize.observe(pane.value);}});
onUnmounted(()=>resize?.disconnect());
</script>
<template><div class="release-history"><button class="text-button" @click="$emit('back')">返回关于</button><h2>更新日志</h2><div ref="pane" class="release-pages" tabindex="0" aria-label="版本记录" @scroll.passive="check"><section v-for="[version,note] in entries" :key="version"><h3>{{version}}</h3><p>{{note}}</p></section><button class="colophon" :disabled="!atEnd" @click="atEnd&&discover('lastline')">— 小金鱼，记于邯院</button></div></div></template>
<style scoped>.release-pages{max-height:48dvh;overflow:auto;overscroll-behavior:contain}.release-pages section{border-bottom:1px solid var(--color-divider);padding:12px 2px}.release-pages h3{margin:0;font-size:15px}.release-pages p{margin:5px 0;line-height:1.65}.colophon{background:none;border:0;color:var(--color-muted);min-height:44px;font-size:12px}</style>
