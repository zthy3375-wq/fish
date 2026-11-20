<script setup lang="ts">
import OfficialBadges from './honors/OfficialBadges.vue';
import {computed} from 'vue';
import {ThumbsUp,MoreHorizontal,ChevronDown,ChevronUp} from 'lucide-vue-next';
import TreeholeImages from './TreeholeImages.vue';
import TreeholeAvatar from './TreeholeAvatar.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import type {TreeholeComment} from '../services/treehole';
const props=defineProps<{comment:TreeholeComment;busy:boolean;locked:boolean;expanded?:boolean;more?:boolean;loading?:boolean;pendingLikes?:Record<string,boolean>;accepted?:boolean;canAccept?:boolean}>();
defineEmits<{image:[comment:TreeholeComment,index:number];reply:[comment:TreeholeComment];like:[comment:TreeholeComment];menu:[comment:TreeholeComment];accept:[comment:TreeholeComment];expand:[];collapse:[]}>();
const liveReplies=computed(()=>props.comment.replies?.filter(reply=>!reply.deleted)??[]);
const shown=computed(()=>props.expanded?liveReplies.value:liveReplies.value.slice(0,2));
function replyName(child:TreeholeComment){
 if(child.replyTo===props.comment.id)return props.comment.deleted?'':props.comment.author.name;
 const parent=props.comment.replies?.find(reply=>reply.id===child.replyTo);
 return parent?.deleted?'':parent?.author.name||'同学';
}
function replyLabel(child:TreeholeComment){
 const name=replyName(child);
 return [child.isOriginalPoster?'楼主':'',name?'回复 '+name:''].filter(Boolean).join(' · ');
}
</script>
<template>
 <article class="th-comment">
  <TreeholeAvatar v-if="!comment.deleted" :name="comment.author.name" :url="comment.author.avatar?.url" :anonymous="comment.author.anonymous" :size="36"/>
  <div class="th-comment-content">
   <template v-if="!comment.deleted">
    <header>
     <div class="honor-byline">
      <strong class="honor-name" :title="comment.author.name">{{comment.author.name}}</strong>
      <OfficialBadges v-if="!comment.author.anonymous&&comment.author.badges&&(comment.author.badges.official||comment.author.badges.worn||comment.author.badges.collection)" :collection="comment.author.badges.collection" :items="[comment.author.badges.official,comment.author.badges.worn]"/>
     </div>
     <button class="th-comment-like" :aria-label="comment.liked?'取消评论点赞':'点赞评论'" :aria-pressed="!!comment.liked" :disabled="busy||pendingLikes?.[comment.id]" @click="$emit('like',comment)">
      <ThumbsUp :size="17" :fill="comment.liked?'currentColor':'none'"/>{{comment.likeCount||''}}
     </button>
     <button class="th-comment-menu" aria-label="评论操作" :disabled="busy" @click="$emit('menu',comment)"><MoreHorizontal :size="17"/></button>
    </header>
    <p v-if="comment.body!=='[图片]'||!comment.images?.length" class="th-comment-body">{{comment.body}}</p>
    <TreeholeImages :images="comment.images||[]" :post-id="comment.postId" @open="$emit('image',comment,$event)"/>
    <div class="th-comment-meta">
     <small>{{treeholeTimestamp(comment.createdAt)}}<span v-if="comment.isOriginalPoster"> · 楼主</span></small>
     <button v-if="!locked" class="th-reply" :disabled="busy" @click="$emit('reply',comment)">回复</button>
     <button v-if="canAccept&&!comment.deleted&&!comment.author.mine&&!comment.author.anonymous"
       class="th-reply" type="button" :aria-pressed="!!accepted" :disabled="busy" @click="$emit('accept',comment)">{{accepted?'撤销采纳':'采纳'}}</button>
     <span v-if="accepted" class="muted">已采纳</span>
    </div>
   </template>
   <div v-if="liveReplies.length||(comment.replyCount||0)>0" class="th-replies">
    <div v-for="child in shown" :key="child.id" class="th-nested-reply">
     <div class="th-nested-byline">
      <div class="honor-byline">
       <strong class="honor-name" :title="child.author.name">{{child.author.name}}</strong>
       <OfficialBadges v-if="!child.author.anonymous&&child.author.badges&&(child.author.badges.official||child.author.badges.worn||child.author.badges.collection)" :collection="child.author.badges.collection" :items="[child.author.badges.official,child.author.badges.worn]"/>
      </div>
      <span class="th-reply-quote">{{replyLabel(child)}}</span>
     </div>
     <button class="th-reply-text" :class="{'is-preview':!expanded}" :disabled="busy||locked" @click="$emit('reply',child)">
      <span class="th-nested-body">{{child.body==='[图片]'&&child.images?.length?'':child.body}}</span>
     </button>
     <TreeholeImages :images="child.images||[]" :post-id="child.postId" @open="$emit('image',child,$event)"/>
     <div v-if="expanded" class="th-reply-meta">
      <small>{{treeholeTimestamp(child.createdAt)}}</small>
      <button :aria-label="child.liked?'取消评论点赞':'点赞评论'" :aria-pressed="!!child.liked" :disabled="busy||pendingLikes?.[child.id]" @click="$emit('like',child)">
       <ThumbsUp :size="13" :fill="child.liked?'currentColor':'none'"/>{{child.likeCount||''}}
      </button>
      <button aria-label="回复操作" :disabled="busy" @click="$emit('menu',child)"><MoreHorizontal :size="16"/></button>
     </div>
    </div>
    <button v-if="!expanded||more" class="th-expand-replies" :disabled="busy||loading" @click="$emit('expand')">
     {{loading?'正在加载…':expanded?'加载更多回复':'全部 '+comment.replyCount+' 条回复'}}<ChevronDown :size="15"/>
    </button>
    <button v-if="expanded" class="th-collapse-replies" :disabled="busy||loading" @click="$emit('collapse')">收起回复<ChevronUp :size="14"/></button>
   </div>
  </div>
 </article>
</template>
<style scoped>
.th-comment{display:flex;align-items:flex-start;gap:10px;padding:16px 0;border-bottom:1px solid var(--color-divider)}.th-comment:last-child{border:0}.th-comment-content{flex:1;min-width:0}header{display:flex;align-items:flex-start;gap:5px}header>div{flex:1;min-width:0}strong{font-weight:600;font-size:14px;overflow-wrap:anywhere}em{font-style:normal;font-size:10px;padding:1px 4px;margin-left:5px;background:var(--color-tint);color:var(--color-primary);border-radius:3px;white-space:nowrap}small{font-size:max(12px,.75rem);color:var(--color-muted);display:block;margin-top:2px}.th-comment-like,.th-comment-menu{display:flex;align-items:center;justify-content:center;gap:4px;min-width:44px;min-height:44px;color:var(--color-muted);font-size:12px}.th-comment-menu{width:44px;margin-right:-8px}button[aria-pressed=true]{color:var(--color-primary)}.th-comment-body{font-size:16px;line-height:1.65;white-space:pre-wrap;overflow-wrap:anywhere;margin:4px 0 0}.th-reply{min-height:44px;color:var(--color-muted);font-size:12px;padding:0 6px 0 0}.th-replies{background:var(--color-bg);border-radius:8px;padding:5px 10px 0;margin-top:0}.th-nested-reply{padding:3px 0 5px}.th-reply-text{text-align:left;font-size:14px;line-height:1.75;overflow-wrap:anywhere;white-space:pre-wrap;width:100%;min-height:44px;padding:4px 0}.th-reply-text strong{color:#3b6689;font-size:14px;font-weight:500}.th-reply-quote{font-size:13px;color:var(--color-muted)}.th-reply-meta{display:flex;align-items:center;gap:9px;color:var(--color-muted);min-height:36px}.th-reply-meta small{flex:1;margin:0;font-size:max(11px,.6875rem)}.th-reply-meta button{display:flex;align-items:center;gap:3px;min-height:44px;min-width:44px;font-size:12px;padding:0 3px}.th-expand-replies,.th-collapse-replies{display:flex;gap:5px;align-items:center;justify-content:center;width:100%;min-height:44px;color:var(--color-muted);font-size:12px;border-top:1px solid var(--color-divider)}.th-collapse-replies{font-size:11px;min-height:44px}
.th-reply-text.is-preview .th-nested-body{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}.th-nested-reply:has(.is-preview){padding:0}
.th-comment-content :deep(.th-images){max-width:270px;margin:8px 0}.th-comment-content :deep(.th-images.single){max-width:180px}.th-comment-content :deep(.th-images.single button){max-height:180px}

.th-comment{padding:20px 0;gap:12px}.th-comment-content header{align-items:center;min-height:36px}.th-comment-content header>div{padding-top:3px}
.th-comment-content .th-comment-body{margin-top:7px;line-height:1.8}.th-comment-meta{display:flex;align-items:center;justify-content:space-between;gap:8px;min-height:40px}.th-comment-meta small{margin:0;font-size:11px}.th-comment-meta .th-reply{color:var(--color-primary);min-height:44px;padding-inline:10px;margin-right:-10px}
.th-comment-content .th-replies{margin-top:2px;padding:4px 12px;border-left:1px solid var(--color-border);background:var(--color-highlight);border-radius:0 10px 10px 0}
.th-nested-byline{display:flex;align-items:baseline;flex-wrap:wrap;gap:4px 8px;margin-bottom:3px}.th-nested-byline strong{font-size:13px;color:var(--color-text);font-weight:600}.th-nested-byline .th-reply-quote{font-size:11px;line-height:1.6}.th-nested-body{display:block;font-size:14px;line-height:1.8;color:var(--color-text)}
.th-reply-text{padding-block:10px;white-space:normal}.th-nested-body{white-space:pre-wrap}.th-nested-reply+.th-nested-reply{border-top:1px solid var(--color-divider)}
.th-reply-meta{padding-bottom:4px}.th-expand-replies,.th-collapse-replies{font-size:12px;color:var(--color-primary)}
.th-nested-byline{padding-top:8px}.th-nested-reply .th-reply-text{padding:0 0 4px;min-height:28px}.th-nested-byline .honor-byline{min-width:0}
</style>
