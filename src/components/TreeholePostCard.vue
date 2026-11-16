<script setup lang="ts">
import {ref,computed} from 'vue';
import {ThumbsUp,MessageCircle,MoreHorizontal,LockKeyhole} from 'lucide-vue-next';
import TreeholeBuddy from './TreeholeBuddy.vue';
import TreeholePoll from './TreeholePoll.vue';
import TreeholeResponses from './TreeholeResponses.vue';
import TreeholeAvatar from './TreeholeAvatar.vue';
import TreeholeImages from './TreeholeImages.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import {treeholeCategoryName,treeholeInterestName} from '../domain/treeholeCategories';
import type {TreeholePost,TreeholeResponseKind} from '../services/treehole';
const props=withDefaults(defineProps<{post:TreeholePost;full?:boolean;busy?:boolean;reacting?:boolean;responsesEnabled?:boolean;joyEnabled?:boolean;responding?:boolean;buddiesEnabled?:boolean;buddyPending?:boolean;pollsEnabled?:boolean;voting?:boolean}>(),{full:false,busy:false,reacting:false});
const emit=defineEmits<{buddyJoin:[enabled:boolean];buddyClose:[closed:boolean];buddyMembers:[];vote:[optionId:string|null];open:[];discussion:[];react:[kind:'like'|'save'];menu:[];image:[index:number];category:[id:string];interest:[id:string];author:[id:string];response:[kind:TreeholeResponseKind]}>();
const pressed=ref(false);
const displayBody=computed(()=>props.post.poll&&props.post.body==='[投票] '+props.post.poll.question?'':props.post.body);
let pointer:{x:number;y:number;at:number;moved:boolean}|undefined;
function down(event:PointerEvent){if(props.full||props.busy)return;pointer={x:event.clientX,y:event.clientY,at:performance.now(),moved:false};pressed.value=!(event.target as Element).closest('button');}
function move(event:PointerEvent){if(pointer&&Math.hypot(event.clientX-pointer.x,event.clientY-pointer.y)>8){pointer.moved=true;pressed.value=false;}}
function capture(event:MouseEvent){
 pressed.value=false;
 if(!props.full&&event.detail!==0&&(pointer?.moved||pointer&&performance.now()-pointer.at>600||window.getSelection()?.toString())){event.preventDefault();event.stopPropagation();}
 pointer=undefined;
}
function openCard(event:MouseEvent){if(!props.full&&!props.busy&&!(event.target as Element).closest('button,a,input,textarea,select'))emit('open');}
</script>
<template>
 <article class="th-post-card" :class="[full?'th-detail':'th-post',{'is-pressed':pressed}]" :data-post-id="post.id" @pointerdown="down" @pointermove="move" @pointerup="pressed=false" @pointercancel="pointer&&(pointer.moved=true);pressed=false" @click.capture="capture" @click="openCard">
  <header><button v-if="post.author.id&&!post.anonymous" class="th-author-avatar" :aria-label="'查看 '+post.author.name+' 的主页'" :disabled="busy" @click="$emit('author',post.author.id)"><TreeholeAvatar :name="post.author.name" :url="post.author.avatar?.url" :size="full?42:36"/></button><TreeholeAvatar v-else :name="post.author.name" :url="post.author.avatar?.url" :anonymous="post.anonymous" :size="full?42:36"/><div class="th-post-byline"><button v-if="post.author.id&&!post.anonymous" class="th-author-name" :disabled="busy" @click="$emit('author',post.author.id)">{{post.author.name}}</button><strong v-else>{{post.author.name}}</strong><span v-if="post.author.mine" class="th-owner">我</span><small>{{treeholeTimestamp(post.createdAt)}}<span v-if="post.anonymous"> · 匿名发布</span></small></div><button class="th-category-tag" :disabled="busy" @click="post.interest?$emit('interest',post.interest):$emit('category',post.category||'daily')"><span>#</span>{{post.interest?'兴趣 · '+treeholeInterestName(post.interest):treeholeCategoryName(post.category)}}</button><button class="th-post-menu" aria-label="帖子操作" :disabled="busy" @click="$emit('menu')"><MoreHorizontal :size="21"/></button></header>
  <div v-if="full" class="th-full-body"><h2 v-if="post.title">{{post.title}}</h2><p v-if="displayBody">{{displayBody}}</p></div>
  <button v-else class="th-post-body" :disabled="busy" @click="$emit('open')"><h2 v-if="post.title">{{post.title}}</h2><span v-if="displayBody">{{displayBody}}</span></button>
  <TreeholeBuddy v-if="post.buddy" :buddy="post.buddy" :mine="post.author.mine" :locked="post.locked" :disabled="busy||!buddiesEnabled" :pending="buddyPending" @join="$emit('buddyJoin',$event)" @close="$emit('buddyClose',$event)" @members="$emit('buddyMembers')"/>
  <TreeholePoll v-if="post.poll" :poll="post.poll" :locked="post.locked" :disabled="busy||!pollsEnabled" :pending="voting" @vote="$emit('vote',$event)"/>
  <TreeholeImages :images="post.images||[]" :post-id="post.id" :full="full" @open="$emit('image',$event)"/>
  <button v-if="!full&&(post.newReplyCount||0)>0" class="th-new-replies" :disabled="busy" @click="$emit('discussion')">{{post.newReplyCount}} 条新回复 · 接着聊 <MessageCircle :size="13"/></button>
  <div class="th-post-interactions">
  <TreeholeResponses v-if="responsesEnabled" :post="post" :joy-enabled="joyEnabled" :disabled="busy||responding" @choose="$emit('response',$event)"/>
  <footer class="th-post-actions"><span class="th-action-spacer"/><span v-if="post.locked" class="th-locked-tag" aria-label="已暂停回复"><LockKeyhole :size="13"/></span><template v-if="!full"><button :aria-label="'查看评论，共 '+post.commentCount+' 条'" :disabled="busy" @click="$emit('discussion')"><MessageCircle :size="19"/><span>{{post.commentCount||'评论'}}</span></button><button :aria-label="post.liked?'取消点赞':'点赞'" :aria-pressed="post.liked" :disabled="busy||reacting" @click="$emit('react','like')"><ThumbsUp :size="19" :fill="post.liked?'currentColor':'none'"/><span>{{post.likeCount||'赞'}}</span></button></template></footer>
  </div>
 </article>
</template>
<style scoped>
.th-post-card{padding:16px 18px 9px;background:var(--color-surface);border-bottom:1px solid var(--color-divider);margin:0 -18px;transition:background-color 100ms ease;overflow-wrap:anywhere}
.th-post{cursor:pointer;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none;touch-action:pan-y pinch-zoom}.th-post.is-pressed{background:var(--color-highlight)}
header{display:flex;align-items:center;gap:8px;min-height:44px}.th-author-avatar{padding:0;min-width:36px;min-height:44px;display:grid;place-items:center;flex-shrink:0}.th-author-name{font-size:14px;font-weight:600;color:var(--color-text);padding:0;text-align:left;line-height:1.4;min-height:24px}.th-post-byline{flex:1;min-width:0;line-height:1.4}.th-post-byline strong{font-size:14px;font-weight:600}.th-owner{padding:1px 4px;border-radius:4px;background:var(--color-tint);color:var(--color-primary);font-size:10px;margin-left:4px}.th-post-byline small{display:block;font-size:12px;color:var(--color-muted);margin-top:1px}.th-post-menu{width:36px;min-height:44px;display:grid;place-items:center;color:var(--color-muted);margin-right:-8px;flex-shrink:0}
.th-category-tag{display:flex;align-items:center;gap:4px;min-height:44px;max-width:94px;flex-shrink:0;padding:0;font-size:11px;color:var(--color-muted);line-height:1.5;text-align:right}.th-category-tag>span{color:var(--color-primary);font-weight:600}
.th-post-body{width:100%;text-align:left;padding:7px 0 4px;font-size:16px;line-height:1.65;display:block;color:var(--color-text)}.th-post-body:active{transform:none}.th-post-body h2,.th-full-body h2{font-size:18px;font-weight:700;line-height:1.5;margin:0 0 4px;letter-spacing:-.2px;overflow-wrap:anywhere}.th-post-body h2,.th-post-body>span{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;white-space:pre-wrap;overflow-wrap:anywhere}.th-post-body h2{-webkit-line-clamp:2}.th-post-body>span{color:var(--color-text)}
.th-full-body{font-size:17px;line-height:1.8;overflow-wrap:anywhere;padding:12px 0 5px;user-select:text}.th-full-body p{white-space:pre-wrap;margin:0}.th-full-body h2{font-size:22px;line-height:1.45;margin-bottom:10px;letter-spacing:-.3px}.th-detail{padding-top:16px;padding-bottom:9px;cursor:default}.th-detail .th-author-name,.th-detail .th-post-byline strong{font-size:15px}
.th-post-interactions{display:flex;align-items:center;gap:4px;flex-wrap:wrap}.th-post-interactions :deep(.th-responses){flex:1}.th-post-actions{display:flex;align-items:center;gap:2px;color:var(--color-muted);margin:0 0 0 auto;min-height:44px}.th-post-actions span{margin:0}.th-action-spacer{width:6px;height:44px;flex-shrink:0}.th-post-actions button{min-height:44px;min-width:44px;display:inline-flex;align-items:center;justify-content:center;gap:4px;font-size:12px;padding:0 4px;font-variant-numeric:tabular-nums}.th-post-actions button[aria-pressed=true]{color:var(--color-primary)}.th-locked-tag{display:flex;align-items:center}.th-detail .th-post-actions:empty{display:none}
.th-new-replies{display:flex;align-items:center;gap:7px;font-size:12px;color:var(--color-primary);min-height:44px;padding:0}.th-post :deep(.th-media){margin:7px 0 4px}
button{transition:color 120ms ease,background 100ms ease}button:active>svg{transform:scale(.9)}button[aria-pressed=true]>svg{animation:th-react 170ms ease-out}button:focus{outline:none}button:focus-visible{outline:2px solid var(--color-primary);outline-offset:2px;border-radius:8px}
@keyframes th-react{50%{transform:scale(1.18)}}@media(prefers-reduced-motion:reduce){*,*::before{animation:none!important;transition:none!important}}
</style>
