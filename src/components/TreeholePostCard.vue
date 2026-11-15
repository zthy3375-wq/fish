<script setup lang="ts">
import {Heart,MessageCircle,Bookmark,MoreHorizontal,LockKeyhole} from 'lucide-vue-next';
import TreeholeAvatar from './TreeholeAvatar.vue';
import TreeholeImages from './TreeholeImages.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import {treeholeCategoryName} from '../domain/treeholeCategories';
import type {TreeholePost} from '../services/treehole';
withDefaults(defineProps<{post:TreeholePost;full?:boolean;busy?:boolean}>(),{full:false,busy:false});
defineEmits<{open:[];react:[kind:'like'|'save'];menu:[];image:[index:number];category:[id:string]}>();
</script>
<template>
 <article class="th-post-card" :class="full?'th-detail':'th-post'">
  <header><TreeholeAvatar :name="post.author.name" :anonymous="post.anonymous" :size="full?38:29"/><div class="th-post-byline"><strong>{{post.author.name}}</strong><span v-if="post.author.mine" class="th-owner">我</span><small v-if="full">{{treeholeTimestamp(post.createdAt)}}</small></div><button class="th-post-menu" aria-label="帖子操作" :disabled="busy" @click="$emit('menu')"><MoreHorizontal :size="21"/></button></header>
  <div v-if="full" class="th-full-body"><h2 v-if="post.title">{{post.title}}</h2><p>{{post.body}}</p></div>
  <button v-else class="th-post-body" :disabled="busy" @click="$emit('open')"><h2 v-if="post.title">{{post.title}}</h2><span>{{post.body}}</span></button>
  <TreeholeImages :images="post.images||[]" :post-id="post.id" :full="full" @open="$emit('image',$event)"/>
  <footer class="th-post-actions"><button class="th-category-tag" :disabled="busy" @click="$emit('category',post.category||'daily')">{{treeholeCategoryName(post.category)}}</button><span class="th-action-spacer"/>
   <span v-if="post.locked" class="th-locked-tag"><LockKeyhole :size="12"/></span>
   <button :aria-label="'查看评论，共 '+post.commentCount+' 条'" :disabled="busy" @click="$emit('open')"><MessageCircle :size="18"/><span>{{post.commentCount||'评论'}}</span></button>
   <button v-if="!full||post.locked" :aria-label="post.liked?'取消点赞':'点赞'" :aria-pressed="post.liked" :disabled="busy" @click="$emit('react','like')"><Heart :size="18" :fill="post.liked?'currentColor':'none'"/><span>{{post.likeCount||'赞'}}</span></button>
   <button v-if="full&&post.locked" :aria-label="post.saved?'取消收藏':'收藏'" :aria-pressed="post.saved" :disabled="busy" @click="$emit('react','save')"><Bookmark :size="18" :fill="post.saved?'currentColor':'none'"/></button>
  </footer>
 </article>
</template>
<style scoped>
.th-post-card{padding:18px 18px 8px;background:var(--color-surface);border-bottom:7px solid var(--color-bg);margin:0 -16px}.th-post-card header{display:flex;align-items:center;gap:9px}.th-post-byline{flex:1;min-width:0}.th-post-byline strong{font-size:13px;line-height:1.5;font-weight:500;color:var(--color-muted);overflow-wrap:anywhere}.th-owner{padding:1px 5px;border-radius:3px;background:var(--color-tint);color:var(--color-primary);font-size:10px;margin-left:7px}.th-post-byline small{display:block;font-size:10px;color:var(--color-muted);margin-top:4px}.th-post-menu{width:32px;min-height:36px;display:grid;place-items:center;color:var(--color-faint,var(--color-muted));margin-right:-7px}.th-post-body{width:100%;text-align:left;padding:13px 0 9px;font-size:15px;line-height:1.7;display:block;color:var(--color-text)}.th-post-body h2,.th-full-body h2{font-size:18px;font-weight:700;line-height:1.55;margin-bottom:6px;overflow-wrap:anywhere}.th-post-body>span{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;white-space:pre-wrap;overflow-wrap:anywhere}.th-full-body{font-size:17px;line-height:1.85;white-space:pre-wrap;overflow-wrap:anywhere;padding:21px 0 12px}.th-full-body h2{font-size:23px;margin-bottom:13px}.th-post-actions{display:flex;align-items:center;gap:14px;color:var(--color-muted)}.th-action-spacer{flex:1}.th-post-actions button{min-height:42px;display:inline-flex;align-items:center;gap:5px;font-size:11px;padding:0 2px}.th-post-actions .th-category-tag{min-height:26px;background:var(--color-bg);border-radius:3px;padding:3px 7px;font-size:11px}.th-post-actions button[aria-pressed=true]{color:var(--color-primary)}.th-detail{padding-bottom:12px}.th-locked-tag{display:flex}
</style>
