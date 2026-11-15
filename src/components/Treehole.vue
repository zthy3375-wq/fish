<script setup lang="ts">
import {ref,computed,onMounted,onUnmounted,onActivated,onDeactivated,watch,nextTick} from 'vue';
import {MessageCircle,Bookmark,ArrowLeft,ShieldCheck,Leaf,Search,X,PenLine,RefreshCw,ChevronRight,VenetianMask,LockKeyhole,LogOut,Eye,EyeOff,AlertCircle,Check,ArrowUp,Flag,Trash2,VolumeX,Sparkles,AtSign,ImagePlus,ThumbsUp,ChevronLeft,Bell,BellOff,MessagesSquare} from 'lucide-vue-next';
import TreeholeInbox from './TreeholeInbox.vue';
import TreeholeFeedPage from './TreeholeFeedPage.vue';
import TreeholeCommentThread from './TreeholeCommentThread.vue';
import {treeholeCategories,treeholeCategoryName} from '../domain/treeholeCategories';
import {readTreeholeDraft,writeTreeholeDraft,deleteTreeholeDraft,prepareTreeholeImage,type DraftImage} from '../services/treeholeDrafts';
import TreeholeAvatar from './TreeholeAvatar.vue';
import TreeholePostCard from './TreeholePostCard.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import {treeholeRequest as api,treeholeError,treeholeErrorCode,type TreeholeUser,type TreeholePost,type TreeholeComment,type TreeholeReport,type TreeholeNotification,type TreeholeProfile} from '../services/treehole';

const props=withDefaults(defineProps<{tabRoot?:boolean}>(),{tabRoot:false});
const category=ref('all'),postCategory=ref('daily'),sort=ref('latest'),postTitle=ref(''),images=ref<DraftImage[]>([]),imagesEnabled=ref(false),draftReady=ref(false),draftSaved=ref('');
const expandedReplies=ref<Record<string,boolean>>({}),replyPages=ref<Record<string,Record<string,string>|null>>({});
const gallery=ref<{post:TreeholePost;index:number}|null>(null),zoomed=ref(false),galleryX=ref(0);
const replyExpanded=ref(false),detailTab=ref('body'),galleryFailed=ref(false);
const detailLoading=ref(false),detailError=ref(''),pageMotion=ref('forward'),selectedPhoto=ref<string|null>(null),edgeOffset=ref(0);
let detailRequest=0,scrollIntentUntil=0;
function manualScroll(){scrollIntentUntil=0;}
const reducedMotion=()=>window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const scrollBehavior=():ScrollBehavior=>reducedMotion()?'instant':'smooth';
function movePhoto(delta:number){const index=images.value.findIndex(i=>i.id===selectedPhoto.value),next=index+delta;if(index<0||next<0||next>=images.value.length)return;const [photo]=images.value.splice(index,1);images.value.splice(next,0,photo);}
let edgeStart:{x:number;y:number;valid:boolean}|null=null;
function edgeDown(e:TouchEvent){manualScroll();const t=e.touches?.[0]||e.changedTouches?.[0];if(!t)return;edgeStart=screen.value!=='feed'&&!dialogOpen.value&&t.clientX<24?{x:t.clientX,y:t.clientY,valid:true}:null;}
function edgeMove(e:TouchEvent){if(!edgeStart)return;const t=e.touches[0];if(Math.abs(t.clientY-edgeStart.y)>30){edgeStart.valid=false;edgeOffset.value=0;}else if(edgeStart.valid&&!reducedMotion())edgeOffset.value=Math.min(180,Math.max(0,t.clientX-edgeStart.x));}
function edgeEnd(e:TouchEvent){const start=edgeStart;edgeStart=null;edgeOffset.value=0;if(!start?.valid)return;const t=e.changedTouches[0];if(t.clientX-start.x>90&&Math.abs(t.clientY-start.y)<30)requestBack();}

const pendingReactions=ref<Record<string,boolean>>({}),pendingLikes=ref<Record<string,boolean>>({}),loadingThreads=ref<Record<string,boolean>>({}),loadedThreads=new Set<string>();
let accountEpoch=0,detailEpoch=0,scrollFrame=0;
const currentImage=computed(()=>gallery.value?.post.images?.[gallery.value.index]);
let draftQueue=Promise.resolve(),draftTimer:ReturnType<typeof setTimeout>|undefined;
const emit=defineEmits<{exit:[];tabNavigation:[visible:boolean]}>();
const searchOpen=ref(false),showPassword=ref(false),replyInput=ref<HTMLTextAreaElement>(),searchInput=ref<HTMLInputElement>();
const dialogElement=ref<HTMLElement>(),dialogMotion=ref('th-sheet-motion');
const user=ref<TreeholeUser|null>(null),busy=ref(false),ready=ref(false),error=ref(''),notice=ref('');
const registration=ref(false),inviteRequired=ref(false),auth=ref<'login'|'register'|'recover'>('login');
const username=ref(''),password=ref(''),nickname=ref(''),invite=ref(''),agreed=ref(false),recoveryInput=ref(''),recovery=ref('');
type Screen='feed'|'compose'|'detail'|'account'|'moderate'|'inbox'|'profile';
const screen=ref<Screen>('feed');
const engagementEnabled=ref(false),unreadCount=ref(0),notifications=ref<TreeholeNotification[]>([]),inboxFilter=ref('all'),inboxLoading=ref(false),inboxError=ref(''),inboxNext=ref<Record<string,string>|null>(null);
const profile=ref<TreeholeProfile|null>(null),profilePosts=ref<TreeholePost[]>([]),profileNext=ref<Record<string,string>|null>(null),bio=ref('');
const focusedThread=ref<TreeholeComment|null>(null),focusedCommentId=ref(''),watchPending=ref(false);
let inboxRevision=0,unreadBusy=false,unreadTimer:ReturnType<typeof setInterval>|undefined;
const routeHistory:Array<{screen:Screen;scroll:number;detail:TreeholePost|null;comments:TreeholeComment[];commentNext:Record<string,string>|null;profile:TreeholeProfile|null;profilePosts:TreeholePost[];profileNext:Record<string,string>|null;context:TreeholeComment|null}>=[];
const scopeLabels:Record<string,string>={mine:'我的帖子',saved:'我的收藏',participated:'我参与的',watching:'关注的讨论'};
const posts=ref<TreeholePost[]>([]),scope=ref('all'),query=ref(''),feedNext=ref<Record<string,string>|null>(null);
const feedLoadingMore=ref(false),feedPageError=ref(''),feedRevision=ref(0);
let appliedFeedKey='',feedNeedsRefresh=false;
const detail=ref<TreeholePost|null>(null),comments=ref<TreeholeComment[]>([]),commentNext=ref<Record<string,string>|null>(null),reply=ref<TreeholeComment|null>(null);
const body=ref(''),anonymous=ref(false),commentBody=ref(''),commentAnon=ref(false),postKey=ref<string>(crypto.randomUUID()),commentKey=ref<string>(crypto.randomUUID());
const reports=ref<TreeholeReport[]>([]),newPassword=ref(''),accountAction=ref<'overview'|'profile'|'password'|'delete'>('overview');
const menu=ref<string|null>(null),reportTarget=ref<{postId:string;commentId?:string}|null>(null),reason=ref(''),discard=ref(false);
const confirmAction=ref<{title:string;run:()=>Promise<void>}|null>(null);
let alive=true,active=true;
const identity=computed(()=>anonymous.value?'匿名同学':user.value?.nickname||'邯院通昵称');
const forceCommentAnon=computed(()=>!!detail.value?.anonymous&&!!detail.value?.author.mine);
function date(value:string){return treeholeTimestamp(value);}
const title=computed(()=>({compose:'发帖',detail:'帖子详情',account:'我的社区',moderate:'社区管理',inbox:'互动消息',profile:'同学主页',feed:'邯院社区'})[screen.value]);
const dialogOpen=computed(()=>!!(menu.value||confirmAction.value||reportTarget.value||discard.value||gallery.value||replyExpanded.value));
function publishTabNavigation(){emit('tabNavigation',screen.value==='feed'&&!recovery.value&&!dialogOpen.value);}
watch([screen,recovery,dialogOpen],publishTabNavigation,{immediate:true});
const actionPost=computed(()=>[detail.value,...posts.value,...profilePosts.value].find(p=>p?.id===menu.value)||(screen.value==='detail'?detail.value:undefined));
const allComments=computed(()=>[...comments.value,...(focusedThread.value?[focusedThread.value]:[])].flatMap(c=>[c,...c.replies||[]]));
const actionComment=computed(()=>allComments.value.find(c=>c.id===menu.value));
function navigationBack(){if(!requestBack())emit('exit');}
function refresh(){if(busy.value||recovery.value||screen.value!=='feed')return;if(!user.value){void initialize();return;}void run(async()=>{await feed();void refreshUnread();notice.value='帖子已刷新';});}
function toggleSearch(){searchOpen.value=!searchOpen.value;if(searchOpen.value)void nextTick(()=>searchInput.value?.focus());}
function clearSearch(){query.value='';void run(()=>feed());}
function focusReply(comment?:TreeholeComment){if(busy.value||detail.value?.locked)return;if(comment)reply.value=comment;replyExpanded.value=true;}
function closeReply(){replyInput.value?.blur();replyExpanded.value=false;}
function accountFeed(next:string){routeHistory.length=0;scope.value=next;query.value='';category.value='all';sort.value='latest';screen.value='feed';void run(()=>feed());}
function selectCategory(next:string){if(busy.value)return;if(screen.value==='detail'&&commentBody.value.trim()){error.value='请先发布回复，或返回时选择放弃';return;}category.value=next;scope.value='all';screen.value='feed';detail.value=null;void run(()=>feed());}
function setSort(next:string){if(busy.value)return;sort.value=next;scope.value='all';void run(()=>feed());}
function windowTop(){scrollIntentUntil=performance.now()+650;detailTab.value="body";window.scrollTo({top:0,behavior:scrollBehavior()});}
function scrollDiscussion(){scrollIntentUntil=performance.now()+650;detailTab.value='comments';document.querySelector('.th-discussion-title')?.scrollIntoView({behavior:scrollBehavior(),block:'start'});}
function trackDetailScroll(){cancelAnimationFrame(scrollFrame);scrollFrame=requestAnimationFrame(()=>{if(screen.value!=='detail'||performance.now()<scrollIntentUntil)return;const heading=document.querySelector('.th-discussion-title'),nav=document.querySelector('.th-nav');if(!heading||!nav)return;const top=heading.getBoundingClientRect().top;if(window.scrollY<8)detailTab.value='body';else if(top<=nav.getBoundingClientRect().bottom+24)detailTab.value='comments';else if(top>window.innerHeight*.7)detailTab.value='body';});}
async function restoreDraft(){if(!user.value)return;draftReady.value=false;try{const d=await readTreeholeDraft(user.value.id);if(d){postTitle.value=d.title;body.value=d.body;postCategory.value=d.category;anonymous.value=d.anonymous;postKey.value=d.requestId;images.value=d.images;}}catch{draftSaved.value='草稿暂时无法读取';}finally{draftReady.value=true;}}
function saveDraft():Promise<boolean>{if(!draftReady.value||!user.value)return Promise.resolve(false);const id=user.value.id;let saved=false;const snapshot=JSON.parse(JSON.stringify({title:postTitle.value,body:body.value,category:postCategory.value,anonymous:anonymous.value,requestId:postKey.value,images:images.value}));draftQueue=draftQueue.then(()=>snapshot.title||snapshot.body||snapshot.images.length?writeTreeholeDraft(id,snapshot):deleteTreeholeDraft(id)).then(()=>{saved=true;draftSaved.value='草稿已保存';}).catch(()=>{draftSaved.value='草稿保存失败，请保留当前页面';});return draftQueue.then(()=>saved);}
function saveAndLeave(){void run(async()=>{clearTimeout(draftTimer);if(!await saveDraft()){error.value='草稿未保存，请继续编辑后重试';return;}discard.value=false;screen.value='feed';});}
async function clearDraft(){clearTimeout(draftTimer);draftReady.value=false;const id=user.value?.id;postTitle.value='';body.value='';images.value=[];draftSaved.value='';await draftQueue;try{if(id)await deleteTreeholeDraft(id);}catch{draftSaved.value='本地草稿清理失败';}finally{draftReady.value=true;}}
watch([postTitle,body,postCategory,anonymous,images],()=>{if(screen.value==='compose'&&draftReady.value){draftSaved.value='保存中…';clearTimeout(draftTimer);draftTimer=setTimeout(saveDraft,180);}},{deep:true});
async function chooseImages(event:Event){const input=event.target as HTMLInputElement;const files=Array.from(input.files||[]);input.value='';if(images.value.length+files.length>9){error.value='最多添加 9 张图片';return;}await run(async()=>{for(const file of files)images.value.push(await prepareTreeholeImage(file));saveDraft();});}
function removeImage(index:number){const old=images.value.splice(index,1)[0];if(old?.remote)void api('media.discard',{imageId:old.remote.id}).catch(()=>{});}
function imageView(post:TreeholePost,index:number){gallery.value={post,index};zoomed.value=false;galleryFailed.value=false;void renewImage();}
async function renewImage(){galleryFailed.value=false;const g=gallery.value,im=currentImage.value;if(!g||!im)return;try{const fresh=(await api('media.url',{postId:g.post.id,imageId:im.id})).image;if(fresh&&gallery.value===g){Object.assign(im,fresh);if(currentImage.value?.id===im.id)galleryFailed.value=false;}}catch{}}
function galleryStep(delta:number){if(!gallery.value)return;const n=gallery.value.post.images?.length||1;gallery.value.index=(gallery.value.index+delta+n)%n;zoomed.value=false;void renewImage();}
function imageGesture(event:TouchEvent){const distance=event.changedTouches[0].clientX-galleryX.value;if(!zoomed.value&&Math.abs(distance)>60)galleryStep(distance<0?1:-1);}
function actionError(e:unknown,epoch:number){if(!alive||epoch!==accountEpoch)return;error.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired')clearAccount();}
async function commentLike(c:TreeholeComment){
 const postId=detail.value?.id,epoch=accountEpoch;if(!postId||busy.value||pendingLikes.value[c.id])return;
 const before={liked:!!c.liked,likeCount:c.likeCount||0},enabled=!before.liked;pendingLikes.value[c.id]=true;error.value='';
 const apply=(value:{liked:boolean;likeCount:number})=>{Object.assign(c,value);const current=allComments.value.find(item=>item.id===c.id);if(current&&current!==c)Object.assign(current,value);};
 apply({liked:enabled,likeCount:Math.max(0,before.likeCount+(enabled?1:-1))});
 try{const r=await api('comments.like',{postId,commentId:c.id,enabled});if(alive&&epoch===accountEpoch&&r.comment)apply({liked:!!r.comment.liked,likeCount:r.comment.likeCount||0});}
 catch(e){if(epoch===accountEpoch)apply(before);actionError(e,epoch);}finally{if(epoch===accountEpoch)delete pendingLikes.value[c.id];}
}
async function expandThread(c:TreeholeComment){
 const postId=detail.value?.id,epoch=accountEpoch,discussion=detailEpoch;if(!postId||busy.value||loadingThreads.value[c.id])return;
 if(loadedThreads.has(c.id)&&!expandedReplies.value[c.id]){expandedReplies.value[c.id]=true;return;}
 const more=!!expandedReplies.value[c.id];if(more&&!replyPages.value[c.id])return;
 loadingThreads.value[c.id]=true;error.value='';
 try{const r=await api('comments.replies',{postId,rootId:c.id,...(more?replyPages.value[c.id]:{})});if(!alive||epoch!==accountEpoch||discussion!==detailEpoch||detail.value?.id!==postId)return;
 c.replies=Array.from(new Map([...(more?c.replies||[]:[]),...r.comments||[]].map(x=>[x.id,x])).values());expandedReplies.value[c.id]=true;loadedThreads.add(c.id);replyPages.value[c.id]=r.next||null;
 }catch(e){actionError(e,epoch);}finally{if(epoch===accountEpoch)delete loadingThreads.value[c.id];}
}
let feedAnchor:{id:string;offset:number}|null=null;
let restoringScroll:number|null=null;
let feedScroll=0,previousFocus:HTMLElement|null=null,previousOverflow='',noticeTimer:ReturnType<typeof setTimeout>|undefined;
function rememberFeedPosition(){
 feedScroll=window.scrollY;
 const top=document.querySelector('.th-nav')?.getBoundingClientRect().bottom||0;
 const card=Array.from(document.querySelectorAll<HTMLElement>('.th-post[data-post-id]')).find(el=>el.getBoundingClientRect().bottom>top);
 feedAnchor=card?.dataset.postId?{id:card.dataset.postId,offset:card.getBoundingClientRect().top}:null;
}
function restoreFeedPosition(){
 const card=feedAnchor?Array.from(document.querySelectorAll<HTMLElement>('.th-post[data-post-id]')).find(el=>el.dataset.postId===feedAnchor!.id):undefined;
 const top=card&&feedAnchor?window.scrollY+card.getBoundingClientRect().top-feedAnchor.offset:feedScroll;
 window.scrollTo({top:Math.max(0,top),behavior:'instant'});
}
watch(screen,async(next,prior)=>{
 if(prior==='feed')rememberFeedPosition();
 const restore=restoringScroll;restoringScroll=null;
 pageMotion.value=next==='feed'?'back':'forward';notice.value='';
 if(prior==='detail'&&next!=='detail'){detailRequest++;detailEpoch++;detailLoading.value=false;detailError.value='';}
 await nextTick();if(!alive||!active||screen.value!==next)return;
 if(restore!==null&&!(next==='feed'&&feedNeedsRefresh))window.scrollTo({top:restore,behavior:'instant'});
 else if(next==='feed'&&!feedNeedsRefresh)restoreFeedPosition();
 else if(next==='detail'&&detailTab.value==='comments'){
  scrollIntentUntil=performance.now()+650;
  document.querySelector(focusedThread.value?'.th-focus-context':'.th-discussion-title')?.scrollIntoView({block:'start',behavior:'instant'});
 }else window.scrollTo({top:0,behavior:'instant'});
});
watch(notice,()=>{clearTimeout(noticeTimer);if(notice.value)noticeTimer=setTimeout(()=>{notice.value='';},5000);});
watch(dialogOpen,async(open)=>{if(open){dialogMotion.value=gallery.value?'th-gallery-motion':'th-sheet-motion';previousFocus=document.activeElement as HTMLElement;previousOverflow=document.body.style.overflow;document.body.style.overflow='hidden';await nextTick();if(replyExpanded.value)replyInput.value?.focus();else dialogElement.value?.querySelector<HTMLElement>('button,input,textarea')?.focus();}else{document.body.style.overflow=previousOverflow;await nextTick();previousFocus?.focus({preventScroll:true});}});
watch([menu,reportTarget,confirmAction,discard,gallery],async()=>{if(dialogOpen.value){await nextTick();if(replyExpanded.value)replyInput.value?.focus();else dialogElement.value?.querySelector<HTMLElement>('button,input,textarea')?.focus();}});
function trapKeys(event:KeyboardEvent){if(!dialogOpen.value)return;if(event.key==='Escape'){event.stopImmediatePropagation();event.preventDefault();requestBack();}if(event.key==='Tab'){const controls=Array.from(dialogElement.value?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),textarea:not(:disabled)')||[]);const first=controls[0],last=controls.at(-1);if(!first){event.preventDefault();return;}if(event.shiftKey&&document.activeElement===first){last?.focus();event.preventDefault();}else if(!event.shiftKey&&document.activeElement===last){first.focus();event.preventDefault();}}}
async function run(work:()=>Promise<void>){
 if(busy.value)return;busy.value=true;error.value='';notice.value='';
 try{await work();}catch(e){if(alive){error.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired'){clearAccount();}}}
 finally{if(alive)busy.value=false;}
}
function clearAccount(){accountEpoch++;inboxRevision++;inboxLoading.value=false;inboxError.value='';notifications.value=[];unreadCount.value=0;inboxNext.value=null;profile.value=null;profilePosts.value=[];profileNext.value=null;focusedThread.value=null;focusedCommentId.value='';routeHistory.length=0;restoringScroll=null;watchPending.value=false;bio.value='';detailRequest++;detailEpoch++;detailLoading.value=false;detailError.value='';feedRevision.value++;feedLoadingMore.value=false;feedPageError.value='';feedNext.value=null;commentNext.value=null;appliedFeedKey='';feedNeedsRefresh=false;feedScroll=0;feedAnchor=null;pendingReactions.value={};pendingLikes.value={};loadingThreads.value={};loadedThreads.clear();replyExpanded.value=false;draftReady.value=false;postTitle.value='';images.value=[];category.value='all';sort.value='latest';showPassword.value=false;searchOpen.value=false;auth.value='login';user.value=null;posts.value=[];detail.value=null;comments.value=[];body.value='';commentBody.value='';reply.value=null;recovery.value='';password.value='';newPassword.value='';recoveryInput.value='';screen.value='feed';menu.value=null;reportTarget.value=null;}
function feedCriteria(){return {scope:scope.value,query:query.value,category:category.value,sort:sort.value};}
function feedKey(){return JSON.stringify(feedCriteria());}
function appendUnique<T extends {id:string}>(current:T[],incoming:T[]){
 const seen=new Set(current.map(item=>item.id));
 return [...current,...incoming.filter(item=>{if(seen.has(item.id))return false;seen.add(item.id);return true;})];
}
async function feed(){
 const revision=++feedRevision.value,epoch=accountEpoch,criteria=feedCriteria(),key=JSON.stringify(criteria);
 feedLoadingMore.value=false;feedPageError.value='';
 const r=await api('posts.list',criteria);
 if(!alive||epoch!==accountEpoch||revision!==feedRevision.value)return;
 posts.value=r.posts||[];feedNext.value=r.next||null;appliedFeedKey=key;feedNeedsRefresh=false;feedAnchor=null;feedScroll=0;
 await nextTick();if(active&&screen.value==='feed')window.scrollTo({top:0,behavior:'instant'});
}
async function loadMoreFeed(){
 if(busy.value||feedLoadingMore.value||!feedNext.value||appliedFeedKey!==feedKey())return;
 const revision=feedRevision.value,epoch=accountEpoch,key=appliedFeedKey,cursor={...feedNext.value},criteria=feedCriteria();
 feedLoadingMore.value=true;feedPageError.value='';
 try{
  const r=await api('posts.list',{...criteria,...cursor});
  if(!alive||epoch!==accountEpoch||revision!==feedRevision.value||key!==feedKey())return;
  posts.value=appendUnique(posts.value,r.posts||[]);
  feedNext.value=r.next||null;
  if(r.next&&JSON.stringify(r.next)===JSON.stringify(cursor))feedPageError.value='暂时无法继续加载，请刷新后重试';
 }catch(e){
  if(alive&&epoch===accountEpoch&&revision===feedRevision.value&&key===feedKey()){
   if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);else feedPageError.value=treeholeError(e);
  }
 }finally{if(epoch===accountEpoch&&revision===feedRevision.value)feedLoadingMore.value=false;}
}
function syncFeedPost(post:TreeholePost){
 posts.value=posts.value.map(cached=>{
  if(cached.id!==post.id)return cached;
  return {...post,...(pendingReactions.value[post.id+':like']?{liked:cached.liked,likeCount:cached.likeCount}:{}),...(pendingReactions.value[post.id+':save']?{saved:cached.saved}:{})};
 });
}
function returnFeed(){
 routeHistory.length=0;focusedThread.value=null;
 screen.value='feed';detail.value=null;password.value='';newPassword.value='';error.value='';
 if(feedNeedsRefresh)void run(()=>feed());
}
function rememberRoute(){routeHistory.push({screen:screen.value,scroll:window.scrollY,detail:detail.value,comments:comments.value,commentNext:commentNext.value,profile:profile.value,profilePosts:profilePosts.value,profileNext:profileNext.value,context:focusedThread.value});}
function previousRoute(){
 const previous=routeHistory.pop();if(!previous){returnFeed();return;}
 detail.value=previous.detail;comments.value=previous.comments;commentNext.value=previous.commentNext;profile.value=previous.profile;profilePosts.value=previous.profilePosts;profileNext.value=previous.profileNext;focusedThread.value=previous.context;
 restoringScroll=previous.scroll;screen.value=previous.screen;error.value='';expandedReplies.value={};replyPages.value={};loadedThreads.clear();
 if(previous.screen==='feed'&&feedNeedsRefresh)void run(()=>feed());
}
async function refreshUnread(){
 if(!engagementEnabled.value||!user.value||!active||document.hidden||unreadBusy)return;
 const epoch=accountEpoch;unreadBusy=true;
 try{const r=await api('notifications.unread');if(alive&&epoch===accountEpoch)unreadCount.value=r.unreadCount??0;}
 catch(e){if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);}
 finally{unreadBusy=false;}
}
async function loadInbox(more=false){
 if(inboxLoading.value||!user.value)return;
 const epoch=accountEpoch,revision=++inboxRevision,filter=inboxFilter.value;
 inboxLoading.value=true;inboxError.value='';
 try{const r=await api('notifications.list',{filter,...(more?inboxNext.value:{})});if(!alive||epoch!==accountEpoch||revision!==inboxRevision)return;notifications.value=more?appendUnique(notifications.value,r.notifications||[]):r.notifications||[];inboxNext.value=r.next||null;unreadCount.value=r.unreadCount??0;}
 catch(e){if(epoch===accountEpoch&&revision===inboxRevision){inboxError.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);}}
 finally{if(epoch===accountEpoch&&revision===inboxRevision)inboxLoading.value=false;}
}
function showInbox(){if(busy.value)return;rememberRoute();screen.value='inbox';error.value='';void loadInbox();}
function filterInbox(value:string){inboxFilter.value=value;notifications.value=[];inboxNext.value=null;void loadInbox();}
async function markNotifications(ids:string[]){
 if(!ids.length)return;const epoch=accountEpoch,r=await api('notifications.read',{ids});if(!alive||epoch!==accountEpoch)return;
 const read=new Set(ids);notifications.value=notifications.value.map(n=>read.has(n.id)?{...n,readAt:n.readAt||new Date().toISOString()}:n);unreadCount.value=r.unreadCount??unreadCount.value;
}
function markVisibleRead(){void run(()=>markNotifications(notifications.value.filter(n=>!n.readAt).map(n=>n.id).slice(0,50)));}
function openNotification(item:TreeholeNotification){void run(async()=>{
 const epoch=accountEpoch;
 const r=await api('posts.get',{postId:item.postId,threaded:true});if(!alive||epoch!==accountEpoch||!r.post)return;
 let context:TreeholeComment|null=null;
 if(item.commentId){try{context=(await api('comments.context',{postId:item.postId,commentId:item.commentId})).context||null;}catch(e){if(treeholeErrorCode(e)!=='not_found')throw e;notice.value='这条回复已不可用，可以继续查看讨论';}}
 if(!alive||epoch!==accountEpoch)return;
 rememberRoute();detailEpoch++;detail.value=r.post;syncFeedPost(r.post);comments.value=r.comments||[];commentNext.value=r.next||null;expandedReplies.value={};replyPages.value={};loadedThreads.clear();focusedThread.value=context;focusedCommentId.value=item.commentId||'';
 commentBody.value='';reply.value=null;commentAnon.value=false;commentKey.value=crypto.randomUUID();screen.value='detail';detailTab.value=item.commentId?'comments':'body';
 try{await markNotifications([item.id]);}catch(e){actionError(e,epoch);}
});}
function openProfile(memberId:string){if(!engagementEnabled.value||(screen.value==='profile'&&profile.value?.id===memberId))return;void run(async()=>{
 const epoch=accountEpoch;
 const [p,r]=await Promise.all([api('profile.get',{memberId}),api('posts.list',{scope:'author',memberId})]);if(!alive||epoch!==accountEpoch||!p.profile)return;
 rememberRoute();profile.value=p.profile;profilePosts.value=r.posts||[];profileNext.value=r.next||null;screen.value='profile';
});}
function moreProfile(){if(!profile.value||!profileNext.value)return;void run(async()=>{
 const epoch=accountEpoch,id=profile.value!.id,r=await api('posts.list',{scope:'author',memberId:id,...profileNext.value});if(epoch!==accountEpoch||profile.value?.id!==id)return;
 profilePosts.value=appendUnique(profilePosts.value,r.posts||[]);profileNext.value=r.next||null;
});}
async function toggleWatch(post:TreeholePost){
 if(watchPending.value||busy.value)return;const epoch=accountEpoch;watchPending.value=true;
 try{const r=await api('threads.watch',{postId:post.id,enabled:!post.watching});if(!alive||epoch!==accountEpoch||!r.post)return;for(const cached of [...posts.value,...profilePosts.value])if(cached.id===post.id)cached.watching=r.post.watching;if(detail.value?.id===post.id)detail.value.watching=r.post.watching;notice.value=r.post.watching?'已关注，有新回复时会出现在互动消息':'已取消关注，直接回复你仍会提醒';if(scope.value==='watching')feedNeedsRefresh=true;void refreshUnread();}
 catch(e){actionError(e,epoch);}finally{if(epoch===accountEpoch)watchPending.value=false;}
}
async function initialize(){await run(async()=>{
 const config=await api('config');if(!alive)return;registration.value=!!config.registrationEnabled;inviteRequired.value=!!config.requiresInvite;imagesEnabled.value=!!config.imagesEnabled;engagementEnabled.value=!!config.engagementEnabled;
 try{const r=await api('me');if(!alive)return;user.value=r.user!;nickname.value=r.user!.nickname;await restoreDraft();await feed();}
 catch(e){if(treeholeErrorCode(e)!=='session_expired')throw e;}
 ready.value=true;void refreshUnread();
});}
function authenticate(){void run(async()=>{
 const r=await api(auth.value,{username:username.value,password:password.value,nickname:nickname.value,invite:invite.value,agreed:agreed.value,recoveryCode:recoveryInput.value});
 password.value='';recoveryInput.value='';if(!alive)return;user.value=r.user!;nickname.value=r.user!.nickname;recovery.value=r.recoveryCode||'';screen.value='feed';posts.value=[];scope.value='all';query.value='';await restoreDraft();await feed();void refreshUnread();
});}
function changeScope(next:string){if(busy.value)return;scope.value=next;if(next==='all')sort.value='latest';void run(()=>feed());}
function compose(anon=false){replyExpanded.value=false;reply.value=null;commentBody.value='';commentAnon.value=false;commentKey.value=crypto.randomUUID();if(!body.value&&!postTitle.value&&!images.value.length){anonymous.value=anon;postCategory.value=category.value==='all'?'daily':category.value;postKey.value=crypto.randomUUID();}screen.value='compose';error.value='';}

async function loadDetail(post:TreeholePost,more=false){
 const epoch=accountEpoch,request=++detailRequest;
 detailLoading.value=true;detailError.value='';
 try{
  const r=await api('posts.get',{postId:post.id,threaded:true,...(more?commentNext.value:{})});
  if(!alive||epoch!==accountEpoch||request!==detailRequest||screen.value!=='detail'||detail.value?.id!==post.id)return;
  if(!r.post)throw Error('post_not_found');
  const fresh={...r.post,...(pendingReactions.value[post.id+':like']?{liked:detail.value.liked,likeCount:detail.value.likeCount}:{}),...(pendingReactions.value[post.id+':save']?{saved:detail.value.saved}:{})};
  detail.value=fresh;syncFeedPost(fresh);
  if(!more){detailEpoch++;expandedReplies.value={};replyPages.value={};loadedThreads.clear();}
  comments.value=more?appendUnique(comments.value,r.comments||[]):r.comments||[];commentNext.value=r.next||null;
 }catch(e){
  if(alive&&epoch===accountEpoch&&request===detailRequest&&screen.value==='detail'&&detail.value?.id===post.id){
   if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);else detailError.value=treeholeError(e);
  }
 }finally{if(epoch===accountEpoch&&request===detailRequest)detailLoading.value=false;}
}
function openPost(post:TreeholePost,discussion=false){
 if(busy.value||screen.value==='detail')return;
 rememberRoute();focusedThread.value=null;focusedCommentId.value='';
 detailEpoch++;detail.value={...post};comments.value=[];commentNext.value=null;expandedReplies.value={};replyPages.value={};loadedThreads.clear();
 screen.value='detail';detailTab.value=discussion?'comments':'body';replyExpanded.value=false;commentBody.value='';reply.value=null;commentAnon.value=false;commentKey.value=crypto.randomUUID();menu.value=null;error.value='';
 void loadDetail(post);
}
function publish(){void run(async()=>{
 for(const image of images.value){if(!image.remote){notice.value='正在上传图片 '+(images.value.indexOf(image)+1)+' / '+images.value.length;const r=await api('media.upload',{data:image.data,requestId:image.id});image.remote=r.image!;saveDraft();}}
 let r;try{r=await api('posts.create',{title:postTitle.value,category:postCategory.value,images:images.value.map(i=>i.remote!.id),body:body.value,anonymous:anonymous.value,requestId:postKey.value});}catch(e){if(treeholeErrorCode(e)==='image_unavailable'){for(const image of images.value){image.remote=undefined;image.id=crypto.randomUUID();}saveDraft();}throw e;}if(!alive)return;
 await clearDraft();postKey.value=crypto.randomUUID();feedNeedsRefresh=true;feedScroll=0;feedAnchor=null;detail.value=r.post!;comments.value=[];screen.value='detail';detailTab.value='body';replyExpanded.value=false;await loadDetail(r.post!);notice.value='已发布';
});}

function sendComment(){if(!detail.value)return;const post=detail.value;void run(async()=>{
 await api('comments.create',{postId:post.id,body:commentBody.value,anonymous:commentAnon.value||forceCommentAnon.value,requestId:commentKey.value,replyTo:reply.value?.id||null});
 closeReply();commentBody.value='';reply.value=null;commentKey.value=crypto.randomUUID();await loadDetail(post);notice.value='回复已发布';
});}
async function react(post:TreeholePost,kind:'like'|'save'){
 const key=post.id+':'+kind,epoch=accountEpoch;if(busy.value||pendingReactions.value[key])return;
 const before={liked:post.liked,saved:post.saved,likeCount:post.likeCount},enabled=kind==='like'?!post.liked:!post.saved;
 const apply=(value:Partial<TreeholePost>)=>{for(const p of [...posts.value,...profilePosts.value])if(p.id===post.id)Object.assign(p,value);if(detail.value?.id===post.id)Object.assign(detail.value,value);};
 pendingReactions.value[key]=true;error.value='';apply(kind==='like'?{liked:enabled,likeCount:Math.max(0,post.likeCount+(enabled?1:-1))}:{saved:enabled});
 try{const r=await api('reactions.set',{postId:post.id,kind,enabled});if(!alive||epoch!==accountEpoch||!r.post)return;apply(kind==='like'?{liked:r.post.liked,likeCount:r.post.likeCount}:{saved:r.post.saved});if(kind==='save'&&!r.post.saved&&scope.value==='saved')posts.value=posts.value.filter(item=>item.id!==post.id);}
 catch(e){if(epoch===accountEpoch)apply(kind==='like'?{liked:before.liked,likeCount:before.likeCount}:{saved:before.saved});actionError(e,epoch);}finally{if(epoch===accountEpoch)delete pendingReactions.value[key];}
}
function askDelete(post:TreeholePost,comment?:TreeholeComment){menu.value=null;confirmAction.value={title:comment?'删除这条评论？':'删除这条帖子和它的讨论？',run:async()=>{
 await api(comment?'comments.delete':'posts.delete',{postId:post.id,commentId:comment?.id});confirmAction.value=null;
 if(comment)await loadDetail(post);else{posts.value=posts.value.filter(p=>p.id!==post.id);screen.value='feed';detail.value=null;}
}};}
function report(post:TreeholePost,comment?:TreeholeComment){menu.value=null;reportTarget.value={postId:post.id,...(comment?{commentId:comment.id}:{})};reason.value='';}
function submitReport(){if(!reportTarget.value)return;void run(async()=>{await api('reports.create',{...reportTarget.value,reason:reason.value});reportTarget.value=null;notice.value='举报已提交，管理员会查看处理';});}
function block(post:TreeholePost,comment?:TreeholeComment){menu.value=null;const anon=comment?comment.author.anonymous:post.anonymous;confirmAction.value={title:anon?'隐藏这条讨论？':'屏蔽此人的昵称发言？匿名内容不会关联屏蔽。',run:async()=>{await api('blocks.set',{postId:post.id,commentId:comment?.id});confirmAction.value=null;detail.value=null;screen.value='feed';await feed();}};}
function account(){screen.value='account';nickname.value=user.value?.nickname||'';bio.value=user.value?.bio||'';password.value='';newPassword.value='';accountAction.value='overview';}
function saveAccount(){void run(async()=>{
 if(accountAction.value==='profile'){const r=await api('profile.update',{nickname:nickname.value,...(engagementEnabled.value?{bio:bio.value}:{})});user.value=r.user!;feedNeedsRefresh=true;notice.value='资料已更新';}
 else if(accountAction.value==='password'){const r=await api('password.change',{password:password.value,newPassword:newPassword.value});password.value='';newPassword.value='';recovery.value=r.recoveryCode||'';notice.value='密码已更新，其他设备已退出';}
 else confirmAction.value={title:'注销邯院通账号？你的帖子、评论和登录状态将被删除，学校课表不受影响。',run:async()=>{await api('account.delete',{password:password.value});await clearDraft();confirmAction.value=null;clearAccount();notice.value='账号已注销';}};
});}
function logout(){confirmAction.value={title:'退出邯院通账号？',run:async()=>{await api('logout');await clearDraft();confirmAction.value=null;clearAccount();}};}
function moderate(){void run(async()=>{const r=await api('admin.reports');reports.value=r.reports||[];screen.value='moderate';});}
function resolveReport(r:TreeholeReport,decision:string){confirmAction.value={title:`确认${({remove:'删除内容',lock:'暂停回复',ban:'禁言 7 天',dismiss:'忽略举报'} as Record<string,string>)[decision]}？`,run:async()=>{
 await api('admin.resolve',{reportId:r.id,decision,reason:r.reason});feedNeedsRefresh=true;confirmAction.value=null;const result=await api('admin.reports');reports.value=result.reports||[];notice.value='已处理';
}};}
async function leaveEditor(){if(screen.value==='compose')await clearDraft();discard.value=false;body.value='';commentBody.value='';reply.value=null;returnFeed();}
function requestBack(){
 if(busy.value||recovery.value)return true;
 if(gallery.value){gallery.value=null;return true;}
 if(replyExpanded.value){closeReply();return true;}
 if(confirmAction.value){confirmAction.value=null;return true;}if(reportTarget.value){reportTarget.value=null;return true;}if(discard.value){discard.value=false;return true;}
 if(menu.value){menu.value=null;return true;}
 if((screen.value==='compose'&&(body.value.trim()||postTitle.value.trim()||images.value.length))||(screen.value==='detail'&&commentBody.value.trim())){discard.value=true;return true;}
 if(screen.value==='account'&&accountAction.value!=='overview'){accountAction.value='overview';password.value='';newPassword.value='';return true;}
 if(screen.value!=='feed'){previousRoute();return true;}
 if(searchOpen.value){searchOpen.value=false;return true;}
 if(!user.value&&auth.value!=='login'){auth.value='login';password.value='';return true;}return false;
}
function flushDraft(){clearTimeout(draftTimer);saveDraft();if(!document.hidden)void refreshUnread();}
function bindEvents(){document.addEventListener('visibilitychange',flushDraft);document.addEventListener('keydown',trapKeys,true);window.addEventListener('scroll',trackDetailScroll,{passive:true});window.addEventListener('wheel',manualScroll,{passive:true});if(!unreadTimer)unreadTimer=setInterval(()=>void refreshUnread(),60000);}
function unbindEvents(){document.removeEventListener('visibilitychange',flushDraft);document.removeEventListener('keydown',trapKeys,true);window.removeEventListener('scroll',trackDetailScroll);window.removeEventListener('wheel',manualScroll);cancelAnimationFrame(scrollFrame);clearInterval(unreadTimer);unreadTimer=undefined;}
defineExpose({requestBack,refresh});
onMounted(()=>{void initialize();bindEvents();});
onActivated(()=>{active=true;bindEvents();publishTabNavigation();void refreshUnread();});
onDeactivated(()=>{active=false;unbindEvents();flushDraft();password.value='';newPassword.value='';});
onUnmounted(()=>{clearTimeout(draftTimer);saveDraft();alive=false;active=false;clearTimeout(noticeTimer);unbindEvents();if(dialogOpen.value)document.body.style.overflow=previousOverflow;password.value='';newPassword.value='';});
</script>

<template>
 <section class="treehole" aria-label="邯院通树洞" :aria-busy="busy" :class="{'has-replies':screen==='detail'&&detail&&!recovery,'with-tab-navigation':props.tabRoot&&screen==='feed'}" @touchstart.passive="edgeDown" @touchmove.passive="edgeMove" @touchend.passive="edgeEnd" @touchcancel="edgeStart=null;edgeOffset=0">
  <div :inert="dialogOpen">
   <header class="th-nav">
    <button v-if="!props.tabRoot||screen!=='feed'" class="th-icon" :aria-label="screen==='feed'?'返回上一页':'返回社区'" :disabled="busy||!!recovery" @click="navigationBack"><ArrowLeft :size="22"/></button>
    <div v-if="screen==='detail'" class="th-detail-tabs"><button :aria-pressed="detailTab==='body'" @click="windowTop">正文</button><button :aria-pressed="detailTab==='comments'" @click="scrollDiscussion">评论</button></div><h1 v-else>{{title}}</h1>
    <template v-if="user&&screen==='feed'&&!recovery"><button class="th-icon" aria-label="搜索帖子" :aria-expanded="searchOpen" :disabled="busy" @click="toggleSearch"><Search :size="21"/></button><button v-if="engagementEnabled" class="th-icon th-inbox-entry" aria-label="互动消息" :disabled="busy" @click="showInbox"><Bell :size="21"/><span v-if="unreadCount" class="th-unread-badge">{{unreadCount>99?'99+':unreadCount}}</span></button><button class="th-self" :aria-label="user.nickname" :disabled="busy" @click="account"><TreeholeAvatar :name="user.nickname" :size="34"/></button></template>
    <button v-else-if="user&&screen==='compose'&&!recovery" class="th-publish" form="treehole-compose" :aria-label="anonymous?'匿名发布':'以昵称发布'" :disabled="busy||(!body.trim()&&!images.length)">发布</button>
    <span v-else class="th-nav-spacer"/>
    <div v-if="busy" class="th-progress" role="status" aria-label="正在处理"/>
   </header>
   <div class="th-content">
    <div v-if="error" class="th-alert" role="alert"><AlertCircle :size="18"/><div>{{error}}<button v-if="!ready" :disabled="busy" @click="initialize">重试连接</button><button v-else-if="user&&screen==='feed'" :disabled="busy" @click="run(()=>feed())">重新加载</button></div></div>
    <div v-if="notice" class="th-notice" role="status"><Check :size="17"/>{{notice}}</div>
    <section v-if="recovery" class="th-card th-recovery"><span class="th-illustration"><ShieldCheck :size="34"/></span><h2>保存你的账号恢复码</h2><p>忘记密码时，用登录账号和这串恢复码找回。请保存到密码管理器或安全位置。</p><code data-testid="recovery-code">{{recovery}}</code><p class="th-muted">只在这次显示，请勿分享给他人。</p><button class="th-primary th-wide" :disabled="busy" @click="recovery=''">我已保存恢复码</button></section>
    <template v-else>
     <div v-if="!ready&&!error" class="th-skeleton" aria-label="正在连接树洞"><span/><span/><span/></div>
     <template v-if="!user&&ready">
      <div class="th-welcome"><div class="th-welcome-art" aria-hidden="true"><span class="th-bubble"><MessageCircle :size="37"/></span><span class="th-mask"><VenetianMask :size="29"/></span><Sparkles class="th-spark" :size="22"/></div><p class="th-eyebrow">邯院通 · 校园社区</p><h2>{{auth==='login'?'说说校园里的那些事':auth==='register'?'遇见校园里的同频人':'把账号找回来'}}</h2><p>分享日常，认真倾听。<br>用昵称相遇，也可以匿名说说心里话。</p></div>
      <form class="th-card th-auth" @submit.prevent="authenticate">
       <div class="th-form-heading"><h3>{{auth==='login'?'登录邯院通':auth==='register'?'创建邯院通账号':'找回邯院通账号'}}</h3><span>与教务账号独立</span></div>
       <label>登录账号<input v-model="username" autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="24" placeholder="字母开头，4–24 位" required :disabled="busy"/></label>
       <label v-if="auth==='register'">公开昵称<input v-model="nickname" autocomplete="nickname" minlength="2" maxlength="20" placeholder="同学们看到的名字" required :disabled="busy"/></label>
       <label v-if="auth==='recover'">账号恢复码<input v-model="recoveryInput" autocomplete="off" autocapitalize="none" spellcheck="false" maxlength="64" placeholder="注册时保存的恢复码" required :disabled="busy"/></label>
       <label>{{auth==='recover'?'新密码':'密码'}}<span class="th-password"><input v-model="password" :type="showPassword?'text':'password'" :autocomplete="auth==='login'?'current-password':'new-password'" minlength="10" maxlength="128" placeholder="至少 10 位" required :disabled="busy"/><button type="button" :aria-label="showPassword?'隐藏密码':'显示密码'" :disabled="busy" @click="showPassword=!showPassword"><EyeOff v-if="showPassword" :size="18"/><Eye v-else :size="18"/></button></span></label>
       <label v-if="auth==='register'&&inviteRequired">内测邀请码<input v-model="invite" autocomplete="off" placeholder="输入邀请码，一起逛逛树洞" required :disabled="busy"/></label>
       <label v-if="auth==='register'" class="th-check"><input v-model="agreed" type="checkbox" required :disabled="busy"/><span>我已阅读并同意树洞规则与账号服务说明</span></label>
       <button class="th-primary th-wide" type="submit" :disabled="busy||auth==='register'&&(!agreed||!registration)">{{auth==='login'?'登录树洞':auth==='register'?'创建账号':'重设密码并登录'}}<ChevronRight :size="17"/></button>
       <div class="th-auth-links"><button v-if="auth!=='register'&&registration" type="button" :disabled="busy" @click="auth='register';password='';showPassword=false;error=''">注册账号</button><button v-if="auth!=='login'" type="button" :disabled="busy" @click="auth='login';password='';showPassword=false;error=''">返回登录</button><button v-if="auth==='login'" type="button" :disabled="busy" @click="auth='recover';password='';showPassword=false;error=''">忘记密码</button></div>
       <p v-if="!registration" class="th-muted">树洞正在准备内测，暂未开放新账号注册。</p>
      </form>
      <details class="th-rules"><summary><ShieldCheck :size="15"/>树洞规则与匿名说明</summary><p>尊重同学，勿发布他人隐私、辱骂、骚扰、垃圾广告或违法内容。可举报、删除自己的内容和注销账号。匿名会对其他用户隐藏昵称与账号，后台保留账号关联用于处理举报；不同帖子使用不同匿名代号。同一帖子内的匿名发言可关联。昵称发帖后改为匿名回复时，请留意内容本身是否暴露身份。</p><p>账号服务保存登录账号、昵称、密码加密摘要、帖子、互动与举报记录，用于登录及社区服务。教务账号与课表不会上传到社区。可以在账号设置中注销。</p></details>
     </template>
     <div v-if="user" :key="screen" class="th-screen-panel" :style="edgeOffset?{transform:'translateX('+edgeOffset+'px)',animation:'none',transition:'none'}:undefined" :class="'th-page-'+pageMotion" :data-screen="screen">
      <template v-if="screen==='feed'">
       <div v-if="engagementEnabled" class="th-return-links"><button :aria-pressed="scope==='all'" :disabled="busy" @click="accountFeed('all')">广场</button><button :aria-pressed="scope==='participated'" :disabled="busy" @click="accountFeed('participated')"><MessagesSquare :size="16"/>我参与的</button><button :aria-pressed="scope==='watching'" :disabled="busy" @click="accountFeed('watching')"><Bell :size="15"/>关注的讨论</button></div>
       <form v-if="searchOpen" class="th-search" @submit.prevent="run(()=>feed())"><Search :size="18"/><input ref="searchInput" v-model="query" maxlength="80" aria-label="搜索树洞文字" placeholder="搜索你感兴趣的内容" :disabled="busy"/><button v-if="query" type="button" aria-label="清除搜索" :disabled="busy" @click="clearSearch"><X :size="17"/></button><button class="th-search-submit" :disabled="busy">搜索</button></form>
       <nav class="th-category-nav" aria-label="帖子分区"><button :aria-pressed="category==='all'" :disabled="busy" @click="selectCategory('all')">全部</button><button v-for="item in treeholeCategories" :key="item.id" :aria-pressed="category===item.id" :disabled="busy" @click="selectCategory(item.id)">{{item.name}}</button></nav>
       <div class="th-feed-toolbar th-feed-intro"><div v-if="scope==='all'" class="th-tabs" aria-label="帖子筛选"><button :aria-pressed="sort==='latest'" :disabled="busy" @click="setSort('latest')">最新</button><button :aria-pressed="sort==='hot'" :disabled="busy" @click="setSort('hot')">热门</button></div><div v-else class="th-scope"><strong>{{scopeLabels[scope]||'广场'}}</strong><button :disabled="busy" @click="changeScope('all')">查看全部</button></div><button class="th-icon" aria-label="刷新树洞" :disabled="busy" @click="refresh"><RefreshCw :size="15"/></button></div>
       <button v-if="body||postTitle||images.length" class="th-draft-resume" :disabled="busy" @click="compose()"><PenLine :size="15"/> 有一条未发布的草稿，继续编辑 <ChevronRight :size="15"/></button>
       <div v-if="query&&!searchOpen" class="th-query">正在看「{{query}}」的搜索结果<button aria-label="清除搜索" :disabled="busy" @click="clearSearch"><X :size="14"/></button></div>
       <div v-if="!posts.length&&!busy&&!error" class="th-empty"><span class="th-empty-art"><MessageCircle :size="32"/><i><Leaf :size="20"/></i></span><h3>{{query?'还没找到这段回声':scope==='mine'?'你的故事，从这里开始':scope==='saved'?'把喜欢的瞬间留在这里':scope==='participated'?'聊过的话题，下次接着聊':scope==='watching'?'关心的讨论，留在这里':'这里，等你说第一句话'}}</h3><p>{{query?'换个关键词，看看大家在聊什么。':scope==='saved'?'在帖子下方点一下收藏，下次就能找到。':scope==='participated'?'发过的帖子和参与过的讨论会出现在这里。':scope==='watching'?'在帖子里关注讨论，新回复会提醒你。':'一件开心的小事，一个想问的问题，都可以。'}}</p><button v-if="!query&&['all','mine'].includes(scope)" class="th-text-link" :disabled="busy" @click="compose()">写下第一条树洞 <ChevronRight :size="15"/></button></div>
       <TreeholePostCard v-for="post in posts" :key="post.id" :post="post" :busy="busy" :reacting="pendingReactions[post.id+':like']" @open="openPost(post)" @discussion="openPost(post,true)" @react="react(post,$event)" @menu="menu=post.id" @image="imageView(post,$event)" @author="openProfile" @category="selectCategory"/>
       <TreeholeFeedPage v-if="feedNext" :page-key="feedRevision+JSON.stringify(feedNext)" :loading="feedLoadingMore" :error="feedPageError" :disabled="busy||!!recovery||dialogOpen" @load="loadMoreFeed"/>
       <p v-else-if="posts.length" class="th-feed-end">暂时就这些，过一会儿再来看看吧</p>

      </template>
      <TreeholeInbox v-else-if="screen==='inbox'" :items="notifications" :filter="inboxFilter" :loading="inboxLoading||busy" :error="inboxError" :more="!!inboxNext" :unread="unreadCount" @filter="filterInbox" @open="openNotification" @refresh="loadInbox()" @more="loadInbox(true)" @read="markVisibleRead"/>
      <template v-else-if="screen==='profile'&&profile"><div class="th-public-profile"><TreeholeAvatar :name="profile.nickname" :size="64"/><h2>{{profile.nickname}}</h2><p>{{profile.bio||'还没有填写简介'}}</p><span>{{profile.postCount}} 条公开帖子</span></div><p class="th-profile-privacy"><ShieldCheck :size="14"/>这里展示公开帖子，匿名发言不会出现在主页</p><TreeholePostCard v-for="post in profilePosts" :key="post.id" :post="post" :busy="busy" :reacting="pendingReactions[post.id+':like']" @open="openPost(post)" @discussion="openPost(post,true)" @react="react(post,$event)" @menu="menu=post.id" @image="imageView(post,$event)" @author="openProfile" @category="selectCategory"/><div v-if="!profilePosts.length" class="th-empty"><p>还没有公开帖子</p></div><button v-if="profileNext" class="th-more" :disabled="busy" @click="moreProfile">更多公开帖子</button></template>
      <form v-else-if="screen==='compose'" id="treehole-compose" class="th-compose" @submit.prevent="publish">
       <div class="th-compose-identity"><TreeholeAvatar :name="identity" :anonymous="anonymous" :size="36"/><div><strong>{{identity}}</strong><small>{{anonymous?'本帖使用独立匿名代号':'使用邯院通账号'}}</small></div><label class="th-anon-pill" :class="{selected:anonymous}"><input v-model="anonymous" type="checkbox" :disabled="busy"/><VenetianMask :size="17"/>匿名发布</label></div>
       <label class="th-zone-select">发布到<select v-model="postCategory" aria-label="选择分区" :disabled="busy"><option v-for="item in treeholeCategories" :key="item.id" :value="item.id">{{item.name}}</option></select></label>
       <input v-model="postTitle" class="th-title-input" aria-label="帖子标题" placeholder="添加标题（选填）" maxlength="40" :disabled="busy"/>
       <label class="th-editor-label"><span class="th-sr-only">想说的话</span><textarea v-model="body" maxlength="3000" rows="6" :required="!images.length" placeholder="分享校园里的新鲜事…" :disabled="busy"/></label>
       <div class="th-draft-images"><div v-for="(photo,index) in images" :key="photo.id" :class="{'is-selected':selectedPhoto===photo.id}"><button class="th-photo-select" type="button" :aria-label="'调整图片 '+(index+1)+' 顺序'" :aria-pressed="selectedPhoto===photo.id" @click="selectedPhoto=photo.id"><img :src="'data:image/jpeg;base64,'+photo.data" :alt="'待发布图片 '+(index+1)"/><span>{{index+1}}</span></button><button class="th-photo-remove" type="button" :aria-label="'移除图片 '+(index+1)" :disabled="busy" @click="removeImage(index)"><X :size="15"/></button></div><label v-if="imagesEnabled&&images.length<9" class="th-add-photo"><ImagePlus :size="25"/><span>{{images.length}} / 9</span><input type="file" accept="image/*" multiple aria-label="添加图片" :disabled="busy" @change="chooseImages"/></label></div>
       <div v-if="selectedPhoto&&images.some(i=>i.id===selectedPhoto)" class="th-photo-order"><span>调整第 {{images.findIndex(i=>i.id===selectedPhoto)+1}} 张</span><button type="button" :disabled="busy||images[0]?.id===selectedPhoto" @click="movePhoto(-1)"><ChevronLeft :size="18"/>前移</button><button type="button" :disabled="busy||images.at(-1)?.id===selectedPhoto" @click="movePhoto(1)">后移<ChevronRight :size="18"/></button></div>
       <p class="th-draft-status">{{draftSaved}}<span v-if="!imagesEnabled">图片服务连接后可添加配图</span></p>
       <div class="th-editor-footer"><span><MessageCircle :size="15"/> 友善表达，尊重隐私</span><span>{{body.length}} / 3000</span></div>
       <div class="th-compose-note"><ShieldCheck :size="17"/><p>{{anonymous?'其他同学看不到你的昵称和账号。本帖内的匿名回复使用同一代号。':'帖子会显示你的邯院通昵称。你也可以在上方开启匿名。'}} 发布后身份方式固定。</p></div>
      </form>
      <template v-else-if="screen==='detail'&&detail">
       <TreeholePostCard :post="detail" full :busy="busy" @open="focusReply()" @react="react(detail,$event)" @menu="menu=detail.id" @image="imageView(detail,$event)" @author="openProfile" @category="selectCategory"/>
       <div v-if="engagementEnabled" class="th-follow-discussion"><div><strong>{{detail.watching?'正在关注这段讨论':'想知道后续？'}}</strong><small>{{detail.watching?'新回复会出现在互动消息':'关注后，有新回复时提醒你'}}</small></div><button :aria-pressed="!!detail.watching" :disabled="busy||watchPending" @click="toggleWatch(detail)"><BellOff v-if="detail.watching" :size="17"/><Bell v-else :size="17"/>{{detail.watching?'取消关注':'关注讨论'}}</button></div>
       <div class="th-discussion-title"><h2>评论 <span aria-hidden="true">{{detail.commentCount}}</span></h2><span>按时间排序</span></div>
       <div v-if="detailError" class="th-detail-error" role="alert"><AlertCircle :size="18"/><div><strong>暂时没有加载完整</strong><p>{{detailError}}，当前正文已保留。</p></div><button :disabled="detailLoading" @click="loadDetail(detail!)">重试</button></div>
       <section v-if="focusedThread" class="th-focus-context" aria-label="消息对应的回复"><div class="th-context-heading"><span>消息对应的回复</span><button @click="focusedThread=null;scrollDiscussion()">查看全部讨论</button></div><TreeholeCommentThread :comment="focusedThread" :busy="busy" :locked="detail.locked" :expanded="true" :loading="loadingThreads[focusedThread.id]" :pending-likes="pendingLikes" :more="(focusedThread.replyCount||0)>(focusedThread.replies?.length||0)" @reply="focusReply" @like="commentLike" @menu="menu=$event.id" @expand="expandThread(focusedThread)"/></section>
       <div class="th-comments">
        <div v-if="detailLoading&&!comments.length" class="th-comment-loading" role="status"><span/><span/><span/><p>正在加载评论…</p></div>
        <div v-else-if="!comments.length&&!detailError" class="th-no-comments"><MessageCircle :size="25"/><strong>第一声回应，就从你开始</strong><p>一句关心、一个想法，都很好。</p></div>
        <TreeholeCommentThread v-for="comment in comments" :key="comment.id" :comment="comment" :busy="busy" :locked="detail.locked" :expanded="expandedReplies[comment.id]" :loading="loadingThreads[comment.id]" :pending-likes="pendingLikes" :more="!!replyPages[comment.id]" @reply="focusReply" @like="commentLike" @menu="menu=$event.id" @expand="expandThread(comment)" @collapse="expandedReplies[comment.id]=false"/>
       </div>
       <button v-if="commentNext" class="th-more" :disabled="busy||detailLoading" @click="loadDetail(detail!,true)">{{detailLoading?'正在加载…':'加载更多评论'}}</button>
       <p v-if="detail.locked" class="th-locked"><LockKeyhole :size="16"/>这条讨论已暂停回复。</p>

      </template>
      <template v-else-if="screen==='account'">
       <div class="th-profile"><TreeholeAvatar :name="user.nickname" :size="68"/><h2>{{user.nickname}}</h2><p><AtSign :size="13"/>{{user.username}}</p><span>邯院通账号 · 昵称由你决定</span></div>
       <p v-if="user.bannedUntil&&new Date(user.bannedUntil)>new Date()" class="th-alert">禁言至 {{date(user.bannedUntil)}}</p>
       <template v-if="accountAction==='overview'">
        <div class="th-profile-shortcuts"><button :disabled="busy" @click="accountFeed('mine')"><PenLine :size="22"/><strong>我的帖子</strong><small>记录校园里的日常</small></button><button :disabled="busy" @click="accountFeed('saved')"><Bookmark :size="22"/><strong>我的收藏</strong><small>留住喜欢的内容</small></button></div>
        <div v-if="engagementEnabled" class="th-profile-shortcuts"><button :disabled="busy" @click="accountFeed('participated')"><MessagesSquare :size="22"/><strong>我参与的</strong><small>把上次的话接着聊</small></button><button :disabled="busy" @click="showInbox"><Bell :size="22"/><strong>互动消息 <span v-if="unreadCount">{{unreadCount}}</span></strong><small>回应与讨论的后续</small></button></div>
        <section class="th-settings"><button :disabled="busy" @click="accountAction='profile'"><PenLine :size="19"/><span>修改昵称</span><ChevronRight :size="17"/></button><button :disabled="busy" @click="accountAction='password'"><LockKeyhole :size="19"/><span>修改密码与恢复码</span><ChevronRight :size="17"/></button><button :disabled="busy" @click="run(async()=>{await api('blocks.clear');feedNeedsRefresh=true;notice='已恢复屏蔽的内容'})"><Eye :size="19"/><span>恢复已屏蔽的内容</span><ChevronRight :size="17"/></button><button v-if="user.role==='moderator'" :disabled="busy" @click="moderate"><ShieldCheck :size="19"/><span>处理举报</span><ChevronRight :size="17"/></button></section>
        <button class="th-logout" :disabled="busy" @click="logout"><LogOut :size="17"/>退出邯院通账号</button><button class="th-account-delete" :disabled="busy" @click="accountAction='delete'">注销账号</button>
       </template>
       <form v-else class="th-card" @submit.prevent="saveAccount"><h3>{{accountAction==='profile'?'换个喜欢的昵称':accountAction==='password'?'更新账号密码':'注销邯院通账号'}}</h3><label v-if="accountAction==='profile'">公开昵称<input v-model="nickname" minlength="2" maxlength="20" required :disabled="busy"/></label><label v-if="accountAction==='profile'&&engagementEnabled">个人简介<textarea v-model="bio" maxlength="120" rows="3" placeholder="简单介绍自己（选填）" :disabled="busy"/></label><template v-if="accountAction!=='profile'"><label>当前密码<input v-model="password" type="password" autocomplete="current-password" required minlength="10" :disabled="busy"/></label><label v-if="accountAction==='password'">新密码<input v-model="newPassword" type="password" autocomplete="new-password" minlength="10" maxlength="128" required :disabled="busy"/></label><p v-else class="th-muted">注销将删除你的树洞帖子、评论和登录状态。学校课表保留。</p></template><button class="th-primary th-wide" :disabled="busy">{{accountAction==='delete'?'继续注销':'保存'}}</button></form>
      </template>
      <section v-else-if="screen==='moderate'"><div class="th-feed-intro"><h2>举报处理</h2><p>认真对待每一次反馈。</p></div><p v-if="!reports.length" class="th-empty">暂无待处理举报。</p><article v-for="r in reports" :key="r.id" class="th-card"><p class="th-full-body">{{r.body}}</p><p class="th-muted">举报原因：{{r.reason}}</p><div class="th-moderation-actions"><button v-for="(name,key) in {remove:'删除',lock:'锁帖',ban:'禁言 7 天',dismiss:'忽略'}" :key="key" :disabled="busy" @click="resolveReport(r,key)">{{name}}</button></div></article></section>
     </div>
    </template>
   </div>
   <button v-if="user&&screen==='feed'&&!recovery" class="th-fab" aria-label="发帖" :disabled="busy" @click="compose()"><PenLine :size="20"/>发树洞</button>
   <div v-if="user&&screen==='detail'&&detail&&!recovery" class="th-readbar" aria-label="帖子互动"><button class="th-reply-entry" :disabled="busy||detail.locked" @click="focusReply()"><PenLine :size="17"/><span>{{detail.locked?'讨论已暂停':commentBody?'继续编辑回复…':'说点什么吧…'}}</span></button><button class="th-read-action" :aria-label="detail.liked?'取消点赞':'点赞'" :aria-pressed="detail.liked" :disabled="busy||pendingReactions[detail.id+':like']" @click="react(detail,'like')"><ThumbsUp :size="21" :fill="detail.liked?'currentColor':'none'"/><span>{{detail.likeCount||'点赞'}}</span></button><button class="th-read-action" :aria-label="detail.saved?'取消收藏':'收藏'" :aria-pressed="detail.saved" :disabled="busy||pendingReactions[detail.id+':save']" @click="react(detail,'save')"><Bookmark :size="21" :fill="detail.saved?'currentColor':'none'"/><span>{{detail.saved?'已收藏':'收藏'}}</span></button><button class="th-read-action" aria-label="查看评论" @click="scrollDiscussion"><MessageCircle :size="21"/><span>{{detail.commentCount||'评论'}}</span></button></div>
  </div>
  <Transition :name="dialogMotion" @before-enter="(el:Element)=>{el.removeAttribute('inert');el.removeAttribute('aria-hidden')}" @before-leave="(el:Element)=>{el.setAttribute('inert','');el.setAttribute('aria-hidden','true')}">
  <div v-if="dialogOpen" class="th-dialog-backdrop" :class="{'is-gallery':!!gallery}" @click.self="!busy&&requestBack()">
   <section ref="dialogElement" class="th-dialog" :class="{'th-gallery':!!gallery,'th-reply-sheet':replyExpanded}" role="dialog" aria-modal="true" aria-label="树洞操作"><div class="th-sheet-grip"/>
    <template v-if="gallery"><div class="th-gallery-bar"><button class="th-icon" aria-label="关闭大图" @click="gallery=null"><X :size="23"/></button><span>{{gallery.index+1}} / {{gallery.post.images?.length}}</span><button class="th-icon" :aria-label="zoomed?'缩小图片':'放大图片'" @click="zoomed=!zoomed"><Search :size="22"/></button></div><div class="th-gallery-stage" :class="{zoomed}" @touchstart="galleryX=$event.touches[0].clientX" @touchend="imageGesture" @dblclick="zoomed=!zoomed"><img v-if="currentImage?.url&&!galleryFailed" :src="currentImage.url" alt="帖子原图" referrerpolicy="no-referrer" @error="galleryFailed=true"/><button v-else @click="renewImage">图片暂未加载，点击重试</button></div><div class="th-gallery-actions"><button :disabled="gallery.index===0" @click="galleryStep(-1)"><ChevronLeft :size="22"/>上一张</button><button :disabled="gallery.index===(gallery.post.images?.length||1)-1" @click="galleryStep(1)">下一张<ChevronRight :size="22"/></button></div></template>
    <form v-else-if="replyExpanded" class="th-reply-box" @submit.prevent="sendComment"><div class="th-editor-heading"><strong>{{reply?'回复 '+reply.author.name:'写评论'}}</strong><button type="button" class="th-icon" aria-label="收起回复编辑器" :disabled="busy" @click="closeReply"><X :size="20"/></button></div><div v-if="reply" class="th-reply-target"><span>{{reply.body}}</span><button type="button" aria-label="取消回复" :disabled="busy" @click="reply=null"><X :size="15"/></button></div><label class="th-reply-input"><span class="th-sr-only">你的回复</span><textarea ref="replyInput" v-model="commentBody" maxlength="1000" rows="4" required :disabled="busy" placeholder="说说你的想法…"/></label><div class="th-reply-bottom"><label class="th-anon-pill" :class="{selected:commentAnon||forceCommentAnon}"><input :checked="commentAnon||forceCommentAnon" type="checkbox" :disabled="busy||forceCommentAnon" @change="commentAnon=($event.target as HTMLInputElement).checked"/><VenetianMask :size="16"/>{{forceCommentAnon?'保持楼主匿名身份':'匿名回复'}}</label><small>{{commentBody.length}} / 1000</small><button class="th-send" :disabled="busy||!commentBody.trim()">发布回复<ArrowUp :size="16"/></button></div><p v-if="error" role="alert">{{error}}</p></form>
    <template v-else-if="discard"><span class="th-dialog-symbol"><PenLine :size="25"/></span><h3>放弃还没发布的文字？</h3><p>尚未发布的内容会被清除。</p><button class="th-primary th-wide" @click="discard=false">继续编辑</button><button v-if="screen==='compose'" class="th-more" :disabled="busy" @click="saveAndLeave">保存草稿并返回</button><button class="th-more" @click="leaveEditor">放弃并返回</button></template>
    <form v-else-if="reportTarget" @submit.prevent="submitReport"><span class="th-dialog-symbol"><Flag :size="25"/></span><h3>举报内容</h3><p>告诉我们发生了什么，管理员会认真查看。</p><label>原因<textarea v-model="reason" minlength="2" maxlength="300" rows="4" required :disabled="busy" placeholder="例如：泄露隐私、骚扰、垃圾广告"/></label><p v-if="error" role="alert">{{error}}</p><button class="th-primary th-wide" :disabled="busy">提交举报</button><button type="button" class="th-more" :disabled="busy" @click="reportTarget=null">取消</button></form>
    <template v-else-if="confirmAction"><span class="th-dialog-symbol"><ShieldCheck :size="25"/></span><h3>{{confirmAction.title}}</h3><p v-if="error" role="alert">{{error}}</p><button class="th-primary th-wide" :disabled="busy" @click="run(confirmAction!.run)">确认</button><button class="th-more" :disabled="busy" @click="confirmAction=null">取消</button></template>
    <template v-else-if="menu&&actionPost"><h3>{{actionComment?'评论操作':'帖子操作'}}</h3><div class="th-sheet-actions"><button v-if="(actionComment||actionPost).author.mine" :disabled="busy" @click="askDelete(actionPost,actionComment)"><Trash2 :size="20"/>{{actionComment?'删除评论':'删除帖子'}}</button><template v-else><button :disabled="busy" @click="report(actionPost,actionComment)"><Flag :size="20"/>举报</button><button :disabled="busy" @click="block(actionPost,actionComment)"><VolumeX :size="20"/>{{(actionComment?.author.anonymous??actionPost.anonymous)?'隐藏这条讨论':'屏蔽昵称发言'}}</button></template></div><button class="th-more" @click="menu=null">取消</button></template>
   </section>
  </div>
  </Transition>
 </section>
</template>
<style scoped src="./Treehole.css"></style>
