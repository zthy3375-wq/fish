<script setup lang="ts">
import TreeholeAvatar from './TreeholeAvatar.vue';
import type {TreeholeFollow} from '../services/treehole';
defineProps<{followers?:boolean;people:TreeholeFollow[];loading:boolean;error:string;more:boolean;retryMore:boolean;disabled:boolean;pending:Record<string,boolean>}>();
defineEmits<{open:[id:string];unfollow:[id:string];follow:[id:string];load:[more:boolean];browse:[]}>();
</script>
<template>
 <section class="th-following-list" :aria-label="followers?'我的粉丝':'我关注的人'" :aria-busy="loading">
  <p class="th-following-note">{{followers?'这里是关注你的同学，名单仅你自己可见。':'关注名单仅自己可见，关注动态只展示公开帖子。'}}</p>
  <div v-for="person in people" :key="person.id" class="th-person" :data-member-id="person.id">
   <button class="th-person-identity" :disabled="disabled" :aria-label="'查看 '+person.nickname+' 的主页'" @click="$emit('open',person.id)"><TreeholeAvatar :name="person.nickname" :url="person.avatar?.url" :size="42"/><span><strong>{{person.nickname}}</strong><small>{{person.bio||'去看看 TA 的公开分享'}}</small></span></button>
   <button v-if="!followers||person.following" class="th-person-unfollow" :disabled="disabled||pending[person.id]" :aria-label="'取消关注 '+person.nickname" @click="$emit('unfollow',person.id)">{{pending[person.id]?'处理中…':followers?'互相关注':'已关注'}}</button><button v-else class="th-person-follow" :disabled="disabled||pending[person.id]" :aria-label="'回关 '+person.nickname" @click="$emit('follow',person.id)">{{pending[person.id]?'处理中…':'回关'}}</button>
  </div>
  <p v-if="loading" class="th-following-state" role="status">正在加载关注名单…</p>
  <div v-else-if="error" class="th-following-state" role="alert"><p>{{error}}，已有名单已保留。</p><button :disabled="disabled" @click="$emit('load',retryMore)">重试加载</button></div>
  <div v-else-if="!people.length" class="th-following-state"><strong>{{followers?'还没有粉丝':'还没有关注同学'}}</strong><p>{{followers?'继续分享日常，让同学认识你。':'遇到喜欢的分享，点开头像，在主页关注 TA。'}}</p><button :disabled="disabled" @click="$emit('browse')">去广场看看</button></div>
  <button v-else-if="more" class="th-following-more" :disabled="disabled" @click="$emit('load',true)">加载更多同学</button>
 </section>
</template>
<style scoped>
.th-following-note{font-size:12px;color:var(--color-muted);line-height:1.7;padding:12px 0;margin:0}
.th-person{display:flex;align-items:center;gap:12px;border-bottom:1px solid var(--color-divider);padding:16px 0}
.th-person-identity{display:flex;align-items:center;gap:12px;min-width:0;flex:1;text-align:left;min-height:48px}.th-person-identity>span{min-width:0;display:flex;flex-direction:column;gap:5px}.th-person strong{font-size:15px;overflow-wrap:anywhere}.th-person small{font-size:12px;color:var(--color-muted);overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;line-height:1.6}
.th-person-unfollow{font-size:12px;min-width:70px;min-height:44px;border-radius:22px;background:var(--color-bg);color:var(--color-muted)}
.th-following-state{padding:40px 8px;text-align:center;font-size:14px;line-height:1.8;color:var(--color-muted)}.th-following-state strong{color:var(--color-text)}.th-following-state p{margin:8px 0}.th-following-state button,.th-following-more{min-height:44px;color:var(--color-primary);font-size:14px}.th-following-more{display:block;margin:16px auto}
.th-person-follow{font-size:12px;min-width:70px;min-height:44px;border-radius:22px;background:var(--color-tint);color:var(--color-primary)}
</style>
