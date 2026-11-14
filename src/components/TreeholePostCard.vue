<script setup lang="ts">
import {computed} from 'vue';
import {Heart,MessageCircle,Bookmark,MoreHorizontal,LockKeyhole} from 'lucide-vue-next';
import TreeholeAvatar from './TreeholeAvatar.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import type {TreeholePost} from '../services/treehole';
const props=withDefaults(defineProps<{post:TreeholePost;full?:boolean;busy?:boolean}>(),{full:false,busy:false});
defineEmits<{open:[];react:[kind:'like'|'save'];menu:[]}>();
const long=computed(()=>props.post.body.length>160||props.post.body.split('\n').length>5);
</script>
<template>
 <article class="th-post-card" :class="full?'th-detail':'th-post'">
  <header><TreeholeAvatar :name="post.author.name" :anonymous="post.anonymous"/><div class="th-post-byline"><strong>{{post.author.name}}</strong><div class="th-post-meta"><time :datetime="post.createdAt">{{treeholeTimestamp(post.createdAt)}}</time><span v-if="post.author.mine" class="th-owner">我</span><span v-if="post.locked"><LockKeyhole :size="11"/> 暂停回复</span></div></div><button class="th-post-menu" aria-label="帖子操作" :disabled="busy" @click="$emit('menu')"><MoreHorizontal :size="21"/></button></header>
  <p v-if="full" class="th-full-body">{{post.body}}</p>
  <button v-else class="th-post-body" :disabled="busy" @click="$emit('open')"><span>{{post.body}}</span><small v-if="long">展开全文</small></button>
  <footer class="th-post-actions">
   <button :aria-label="post.liked?'取消点赞':'点赞'" :aria-pressed="post.liked" :disabled="busy" @click="$emit('react','like')"><Heart :size="20" :fill="post.liked?'currentColor':'none'"/><span>{{post.likeCount||'赞'}}</span></button>
   <button :aria-label="'查看评论，共 '+post.commentCount+' 条'" :disabled="busy" @click="$emit('open')"><MessageCircle :size="20"/><span>{{post.commentCount||'评论'}}</span></button>
   <button :aria-label="post.saved?'取消收藏':'收藏'" :aria-pressed="post.saved" :disabled="busy" @click="$emit('react','save')"><Bookmark :size="19" :fill="post.saved?'currentColor':'none'"/><span>{{post.saved?'已收藏':'收藏'}}</span></button>
  </footer>
 </article>
</template>
<style scoped>
.th-post-card{padding:18px 18px 5px;background:var(--color-surface);border:1px solid color-mix(in srgb,var(--color-border) 65%,transparent);border-radius:22px;box-shadow:0 3px 12px #33265303;margin:12px 0}.th-post-card header{display:flex;align-items:center;gap:11px}.th-post-byline{flex:1;min-width:0}.th-post-byline strong{font-size:14px;line-height:1.5;font-weight:650;overflow-wrap:anywhere}.th-post-meta{display:flex;align-items:center;flex-wrap:wrap;gap:7px;margin-top:4px;color:var(--color-muted);font-size:11px}.th-owner{padding:0 5px;border-radius:4px;background:var(--color-tint);color:var(--color-primary)}.th-post-menu{width:36px;min-height:44px;display:grid;place-items:center;color:var(--color-muted);margin-right:-8px}.th-post-body{width:100%;text-align:left;padding:16px 0 17px;font-size:16px;line-height:1.8;display:block}.th-post-body>span{display:-webkit-box;-webkit-line-clamp:6;-webkit-box-orient:vertical;overflow:hidden;white-space:pre-wrap;overflow-wrap:anywhere}.th-post-body small{display:block;font-size:12px;color:var(--color-primary);margin-top:7px}.th-full-body{font-size:16px;line-height:1.9;white-space:pre-wrap;overflow-wrap:anywhere;padding:21px 0 23px}.th-post-actions{display:flex;align-items:center;justify-content:space-between;border-top:1px solid var(--color-divider);color:var(--color-muted)}.th-post-actions button{min-height:46px;min-width:64px;display:inline-flex;align-items:center;gap:7px;font-size:12px;padding:0 4px}.th-post-actions button:last-child{justify-content:flex-end}.th-post-actions button[aria-pressed=true]{color:var(--color-primary)}.th-detail{box-shadow:none}
</style>
