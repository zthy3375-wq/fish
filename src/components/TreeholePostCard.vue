<script setup lang="ts">
import {ThumbsUp,MessageCircle,MoreHorizontal,LockKeyhole} from 'lucide-vue-next';
import TreeholeAvatar from './TreeholeAvatar.vue';
import TreeholeImages from './TreeholeImages.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import {treeholeCategoryName} from '../domain/treeholeCategories';
import type {TreeholePost} from '../services/treehole';
withDefaults(defineProps<{post:TreeholePost;full?:boolean;busy?:boolean;reacting?:boolean}>(),{full:false,busy:false,reacting:false});
defineEmits<{open:[];react:[kind:'like'|'save'];menu:[];image:[index:number];category:[id:string]}>();
</script>
<template>
 <article class="th-post-card" :class="full?'th-detail':'th-post'">
  <header><TreeholeAvatar :name="post.author.name" :anonymous="post.anonymous" :size="full?40:32"/><div class="th-post-byline"><strong>{{post.author.name}}</strong><span v-if="post.author.mine" class="th-owner">我</span><small v-if="full">{{treeholeTimestamp(post.createdAt)}}</small></div><button class="th-post-menu" aria-label="帖子操作" :disabled="busy" @click="$emit('menu')"><MoreHorizontal :size="21"/></button></header>
  <div v-if="full" class="th-full-body"><h2 v-if="post.title">{{post.title}}</h2><p v-if="post.body">{{post.body}}</p></div>
  <button v-else class="th-post-body" :disabled="busy" @click="$emit('open')"><h2 v-if="post.title">{{post.title}}</h2><span v-if="post.body">{{post.body}}</span></button>
  <TreeholeImages :images="post.images||[]" :post-id="post.id" :full="full" @open="$emit('image',$event)"/>
  <footer class="th-post-actions"><button class="th-category-tag" :disabled="busy" @click="$emit('category',post.category||'daily')"><span>#</span>{{treeholeCategoryName(post.category)}}</button><span class="th-action-spacer"/><span v-if="post.locked" class="th-locked-tag" aria-label="已暂停回复"><LockKeyhole :size="13"/></span><template v-if="!full"><button :aria-label="'查看评论，共 '+post.commentCount+' 条'" :disabled="busy" @click="$emit('open')"><MessageCircle :size="19"/><span>{{post.commentCount||'评论'}}</span></button><button :aria-label="post.liked?'取消点赞':'点赞'" :aria-pressed="post.liked" :disabled="busy||reacting" @click="$emit('react','like')"><ThumbsUp :size="19" :fill="post.liked?'currentColor':'none'"/><span>{{post.likeCount||'赞'}}</span></button></template></footer>
 </article>
</template>
<style scoped>
.th-post-card{padding:18px 16px 10px;background:var(--color-surface);border-bottom:7px solid var(--color-bg);margin:0 -16px}
header{display:flex;align-items:center;gap:9px;min-height:34px}.th-post-byline{flex:1;min-width:0;line-height:1.4}.th-post-byline strong{font-size:14px;font-weight:500;color:var(--color-muted);overflow-wrap:anywhere}.th-owner{padding:1px 4px;border-radius:3px;background:var(--color-tint);color:var(--color-primary);font-size:10px;margin-left:6px}.th-post-byline small{display:block;font-size:11px;color:var(--color-muted);margin-top:5px}.th-post-menu{width:36px;min-height:36px;display:grid;place-items:center;color:var(--color-faint);margin-right:-9px;flex-shrink:0}
.th-post-body{width:100%;text-align:left;padding:13px 0 8px;font-size:16px;line-height:1.65;display:block;color:var(--color-text)}.th-post-body h2,.th-full-body h2{font-size:18px;font-weight:700;line-height:1.5;margin:0 0 6px;overflow-wrap:anywhere}.th-post-body h2,.th-post-body>span{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;white-space:pre-wrap;overflow-wrap:anywhere}.th-post-body h2{-webkit-line-clamp:2}
.th-full-body{font-size:17px;line-height:1.8;overflow-wrap:anywhere;padding:22px 0 4px}.th-full-body p{white-space:pre-wrap;margin:0}.th-full-body h2{font-size:23px;margin-bottom:12px}
.th-post-actions{display:flex;align-items:center;gap:19px;color:var(--color-muted);padding-top:6px}.th-action-spacer{flex:1}.th-post-actions button{min-height:40px;display:inline-flex;align-items:center;gap:5px;font-size:12px;padding:0}.th-post-actions .th-category-tag{min-height:26px;background:var(--color-bg);border-radius:4px;padding:3px 8px;font-size:12px;gap:5px}.th-category-tag>span{color:var(--color-faint);font-weight:700}.th-post-actions button[aria-pressed=true]{color:var(--color-primary)}.th-detail{padding-top:21px;padding-bottom:18px}.th-detail .th-post-byline strong{font-size:16px;font-weight:650;color:var(--color-text)}.th-locked-tag{display:flex}
</style>
