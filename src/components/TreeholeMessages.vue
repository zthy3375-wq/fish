<script setup lang="ts">
import {ref,computed,onMounted,onActivated,onDeactivated,onUnmounted,nextTick} from 'vue';
import {MessageCircle,Send,RefreshCw,ChevronRight,ArrowDown,ShieldBan} from 'lucide-vue-next';
import TreeholeAvatar from './TreeholeAvatar.vue';
import {treeholeRequest,treeholeError,treeholeErrorCode,type TreeholeConversation,type TreeholeMessage,type TreeholeMessageDraft} from '../services/treehole';
import {treeholeTimestamp} from '../domain/treeholePresentation';
const props=defineProps<{initialMember?:string;drafts:Record<string,TreeholeMessageDraft>}>();
const emit=defineEmits<{unread:[count:number];expired:[];blocked:[];title:[name:string]}>();
const threads=ref<TreeholeConversation[]>([]),conversation=ref<TreeholeConversation|null>(null),messages=ref<TreeholeMessage[]>([]);
const inboxNext=ref<Record<string,string>|null>(null),older=ref<Record<string,string>|null>(null),loading=ref(false),loadingOlder=ref(false),sending=ref(false),error=ref(''),readError=ref(false),confirmBlock=ref(false),blocked=ref(false);
const scroller=ref<HTMLElement>(),textarea=ref<HTMLTextAreaElement>(),nearBottom=ref(true),newMessages=ref(false);
const text=ref('');let alive=true,generation=0,polling=false,ackBusy=false,ackSeq='0',timer:ReturnType<typeof setInterval>;
const canSend=computed(()=>text.value.trim().length>0&&text.value.trim().length<=1000&&!sending.value&&!blocked.value&&!loading.value);
const draft=computed(()=>conversation.value?props.drafts[conversation.value.id]:undefined);
function saveDraft(){if(!conversation.value)return;props.drafts[conversation.value.id]={body:text.value,requestId:draft.value?.requestId||crypto.randomUUID(),failed:draft.value?.failed};}
function changed(){if(draft.value?.failed){draft.value.requestId=crypto.randomUUID();draft.value.failed=false;}saveDraft();}
function fail(e:unknown){if(!alive)return;if(treeholeErrorCode(e)==='session_expired'){alive=false;emit('expired');return;}error.value=treeholeError(e);if(treeholeErrorCode(e)==='conversation_unavailable')blocked.value=true;}
async function inbox(more=false,quiet=false){
 if(loading.value||polling||more&&!inboxNext.value)return;const g=generation;if(!quiet)loading.value=true;else polling=true;error.value='';
 try{const r=await treeholeRequest('messages.inbox',more?{...inboxNext.value}:{});if(!alive||g!==generation)return;threads.value=more?[...threads.value,...(r.conversations||[]).filter(x=>!threads.value.some(y=>x.id===y.id))]:r.conversations||[];inboxNext.value=r.next||null;emit('unread',r.messageUnreadCount||0);}
 catch(e){if(g===generation)fail(e);}finally{if(g===generation){loading.value=false;polling=false;}}
}
async function acknowledge(){
 const c=conversation.value,last=messages.value.at(-1),g=generation;if(!c||!last||!nearBottom.value||document.hidden||!visibleTab||blocked.value||ackBusy||BigInt(last.seq)<=BigInt(ackSeq))return;ackBusy=true;
 try{await treeholeRequest('messages.read',{conversationId:c.id,throughSeq:last.seq});if(!alive||g!==generation)return;readError.value=false;const r=await treeholeRequest('messages.unread');if(alive&&g===generation){ackSeq=last.seq;emit('unread',r.messageUnreadCount||0);}}
 catch(e){if(alive&&g===generation){readError.value=true;if(treeholeErrorCode(e)==='session_expired'){alive=false;emit('expired');}}}finally{if(g===generation)ackBusy=false;}
}
function ordered(rows:TreeholeMessage[]){return [...new Map(rows.map(x=>[x.id,x])).values()].sort((a,b)=>BigInt(a.seq)<BigInt(b.seq)?-1:1);}
async function bottom(){await nextTick();if(scroller.value)scroller.value.scrollTop=scroller.value.scrollHeight;nearBottom.value=true;newMessages.value=false;void acknowledge();}
function scrolling(){const el=scroller.value;if(!el)return;nearBottom.value=el.scrollHeight-el.scrollTop-el.clientHeight<70;if(nearBottom.value){newMessages.value=false;if(!readError.value)void acknowledge();}}
async function history(more=false,quiet=false){
 const c=conversation.value;if(!c||loading.value||loadingOlder.value||polling||more&&!older.value||blocked.value)return;
 const g=generation,wasBottom=nearBottom.value,previousHeight=scroller.value?.scrollHeight||0,previousTop=scroller.value?.scrollTop||0;
 if(more)loadingOlder.value=true;else if(quiet)polling=true;else loading.value=true;
 if(!quiet)error.value='';
 try{
  let cursor=more?older.value:quiet&&messages.value.length?{afterSeq:messages.value.at(-1)!.seq}:{};
  do{const r=await treeholeRequest('messages.list',{conversationId:c.id,...cursor});if(!alive||g!==generation)return;
   conversation.value=r.conversation||c;const fresh=r.messages||[];messages.value=ordered([...messages.value,...fresh]);
   for(const m of fresh)if(m.mine&&m.requestId){if(draft.value?.requestId===m.requestId){delete props.drafts[c.id];text.value='';error.value='';}}
   if(more||!quiet)older.value=r.next||null;
   cursor=quiet?r.next||null:null;
  }while(cursor);
  await nextTick();if(more&&scroller.value)scroller.value.scrollTop=previousTop+scroller.value.scrollHeight-previousHeight;
  else if(wasBottom)await bottom();else newMessages.value=messages.value.at(-1)?.seq!==c.lastSeq;
 }catch(e){if(g===generation)fail(e);}finally{if(g===generation){loading.value=false;loadingOlder.value=false;polling=false;}}
}
async function openThread(id:string,member=false){
 if(loading.value||sending.value)return;saveDraft();generation++;ackBusy=false;ackSeq='0';polling=false;messages.value=[];older.value=null;error.value='';blocked.value=false;confirmBlock.value=false;nearBottom.value=true;loading.value=true;const g=generation;
 try{let c:TreeholeConversation|undefined;if(member)c=(await treeholeRequest('messages.open',{memberId:id})).conversation;else c=threads.value.find(t=>t.id===id);
  if(!alive||g!==generation||!c)return;conversation.value=c;text.value=props.drafts[c.id]?.body||'';emit('title',c.member.nickname);loading.value=false;await history();
 }catch(e){if(g===generation)fail(e);}finally{if(g===generation)loading.value=false;}
}
async function send(){
 const c=conversation.value;if(!c||!canSend.value)return;saveDraft();const snapshot={...draft.value!,body:text.value.trim()},g=generation;props.drafts[c.id]=snapshot;sending.value=true;error.value='';
 try{const r=await treeholeRequest('messages.send',{conversationId:c.id,body:snapshot.body,requestId:snapshot.requestId});if(!alive||g!==generation)return;
  if(!r.message)throw Error('invalid_response');messages.value=ordered([...messages.value,r.message]);conversation.value=r.conversation||c;if(draft.value?.requestId===snapshot.requestId){text.value='';delete props.drafts[c.id];}await bottom();textarea.value?.focus({preventScroll:true});
 }catch(e){if(alive&&g===generation){if(draft.value?.requestId===snapshot.requestId)draft.value.failed=true;fail(e);}}
 finally{if(alive&&g===generation)sending.value=false;}
}
async function block(){const c=conversation.value;if(!c||sending.value)return;loading.value=true;const g=generation;
 try{await treeholeRequest('members.block',{memberId:c.member.id});if(!alive||g!==generation)return;delete props.drafts[c.id];text.value='';messages.value=[];blocked.value=true;confirmBlock.value=false;emit('blocked');error.value='已屏蔽对方，双方私信与关注关系已隐藏。';emit('unread',(await treeholeRequest('messages.unread')).messageUnreadCount||0);}catch(e){if(g===generation)fail(e);}finally{if(g===generation)loading.value=false;}}
function back(){if(sending.value)return true;saveDraft();if(conversation.value&&!props.initialMember){generation++;conversation.value=null;messages.value=[];error.value='';blocked.value=false;loading.value=false;loadingOlder.value=false;polling=false;confirmBlock.value=false;emit('title','私信');void inbox();return true;}return false;}
let visibleTab=true,lastInboxPoll=-Infinity;
function refresh(force=false){
 if(document.hidden||!alive||!visibleTab)return;
 if(conversation.value){void history(false,true);return}
 if(inboxNext.value||!force&&Date.now()-lastInboxPoll<60000)return;
 lastInboxPoll=Date.now();void inbox(false,true);
}
function onVisibility(){if(!document.hidden)refresh(true)}
onMounted(()=>{lastInboxPoll=Date.now();if(props.initialMember)void openThread(props.initialMember,true);else void inbox();timer=setInterval(()=>refresh(),8000);document.addEventListener('visibilitychange',onVisibility);});
onDeactivated(()=>{visibleTab=false});
onActivated(()=>{if(!visibleTab){visibleTab=true;refresh(true)}});
onUnmounted(()=>{if(alive)saveDraft();alive=false;generation++;clearInterval(timer);document.removeEventListener('visibilitychange',onVisibility);});
defineExpose({back});
</script>
<template>
 <section class="th-dm" :class="{'is-chat':conversation}" aria-label="私信">
  <template v-if="!conversation">
   <div class="dm-list-heading"><span>与同学的私下交流</span><button aria-label="刷新私信" :disabled="loading" @click="inbox()"><RefreshCw :size="18"/></button></div>
   <button v-for="thread in threads" :key="thread.id" class="dm-thread" :data-conversation-id="thread.id" @click="openThread(thread.id)"><TreeholeAvatar :name="thread.member.nickname" :url="thread.member.avatar?.url" :size="44"/><span><strong>{{thread.member.nickname}}</strong><small>{{thread.lastMessage}}</small></span><span class="dm-thread-meta"><time>{{treeholeTimestamp(thread.updatedAt)}}</time><b v-if="thread.unreadCount">{{thread.unreadCount>99?'99+':thread.unreadCount}}</b></span><ChevronRight :size="15"/></button>
   <p v-if="!threads.length&&!loading&&!error" class="dm-empty"><MessageCircle :size="32"/>还没有私信<span>在同学的公开主页点“发私信”，就能开始聊天。</span></p>
   <button v-if="inboxNext" class="dm-more" :disabled="loading" @click="inbox(true)">加载更多会话</button>
  </template>
  <template v-else>
   <div class="dm-chat-heading"><TreeholeAvatar :name="conversation.member.nickname" :url="conversation.member.avatar?.url" :size="30"/><span>{{conversation.member.nickname}}</span><button aria-label="屏蔽私信对象" :disabled="loading||sending||blocked" @click="confirmBlock=!confirmBlock"><ShieldBan :size="18"/></button></div>
   <div v-if="confirmBlock" class="dm-block-confirm"><p>屏蔽后双方无法继续私信，关注关系会解除。可在“我的社区”恢复屏蔽。</p><button @click="confirmBlock=false">取消</button><button @click="block">确认屏蔽</button></div>
   <div ref="scroller" class="dm-history" role="log" aria-label="聊天记录" @scroll.passive="scrolling">
    <button v-if="older" class="dm-more" :disabled="loadingOlder" @click="history(true)">{{loadingOlder?'正在加载…':'查看更早消息'}}</button>
    <p v-if="!messages.length&&!loading&&!blocked" class="dm-start">打个招呼吧，私信显示你的邯院通昵称。</p>
    <article v-for="message in messages" :key="message.id" class="dm-message" :class="{mine:message.mine}" :data-message-id="message.id"><time>{{treeholeTimestamp(message.createdAt)}}</time><p>{{message.body}}</p></article>
   </div>
   <button v-if="newMessages" class="dm-new" @click="bottom"><ArrowDown :size="15"/>新消息 · 回到底部</button>
   <button v-if="readError&&!blocked" class="dm-read-retry" @click="acknowledge">未读状态尚未同步，点击重试</button>
   <form class="dm-composer" @submit.prevent="send"><textarea ref="textarea" v-model="text" aria-label="私信内容" placeholder="说点什么…" maxlength="1000" rows="2" :disabled="sending||blocked" @input="changed"/><div><small>{{text.length}} / 1000</small><button :disabled="!canSend" :aria-label="draft?.failed?'重试发送私信':'发送私信'"><Send :size="18"/>{{sending?'发送中…':draft?.failed?'重试发送':'发送'}}</button></div></form>
   <p class="dm-private-note">私信不展示在公开主页，暂支持文字。未发送文字暂存在本次会话，退出账号后清除。</p>
  </template>
  <p v-if="loading" class="dm-state" role="status">正在加载私信…</p>
  <div v-if="error" class="dm-error" role="alert"><p>{{error}}</p><button v-if="!blocked&&!draft?.failed" :disabled="loading" @click="conversation?history():initialMember?openThread(initialMember,true):inbox()">重试加载</button></div>
 </section>
</template>
<style scoped>
.th-dm{padding-bottom:12px}.dm-list-heading,.dm-chat-heading{display:flex;align-items:center;gap:9px;min-height:52px;font-size:13px;color:var(--color-muted);border-bottom:1px solid var(--color-divider)}.dm-list-heading>span,.dm-chat-heading>span{flex:1;min-width:0;overflow-wrap:anywhere}.dm-list-heading button,.dm-chat-heading button{width:44px;min-height:44px;display:grid;place-items:center}.dm-thread{width:100%;display:flex;align-items:center;gap:11px;text-align:left;padding:15px 0;border-bottom:1px solid var(--color-divider)}.dm-thread>span:first-of-type{flex:1;min-width:0}.dm-thread strong{display:block;font-size:15px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.dm-thread small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;color:var(--color-muted);margin-top:5px}.dm-thread-meta{display:flex;flex-direction:column;align-items:flex-end;gap:7px}.dm-thread time{font-size:11px;color:var(--color-muted)}.dm-thread b{font-size:11px;border-radius:12px;padding:2px 5px;background:var(--color-primary);color:white}.dm-thread>svg{color:var(--color-muted)}
.dm-empty{display:flex;flex-direction:column;align-items:center;gap:14px;padding:65px 8px;font-size:16px}.dm-empty>span{font-size:13px;color:var(--color-muted);text-align:center}.dm-more{display:block;min-height:44px;margin:0 auto;color:var(--color-primary);font-size:13px}.is-chat{height:calc(100dvh - 60px - var(--safe-top));display:flex;flex-direction:column;padding-bottom:var(--safe-bottom)}.dm-chat-heading{flex-shrink:0}.dm-history{flex:1;min-height:100px;overflow-y:auto;overscroll-behavior:contain;padding:8px 0 16px;overflow-anchor:none}.dm-message{display:flex;align-items:flex-start;flex-direction:column;margin:10px 0 15px}.dm-message time{font-size:11px;color:var(--color-muted);margin:0 5px 5px}.dm-message p{padding:10px 13px;background:var(--color-bg);border-radius:4px 15px 15px;max-width:87%;font-size:16px;line-height:1.65;white-space:pre-wrap;overflow-wrap:anywhere;user-select:text}.dm-message.mine{align-items:flex-end}.dm-message.mine p{background:var(--color-tint);border-radius:15px 4px 15px 15px}.dm-start{font-size:13px;color:var(--color-muted);padding:28px 8px;text-align:center}.dm-composer{border-top:1px solid var(--color-divider);padding-top:10px;flex-shrink:0}.dm-composer textarea{width:100%;min-height:72px;max-height:150px;border:1px solid var(--color-border);border-radius:12px;background:var(--color-bg);color:var(--color-text);padding:10px 12px;font:inherit;font-size:16px;resize:none}.dm-composer>div{display:flex;align-items:center;justify-content:space-between;gap:10px}.dm-composer small{font-size:11px;color:var(--color-muted)}.dm-composer button{min-height:44px;display:flex;align-items:center;gap:7px;padding:0 18px;color:var(--color-primary);font-size:14px}.dm-private-note{font-size:11px;line-height:1.6;color:var(--color-muted);margin:3px 0 8px}.dm-state,.dm-error{font-size:13px;line-height:1.7;padding:10px 0;color:var(--color-muted)}.dm-error button,.dm-block-confirm button{min-height:44px;padding:0 12px;color:var(--color-primary);font-size:13px}.dm-block-confirm{font-size:13px;background:var(--color-tint);padding:10px;border-radius:10px}.dm-new,.dm-read-retry{min-height:44px;color:var(--color-primary);font-size:13px;display:flex;align-items:center;justify-content:center;gap:6px;flex-shrink:0}
</style>
