<script setup lang="ts">
import {ref,computed,onMounted,onUnmounted,onActivated,onDeactivated,watch,nextTick} from 'vue';
import {MessageCircle,Bookmark,ArrowLeft,ShieldCheck,Leaf,Search,X,PenLine,RefreshCw,ChevronRight,VenetianMask,LockKeyhole,LogOut,Eye,EyeOff,AlertCircle,Check,ArrowUp,Flag,Trash2,VolumeX,Sparkles,AtSign,ImagePlus,ChevronLeft,Bell,BellOff,MessagesSquare,ChevronDown,ChartNoAxesColumnIncreasing,CalendarPlus} from 'lucide-vue-next';
import TreeholeMessages from './TreeholeMessages.vue';
import TreeholeAdmin from './TreeholeAdmin.vue';
const moderationEnabled=ref(false),adminTarget=ref<{postId:string;commentId?:string|null}|null>(null);
import TreeholeUploadStatus from './TreeholeUploadStatus.vue';
import {uploadTreeholeImages,type TreeholeUploadProgress} from '../services/treeholeUpload';
import TreeholeInbox from './TreeholeInbox.vue';
import TreeholeBuddyEditor from './TreeholeBuddyEditor.vue';
import {buddyDraftValid,newBuddyDraft} from '../domain/treeholeBuddies';
import TreeholePollEditor from './TreeholePollEditor.vue';
import TreeholeFollowing from './TreeholeFollowing.vue';
import TreeholeFeedPage from './TreeholeFeedPage.vue';
import TreeholeCommentThread from './TreeholeCommentThread.vue';
import {treeholeDestinationName,treeholeFeedFilters,treeholeNewTopic,treeholeTopicCategory} from '../domain/treeholeCategories';
import {readTreeholeDraft,writeTreeholeDraft,deleteTreeholeDraft,prepareTreeholeImage,type DraftImage} from '../services/treeholeDrafts';
import TreeholeAvatar from './TreeholeAvatar.vue';
import TreeholeDestination from './TreeholeDestination.vue';
import TreeholeBoards from './TreeholeBoards.vue';
import TreeholeBoardPicker from './TreeholeBoardPicker.vue';
import TreeholeLike from './TreeholeLike.vue';
import TreeholePostCard from './TreeholePostCard.vue';
import {treeholeTimestamp} from '../domain/treeholePresentation';
import {treeholeRequest as request,treeholeError,treeholeErrorCode,type TreeholeResult,type TreeholeResponseKind,type TreeholeUser,type TreeholePost,type TreeholeComment,type TreeholeReport,type TreeholeNotification,type TreeholeProfile,type TreeholeFollow,type TreeholeSocial,type TreeholeMessageDraft,type TreeholePoll,type TreeholePollDraft,type TreeholeBuddy,type TreeholeBuddyDraft,type TreeholeBuddyMember} from '../services/treehole';

const props=withDefaults(defineProps<{tabRoot?:boolean}>(),{tabRoot:false});
const keyboardNavigation=ref(false),joyEnabled=ref(false),postInput=ref<HTMLTextAreaElement>();
function sizePostInput(){const el=postInput.value;if(!el)return;el.style.height='auto';el.style.height=Math.max(152,el.scrollHeight)+'px';}
const avatarsEnabled=ref(false),responsesEnabled=ref(false),avatarCandidate=ref<DraftImage|null>(null),pendingResponses=ref<Record<string,boolean>>({});
const pollsEnabled=ref(false),commentImagesEnabled=ref(false),pollDraft=ref<TreeholePollDraft|null>(null),commentImages=ref<DraftImage[]>([]),pendingVotes=ref<Record<string,boolean>>({});
const buddiesEnabled=ref(false),buddyDraft=ref<TreeholeBuddyDraft|null>(null),pendingBuddies=ref<Record<string,boolean>>({});
const buddySnapshots=new Map<string,TreeholeBuddy>();
const buddyValid=computed(()=>!buddyDraft.value||postCategory.value==='buddies'&&!pollDraft.value&&!!body.value.trim()&&buddyDraftValid(buddyDraft.value));
const buddyRoster=ref<{post:TreeholePost;members:TreeholeBuddyMember[];loading:boolean;error:string}|null>(null);
const pollSnapshots=new Map<string,TreeholePoll>();
async function api(action:string,payload:Record<string,unknown>={}){const epoch=accountEpoch,r=await request(action,boardsEnabled.value?{...payload,boardTopics:true}:payload);if(epoch===accountEpoch){for(const p of [...(r.posts||[]),...(r.post?[r.post]:[])]){if(p.buddy){const known=buddySnapshots.get(p.id);if(known&&known.version>p.buddy.version)p.buddy=known;else buddySnapshots.set(p.id,p.buddy);}if(!p.poll)continue;const known=pollSnapshots.get(p.id);if(known&&known.version>p.poll.version)p.poll=known;else pollSnapshots.set(p.id,p.poll);}}return r;}
const pollValid=computed(()=>!pollDraft.value||!!pollDraft.value.question.trim()&&pollDraft.value.question.trim().length<=80&&pollDraft.value.options.length>=2&&pollDraft.value.options.length<=6&&pollDraft.value.options.every(x=>!!x.trim()&&x.trim().length<=40)&&new Set(pollDraft.value.options.map(x=>x.trim().toLowerCase())).size===pollDraft.value.options.length);
const socialEnabled=ref(false),messagesEnabled=ref(false),social=ref<TreeholeSocial|null>(null),socialError=ref(''),peopleKind=ref('following'),messageUnread=ref(0),messageTitle=ref('私信'),messageMember=ref<string>(),messageDrafts=ref<Record<string,TreeholeMessageDraft>>({}),messagesView=ref<InstanceType<typeof TreeholeMessages>>();
const followingEnabled=ref(false),following=ref<TreeholeFollow[]>([]),followingNext=ref<Record<string,string>|null>(null),followingLoading=ref(false),followingError=ref(''),pendingFollows=ref<Record<string,boolean>>({});
let followingRevision=0;
const followingRetryMore=ref(false);
const discoveryEnabled=ref(false),boardsEnabled=ref(false),interest=ref(''),postInterest=ref('');
const boardPicker=ref<'compose'|'interests'|null>(null);
const boardPrompts:Record<string,string>={
 graduate:'可以分享你的择校经历、复习方法或备考进度。',
 reading:'读到一本想聊的书，可以从一条读书笔记开始。',
 fitness:'可以分享训练记录，或问问同学怎么练。',
};
const boardPrompt=computed(()=>boardPrompts[interest.value]);
const boardName=computed(()=>treeholeDestinationName(category.value,interest.value));
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
let draftRevision=0;
const postUpload=ref<TreeholeUploadProgress|null>(null),commentUpload=ref<TreeholeUploadProgress|null>(null);
let draftQueue=Promise.resolve(),draftTimer:ReturnType<typeof setTimeout>|undefined;
const emit=defineEmits<{exit:[];tabNavigation:[visible:boolean]}>();
const searchOpen=ref(false),showPassword=ref(false),replyInput=ref<HTMLTextAreaElement>(),searchInput=ref<HTMLInputElement>();
const dialogElement=ref<HTMLElement>(),dialogMotion=ref('th-sheet-motion');
const user=ref<TreeholeUser|null>(null),busy=ref(false),ready=ref(false),error=ref(''),notice=ref('');
const registration=ref(false),combinedUnread=ref(false),auth=ref<'login'|'register'|'recover'>('login');
const username=ref(''),password=ref(''),nickname=ref(''),optionalRecovery=ref(''),recoveryInput=ref(''),recovery=ref('');
type Screen='feed'|'compose'|'detail'|'account'|'moderate'|'inbox'|'profile'|'following'|'messages';
const screen=ref<Screen>('feed');
const engagementEnabled=ref(false),unreadCount=ref(0),notifications=ref<TreeholeNotification[]>([]),inboxFilter=ref('all'),inboxLoading=ref(false),inboxError=ref(''),inboxNext=ref<Record<string,string>|null>(null);
const profile=ref<TreeholeProfile|null>(null),profilePosts=ref<TreeholePost[]>([]),profileNext=ref<Record<string,string>|null>(null),bio=ref('');
const focusedThread=ref<TreeholeComment|null>(null),focusedCommentId=ref(''),watchPending=ref(false);
let lastUnreadAt=-Infinity,inboxRevision=0,unreadBusy=false,unreadTimer:ReturnType<typeof setInterval>|undefined;
const routeHistory:Array<{screen:Screen;scroll:number;detail:TreeholePost|null;comments:TreeholeComment[];commentNext:Record<string,string>|null;profile:TreeholeProfile|null;profilePosts:TreeholePost[];profileNext:Record<string,string>|null;context:TreeholeComment|null}>=[];
const scopeLabels:Record<string,string>={joined:'我报名的',mine:'我的帖子',saved:'我的收藏',participated:'我参与的',watching:'关注的讨论',following:'关注动态'};
const posts=ref<TreeholePost[]>([]),scope=ref('all'),query=ref(''),feedNext=ref<Record<string,string>|null>(null);
const browseScope=computed(()=>scope.value==='all'||scope.value==='following');
const continueScope=ref('participated'),fabCollapsed=ref(false);
const continuing=computed(()=>['participated','watching'].includes(scope.value));
watch(scope,next=>{if(['participated','watching'].includes(next))continueScope.value=next;});
let feedScrollSample=0;
watch(screen,()=>{fabCollapsed.value=false;feedScrollSample=0;});
const feedLoadingMore=ref(false),feedPageError=ref(''),feedRevision=ref(0);
let appliedFeedKey='',feedNeedsRefresh=false;
const detail=ref<TreeholePost|null>(null),comments=ref<TreeholeComment[]>([]),commentNext=ref<Record<string,string>|null>(null),reply=ref<TreeholeComment|null>(null);
const body=ref(''),anonymous=ref(false),commentBody=ref(''),commentAnon=ref(false),postKey=ref<string>(crypto.randomUUID()),commentKey=ref<string>(crypto.randomUUID());
const reports=ref<TreeholeReport[]>([]),newPassword=ref(''),accountAction=ref<'overview'|'profile'|'password'|'delete'>('overview');
const menu=ref<string|null>(null),reportTarget=ref<{postId:string;commentId?:string}|null>(null),reason=ref(''),discard=ref(false);
const confirmAction=ref<{title:string;run:()=>Promise<void>}|null>(null);
let alive=true,active=true;
const identity=computed(()=>anonymous.value?'匿名同学':user.value?.nickname||'邯院通昵称');
const forceCommentAnon=computed(()=>detail.value?.category==='treehole'||!!detail.value?.anonymous&&!!detail.value?.author.mine);
function date(value:string){return treeholeTimestamp(value);}
const title=computed(()=>({compose:'发帖',detail:'帖子详情',account:'我的社区',moderate:'社区管理',inbox:'互动消息',profile:'同学主页',following:peopleKind.value==='followers'?'我的粉丝':'我关注的人',messages:messageTitle.value,feed:'邯院社区'})[screen.value]);
const dialogOpen=computed(()=>!!(boardPicker.value||buddyRoster.value||menu.value||confirmAction.value||reportTarget.value||discard.value||gallery.value||replyExpanded.value));
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
function accountFeed(next:string){if(busy.value)return;const old={scope:scope.value,query:query.value,category:category.value,interest:interest.value,sort:sort.value,screen:screen.value},epoch=accountEpoch;scope.value=next;query.value='';category.value='all';interest.value='';sort.value='latest';screen.value='feed';void run(async()=>{try{await feed();if(epoch===accountEpoch)routeHistory.length=0;}catch(e){if(epoch===accountEpoch){scope.value=old.scope;query.value=old.query;category.value=old.category;interest.value=old.interest;sort.value=old.sort;screen.value=old.screen;}throw e;}});}
function selectCategory(next:string,topic=''){
 if(busy.value)return;
 if(screen.value==='detail'&&(commentBody.value.trim()||commentImages.value.length)){error.value='请先发布回复，或返回时选择放弃';return;}
 if(screen.value==='feed'&&browseScope.value&&category.value===next&&interest.value===topic)return;
 const previous={category:category.value,interest:interest.value,scope:scope.value},epoch=accountEpoch;
 category.value=next;interest.value=topic;if(scope.value!=='following')scope.value='all';screen.value='feed';detail.value=null;
 void run(async()=>{try{await feed();}catch(e){if(epoch===accountEpoch){category.value=previous.category;interest.value=previous.interest;scope.value=previous.scope;}throw e;}});
}
function selectInterest(next:string){selectCategory(treeholeTopicCategory(next),treeholeNewTopic(next)&&!boardsEnabled.value?'':next);}
function pickBoard(next:string,topic:string){
 const from=boardPicker.value;
 boardPicker.value=null;
 if(from==='compose'){postCategory.value=next;postInterest.value=topic;}
 else if(from==='interests')selectCategory(next,topic);
}
function setSort(next:string){if(busy.value)return;sort.value=next;if(scope.value!=='following')scope.value='all';void run(()=>feed());}
function windowTop(){scrollIntentUntil=performance.now()+650;detailTab.value="body";window.scrollTo({top:0,behavior:scrollBehavior()});}
function scrollDiscussion(){scrollIntentUntil=performance.now()+650;detailTab.value='comments';document.querySelector('.th-discussion-title')?.scrollIntoView({behavior:scrollBehavior(),block:'start'});}
function trackDetailScroll(){cancelAnimationFrame(scrollFrame);scrollFrame=requestAnimationFrame(()=>{if(screen.value==='feed'&&!dialogOpen.value){const y=Math.max(0,window.scrollY),delta=y-feedScrollSample;if(y<80){fabCollapsed.value=false;feedScrollSample=y;}else if(Math.abs(delta)>14){fabCollapsed.value=delta>0;feedScrollSample=y;}return;}if(screen.value!=='detail'||performance.now()<scrollIntentUntil)return;const heading=document.querySelector('.th-discussion-title'),nav=document.querySelector('.th-nav');if(!heading||!nav)return;const top=heading.getBoundingClientRect().top;if(window.scrollY<8)detailTab.value='body';else if(top<=nav.getBoundingClientRect().bottom+24)detailTab.value='comments';else if(top>window.innerHeight*.7)detailTab.value='body';});}
async function restoreDraft(){if(!user.value)return;draftReady.value=false;try{const d=await readTreeholeDraft(user.value.id);if(d){postTitle.value=d.title;body.value=d.body;postCategory.value=d.category;postInterest.value=d.interest||'';anonymous.value=d.category==='treehole'||d.anonymous;postKey.value=d.requestId;images.value=d.images;pollDraft.value=d.poll||null;buddyDraft.value=d.buddy||null;}}catch{draftSaved.value='草稿暂时无法读取';}finally{draftReady.value=true;}}
function saveDraft():Promise<boolean>{
 if(!draftReady.value||!user.value)return Promise.resolve(false);
 const id=user.value.id,epoch=accountEpoch,revision=draftRevision;let saved=false;
 const snapshot=JSON.parse(JSON.stringify({title:postTitle.value,body:body.value,category:postCategory.value,interest:postInterest.value,anonymous:anonymous.value,requestId:postKey.value,images:images.value,poll:pollDraft.value,buddy:buddyDraft.value}));
 const current=()=>alive&&epoch===accountEpoch&&revision===draftRevision;
 if(current())draftSaved.value='保存中…';
 draftQueue=draftQueue.then(()=>snapshot.title||snapshot.body||snapshot.images.length||snapshot.poll||snapshot.buddy?writeTreeholeDraft(id,snapshot):deleteTreeholeDraft(id)).then(()=>{
  saved=true;if(current())draftSaved.value='草稿已保存';
 }).catch(()=>{if(current())draftSaved.value='草稿保存失败，请保留当前页面';});
 return draftQueue.then(()=>saved);
}
function retryDraft(){clearTimeout(draftTimer);void saveDraft();}
function saveAndLeave(){void run(async()=>{clearTimeout(draftTimer);if(!await saveDraft()){error.value='草稿未保存，请继续编辑后重试';return;}discard.value=false;screen.value='feed';});}
async function clearDraft(){draftRevision++;postUpload.value=null;clearTimeout(draftTimer);draftReady.value=false;const id=user.value?.id;postTitle.value='';body.value='';postInterest.value='';images.value=[];pollDraft.value=null;buddyDraft.value=null;draftSaved.value='';await draftQueue;try{if(id)await deleteTreeholeDraft(id);}catch{draftSaved.value='本地草稿清理失败';}finally{draftReady.value=true;}}
watch(body,()=>{if(screen.value==='compose')void nextTick(sizePostInput);});
watch(screen,next=>{if(next==='compose')void nextTick(sizePostInput);});
watch([postTitle,body,postCategory,postInterest,anonymous,images,pollDraft,buddyDraft],()=>{if(screen.value==='compose'&&draftReady.value){draftRevision++;draftSaved.value='保存中…';clearTimeout(draftTimer);draftTimer=setTimeout(saveDraft,180);}},{deep:true});
watch(postCategory,(next)=>{if(next==='treehole')anonymous.value=true;if(postInterest.value&&treeholeTopicCategory(postInterest.value)!==next)postInterest.value='';});
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
watch(notice,()=>{clearTimeout(noticeTimer);if(notice.value)noticeTimer=setTimeout(()=>{notice.value='';},2600);});
watch(dialogOpen,async(open)=>{if(open){dialogMotion.value=gallery.value?'th-gallery-motion':'th-sheet-motion';previousFocus=document.activeElement as HTMLElement;previousOverflow=document.body.style.overflow;document.body.style.overflow='hidden';await nextTick();if(replyExpanded.value)replyInput.value?.focus();else dialogElement.value?.querySelector<HTMLElement>('button,input,textarea')?.focus();}else{document.body.style.overflow=previousOverflow;await nextTick();previousFocus?.focus({preventScroll:true});}});
watch([buddyRoster,menu,reportTarget,confirmAction,discard,gallery],async()=>{if(dialogOpen.value){await nextTick();if(replyExpanded.value)replyInput.value?.focus();else dialogElement.value?.querySelector<HTMLElement>('button,input,textarea')?.focus();}});
function trapKeys(event:KeyboardEvent){if(!dialogOpen.value)return;if(event.key==='Escape'){event.stopImmediatePropagation();event.preventDefault();requestBack();}if(event.key==='Tab'){const controls=Array.from(dialogElement.value?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),textarea:not(:disabled)')||[]);const first=controls[0],last=controls.at(-1);if(!first){event.preventDefault();return;}if(event.shiftKey&&document.activeElement===first){last?.focus();event.preventDefault();}else if(!event.shiftKey&&document.activeElement===last){first.focus();event.preventDefault();}}}
async function run(work:()=>Promise<void>){
 if(busy.value)return;busy.value=true;error.value='';notice.value='';
 try{await work();}catch(e){if(alive){error.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired'){clearAccount();}}}
 finally{if(alive)busy.value=false;}
}
function clearAccount(){optionalRecovery.value='';lastUnreadAt=-Infinity;boardPicker.value=null;draftRevision++;postUpload.value=null;commentUpload.value=null;social.value=null;socialError.value='';peopleKind.value='following';messageUnread.value=0;messageDrafts.value={};messageMember.value=undefined;continueScope.value='participated';fabCollapsed.value=false;buddySnapshots.clear();pendingBuddies.value={};buddyDraft.value=null;buddyRoster.value=null;pollSnapshots.clear();pendingVotes.value={};pollDraft.value=null;commentImages.value=[];followingRevision++;following.value=[];followingNext.value=null;followingLoading.value=false;followingError.value='';pendingFollows.value={};scope.value='all';query.value='';avatarCandidate.value=null;pendingResponses.value={};accountEpoch++;inboxRevision++;inboxLoading.value=false;inboxError.value='';notifications.value=[];unreadCount.value=0;inboxNext.value=null;profile.value=null;profilePosts.value=[];profileNext.value=null;focusedThread.value=null;focusedCommentId.value='';routeHistory.length=0;restoringScroll=null;watchPending.value=false;bio.value='';detailRequest++;detailEpoch++;detailLoading.value=false;detailError.value='';feedRevision.value++;feedLoadingMore.value=false;feedPageError.value='';feedNext.value=null;commentNext.value=null;appliedFeedKey='';feedNeedsRefresh=false;feedScroll=0;feedAnchor=null;pendingReactions.value={};pendingLikes.value={};loadingThreads.value={};loadedThreads.clear();replyExpanded.value=false;draftReady.value=false;postTitle.value='';images.value=[];category.value='all';interest.value='';sort.value='latest';showPassword.value=false;searchOpen.value=false;auth.value='login';user.value=null;posts.value=[];detail.value=null;comments.value=[];body.value='';commentBody.value='';commentImages.value=[];reply.value=null;recovery.value='';password.value='';newPassword.value='';recoveryInput.value='';screen.value='feed';menu.value=null;reportTarget.value=null;}
function feedCriteria(){return {scope:scope.value,query:query.value,...treeholeFeedFilters(category.value,interest.value,discoveryEnabled.value),sort:sort.value};}
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
  return {...post,...(pendingReactions.value[post.id+':like']?{liked:cached.liked,likeCount:cached.likeCount}:{}),...(pendingReactions.value[post.id+':save']?{saved:cached.saved}:{}),...(pendingResponses.value[post.id]?{myResponse:cached.myResponse,responseCounts:cached.responseCounts}:{})};
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
 if(previous.screen==='following')void loadFollowing();if(previous.screen==='account')void refreshSocial();
}
async function refreshUnread(){
 if(!engagementEnabled.value||!user.value||!active||document.hidden||unreadBusy||Date.now()-lastUnreadAt<180000)return;
 const epoch=accountEpoch;unreadBusy=true;lastUnreadAt=Date.now();
 try{const r=await api('notifications.unread',combinedUnread.value?{withMessages:true}:{});if(alive&&epoch===accountEpoch)unreadCount.value=r.unreadCount??0;if(alive&&epoch===accountEpoch&&typeof r.messageUnreadCount==='number')messageUnread.value=r.messageUnreadCount;else if(alive&&epoch===accountEpoch&&messagesEnabled.value){const dm=await api('messages.unread');if(alive&&epoch===accountEpoch)messageUnread.value=dm.messageUnreadCount||0;}}
 catch(e){if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);}
 finally{unreadBusy=false;}
}
async function loadInbox(more=false){
 if(inboxLoading.value||!user.value)return;
 const epoch=accountEpoch,revision=++inboxRevision,filter=inboxFilter.value;
 inboxLoading.value=true;inboxError.value='';
 try{const r=await api('notifications.list',{filter,...(combinedUnread.value?{withMessages:true}:{}),...(more?inboxNext.value:{})});if(!alive||epoch!==accountEpoch||revision!==inboxRevision)return;notifications.value=more?appendUnique(notifications.value,r.notifications||[]):r.notifications||[];inboxNext.value=r.next||null;unreadCount.value=r.unreadCount??0;if(alive&&epoch===accountEpoch&&typeof r.messageUnreadCount==='number')messageUnread.value=r.messageUnreadCount;else if(alive&&epoch===accountEpoch&&messagesEnabled.value){const dm=await api('messages.unread');if(alive&&epoch===accountEpoch)messageUnread.value=dm.messageUnreadCount||0;}}
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
 commentBody.value='';commentImages.value=[];reply.value=null;commentAnon.value=false;commentKey.value=crypto.randomUUID();screen.value='detail';detailTab.value=item.commentId?'comments':'body';
 try{await markNotifications([item.id]);}catch(e){actionError(e,epoch);}
});}
function openProfile(memberId:string){if(!engagementEnabled.value||(screen.value==='profile'&&profile.value?.id===memberId))return;void run(async()=>{
 const epoch=accountEpoch;
 const [p,r]=await Promise.all([api('profile.get',{memberId}),api('posts.list',{scope:'author',memberId})]);if(!alive||epoch!==accountEpoch||!p.profile)return;
 rememberRoute();if(memberId===user.value?.id)void refreshSocial();profile.value=p.profile;profilePosts.value=r.posts||[];profileNext.value=r.next||null;screen.value='profile';
});}
function moreProfile(){if(!profile.value||!profileNext.value)return;void run(async()=>{
 const epoch=accountEpoch,id=profile.value!.id,r=await api('posts.list',{scope:'author',memberId:id,...profileNext.value});if(epoch!==accountEpoch||profile.value?.id!==id)return;
 profilePosts.value=appendUnique(profilePosts.value,r.posts||[]);profileNext.value=r.next||null;
});}
function showMessages(memberId?:string){if(busy.value||!messagesEnabled.value)return;rememberRoute();messageMember.value=memberId;messageTitle.value='私信';screen.value='messages';}
async function refreshSocial(){if(!socialEnabled.value||!user.value)return;const epoch=accountEpoch;try{const r=await api('follows.stats');if(alive&&epoch===accountEpoch){social.value=r.social||null;socialError.value='';}}catch(e){if(alive&&epoch===accountEpoch){socialError.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);}}}
function showFollowing(kind='following'){if(busy.value||!followingEnabled.value)return;rememberRoute();if(peopleKind.value!==kind){followingRevision++;followingLoading.value=false;following.value=[];followingNext.value=null;}peopleKind.value=kind;screen.value='following';void loadFollowing();}
async function loadFollowing(more=false){
 if(followingLoading.value||!user.value||(more&&!followingNext.value))return;
 const epoch=accountEpoch,revision=++followingRevision;followingLoading.value=true;followingError.value='';followingRetryMore.value=more;
 try{const r=await api(peopleKind.value==='followers'?'followers.list':'follows.list',more?{...followingNext.value}:{});if(!alive||epoch!==accountEpoch||revision!==followingRevision)return;following.value=more?appendUnique(following.value,(peopleKind.value==='followers'?r.followers:r.following)||[]):(peopleKind.value==='followers'?r.followers:r.following)||[];followingNext.value=r.next||null;}
 catch(e){if(alive&&epoch===accountEpoch&&revision===followingRevision){if(treeholeErrorCode(e)==='session_expired')actionError(e,epoch);else followingError.value=treeholeError(e);}}
 finally{if(epoch===accountEpoch&&revision===followingRevision)followingLoading.value=false;}
}
async function setFollow(memberId:string,enabled:boolean){
 if(busy.value||pendingFollows.value[memberId]||!followingEnabled.value)return;
 const epoch=accountEpoch;error.value='';pendingFollows.value={...pendingFollows.value,[memberId]:true};
 try{const r=await api('follows.set',{memberId,enabled});if(!alive||epoch!==accountEpoch)return;
  if(profile.value?.id===memberId)profile.value={...(r.profile||profile.value),following:enabled};
  for(const frame of routeHistory)if(frame.profile?.id===memberId)frame.profile={...frame.profile,following:enabled};
  followingRevision++;followingLoading.value=false;if(peopleKind.value==='followers')following.value=following.value.map(p=>p.id===memberId?{...p,following:enabled}:p);else if(!enabled)following.value=following.value.filter(p=>p.id!==memberId);void refreshSocial();
  if(scope.value==='following'){feedRevision.value++;feedLoadingMore.value=false;feedNext.value=null;feedNeedsRefresh=true;if(!enabled)posts.value=posts.value.filter(p=>p.author.id!==memberId);}
  notice.value=enabled?'已关注，可以在关注动态里看 TA 的公开分享':'已取消关注';
 }catch(e){actionError(e,epoch);}finally{if(epoch===accountEpoch){const next={...pendingFollows.value};delete next[memberId];pendingFollows.value=next;}}
}
async function toggleWatch(post:TreeholePost){
 if(watchPending.value||busy.value)return;const epoch=accountEpoch;watchPending.value=true;
 try{const r=await api('threads.watch',{postId:post.id,enabled:!post.watching});if(!alive||epoch!==accountEpoch||!r.post)return;for(const cached of [...posts.value,...profilePosts.value])if(cached.id===post.id)cached.watching=r.post.watching;if(detail.value?.id===post.id)detail.value.watching=r.post.watching;notice.value=r.post.watching?'已关注，有新回复时会出现在互动消息':'已取消关注，直接回复你仍会提醒';if(scope.value==='watching')feedNeedsRefresh=true;void refreshUnread();}
 catch(e){actionError(e,epoch);}finally{if(epoch===accountEpoch)watchPending.value=false;}
}
function applyConfig(config:TreeholeResult){
 registration.value=config.registrationEnabled===true&&config.simpleRegistration===true;
 combinedUnread.value=config.combinedUnread===true;
 imagesEnabled.value=!!config.imagesEnabled;engagementEnabled.value=!!config.engagementEnabled;avatarsEnabled.value=!!config.avatarsEnabled;responsesEnabled.value=!!config.responsesEnabled;joyEnabled.value=config.responseKinds?.includes('joy')===true;discoveryEnabled.value=!!config.discoveryEnabled;boardsEnabled.value=discoveryEnabled.value&&config.boardsEnabled===true;followingEnabled.value=!!config.followingEnabled;socialEnabled.value=!!config.socialEnabled;messagesEnabled.value=!!config.messagesEnabled;pollsEnabled.value=!!config.pollsEnabled;buddiesEnabled.value=!!config.buddiesEnabled;commentImagesEnabled.value=!!config.commentImagesEnabled;moderationEnabled.value=!!config.moderationEnabled;
}
async function initialize(){await run(async()=>{
 let entry:TreeholeResult|undefined;
 try{entry=await api('me',{entry:true,boardTopics:true})}catch(e){if(treeholeErrorCode(e)!=='session_expired')throw e}
 if(!alive)return;
 const config=entry?.config??await api('config');
 if(!alive)return;
 applyConfig(config);ready.value=true;
 if(!entry?.user)return;
 user.value=entry.user;nickname.value=entry.user.nickname;
 if(entry.config&&Array.isArray(entry.posts)){
  posts.value=entry.posts;feedNext.value=entry.next??null;appliedFeedKey=feedKey();feedNeedsRefresh=false;
  await restoreDraft();
 }else await Promise.all([feed(),restoreDraft()]);
 void refreshUnread();
});}
function authenticate(){void run(async()=>{
 const mode=auth.value;
 const payload={username:username.value,password:password.value,...(mode==='register'?{agreed:true}:{}),...(mode==='recover'?{recoveryCode:recoveryInput.value}:{})};
 const r=await api(mode,payload);
 password.value='';recoveryInput.value='';if(!alive||!r.user)return;
 user.value=r.user;nickname.value=r.user.nickname;optionalRecovery.value=mode==='register'?r.recoveryCode||'':'';
 recovery.value=mode==='recover'?r.recoveryCode||'':'';screen.value='feed';posts.value=[];scope.value='all';query.value='';
 await Promise.all([feed(),restoreDraft()]);void refreshUnread();
});}
function changeScope(next:string){if(busy.value)return;scope.value=next;if(next==='all')sort.value='latest';void run(()=>feed());}
function compose(anon=false){postUpload.value=null;replyExpanded.value=false;reply.value=null;commentBody.value='';commentImages.value=[];commentAnon.value=false;commentKey.value=crypto.randomUUID();if(!body.value&&!postTitle.value&&!images.value.length&&!pollDraft.value&&!buddyDraft.value){anonymous.value=anon||category.value==='treehole';postCategory.value=category.value==='all'?'daily':category.value;postInterest.value=interest.value;postKey.value=crypto.randomUUID();}screen.value='compose';error.value='';}

async function loadDetail(post:TreeholePost,more=false){
 const epoch=accountEpoch,request=++detailRequest;
 detailLoading.value=true;detailError.value='';
 try{
  const r=await api('posts.get',{postId:post.id,threaded:true,...(more?commentNext.value:{})});
  if(!alive||epoch!==accountEpoch||request!==detailRequest||screen.value!=='detail'||detail.value?.id!==post.id)return;
  if(!r.post)throw Error('post_not_found');
  const fresh={...r.post,...(pendingReactions.value[post.id+':like']?{liked:detail.value.liked,likeCount:detail.value.likeCount}:{}),...(pendingReactions.value[post.id+':save']?{saved:detail.value.saved}:{}),...(pendingResponses.value[post.id]?{myResponse:detail.value.myResponse,responseCounts:detail.value.responseCounts}:{})};
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
 commentUpload.value=null;screen.value='detail';detailTab.value=discussion?'comments':'body';replyExpanded.value=false;commentBody.value='';commentImages.value=[];reply.value=null;commentAnon.value=false;commentKey.value=crypto.randomUUID();menu.value=null;error.value='';
 void loadDetail(post);
}
function publish(){void run(async()=>{
 if(buddyDraft.value&&(!buddiesEnabled.value||!buddyValid.value)){error.value='请补全搭子说明、地点、人数和未来 90 天内的时间，草稿已保留';return;}
 if(pollDraft.value&&(!pollsEnabled.value||!pollValid.value)){error.value='请填写投票问题和不同的选项，草稿已保留';return;}
 const epoch=accountEpoch,current=()=>alive&&epoch===accountEpoch;
 if((!discoveryEnabled.value&&['entertainment','treehole'].includes(postCategory.value))||(!boardsEnabled.value&&treeholeNewTopic(postInterest.value))){error.value='这个分区暂不可用，草稿已保留，请稍后重试';return;}
 try{
  if(!await uploadTreeholeImages(images.value,'post',api,p=>postUpload.value=p,current,()=>{void saveDraft();}))return;
  const r=await api('posts.create',{buddy:buddyDraft.value,poll:pollDraft.value,title:postTitle.value,category:postCategory.value,interest:postInterest.value,images:images.value.map(i=>i.remote!.id),body:body.value,anonymous:postCategory.value==='treehole'||anonymous.value,requestId:postKey.value});
  if(!current())return;
  await clearDraft();postKey.value=crypto.randomUUID();feedNeedsRefresh=true;feedScroll=0;feedAnchor=null;detail.value=r.post!;comments.value=[];screen.value='detail';detailTab.value='body';replyExpanded.value=false;await loadDetail(r.post!);notice.value='已发布';
 }catch(e){
  if(current()){
   if(treeholeErrorCode(e)==='image_unavailable'){for(const image of images.value){image.remote=undefined;image.id=crypto.randomUUID();}void saveDraft();}
   postUpload.value={phase:'failed',completed:images.value.filter(i=>i.remote).length,total:images.value.length,currentId:postUpload.value?.currentId};
  }
  throw e;
 }
});}

async function chooseCommentImages(event:Event){const input=event.target as HTMLInputElement,files=Array.from(input.files||[]);input.value='';if(commentImages.value.length+files.length>3){error.value='评论最多添加 3 张图片';return;}const epoch=accountEpoch,postId=detail.value?.id;await run(async()=>{for(const file of files){const prepared=await prepareTreeholeImage(file);if(epoch!==accountEpoch||detail.value?.id!==postId)return;commentImages.value.push(prepared);}});}
function removeCommentImage(index:number){const old=commentImages.value.splice(index,1)[0];if(old?.remote)void api('media.discard',{imageId:old.remote.id}).catch(()=>{});}
function commentImageView(comment:TreeholeComment,index:number){if(detail.value)imageView({...detail.value,images:comment.images},index);}
function sendComment(){if(!detail.value)return;const post=detail.value,epoch=accountEpoch;void run(async()=>{
 if(commentImages.value.length&&!commentImagesEnabled.value){error.value='评论图片暂不可用，已保留当前回复';return;}
 const photos=[...commentImages.value],current=()=>alive&&epoch===accountEpoch&&detail.value?.id===post.id;
 try{
  if(!await uploadTreeholeImages(photos,'comment',api,p=>commentUpload.value=p,current))return;
  await api('comments.create',{postId:post.id,images:photos.map(i=>i.remote!.id),body:commentBody.value,anonymous:commentAnon.value||forceCommentAnon.value,requestId:commentKey.value,replyTo:reply.value?.id||null});
 }catch(e){
  if(current()){
   if(treeholeErrorCode(e)==='image_unavailable'){for(const image of photos){image.remote=undefined;image.id=crypto.randomUUID();}}
   commentUpload.value={phase:'failed',completed:photos.filter(i=>i.remote).length,total:photos.length,currentId:commentUpload.value?.currentId};
  }
  throw e;
 }
 if(!current())return;
 commentUpload.value=null;closeReply();commentBody.value='';commentImages.value=[];reply.value=null;commentKey.value=crypto.randomUUID();await loadDetail(post);notice.value='回复已发布';
});}

function applyBuddy(post:TreeholePost,buddy:TreeholeBuddy){
 buddySnapshots.set(post.id,buddy);for(const p of [post,...posts.value,...profilePosts.value,...routeHistory.flatMap(r=>[...(r.detail?[r.detail]:[]),...r.profilePosts]),...(detail.value?[detail.value]:[]),...(buddyRoster.value?[buddyRoster.value.post]:[])])if(p.id===post.id)p.buddy=buddy;
}
async function buddyAction(post:TreeholePost,action:'join'|'close',enabled:boolean){
 const epoch=accountEpoch;if(!buddiesEnabled.value||busy.value||pendingBuddies.value[post.id])return;pendingBuddies.value[post.id]=true;error.value='';
 try{const r=await api('buddies.'+action,{postId:post.id,...(action==='join'?{enabled}:{closed:enabled})});if(alive&&epoch===accountEpoch&&r.post?.buddy){applyBuddy(post,r.post.buddy);feedNeedsRefresh=true;notice.value=action==='join'?(enabled?'报名成功，可在「我报名的」找到这条讨论':'已退出报名'):(enabled?'已结束招募':'已重新开放招募');}}
 catch(e){if(epoch===accountEpoch&&['buddy_full','buddy_closed','post_locked'].includes(treeholeErrorCode(e)||'')){try{const fresh=await api('posts.get',{postId:post.id});if(alive&&epoch===accountEpoch&&fresh.post?.buddy)applyBuddy(post,fresh.post.buddy);}catch{}}actionError(e,epoch);}
 finally{if(epoch===accountEpoch)delete pendingBuddies.value[post.id];}
}
async function showBuddyMembers(post:TreeholePost){
 if(!post.author.mine||busy.value)return;const epoch=accountEpoch;
 if(buddyRoster.value?.post.id!==post.id)buddyRoster.value={post,members:[],loading:false,error:''};
 const roster=buddyRoster.value;if(!roster||roster.loading)return;roster.loading=true;roster.error='';
 try{const r=await api('buddies.members',{postId:post.id});if(alive&&epoch===accountEpoch&&buddyRoster.value===roster){roster.members=r.participants||[];if(r.post?.buddy)applyBuddy(post,r.post.buddy);}}
 catch(e){if(epoch===accountEpoch&&buddyRoster.value===roster){roster.error=treeholeError(e);if(treeholeErrorCode(e)==='session_expired')clearAccount();}}
 finally{if(epoch===accountEpoch&&buddyRoster.value===roster)roster.loading=false;}
}
async function vote(post:TreeholePost,optionId:string|null){const epoch=accountEpoch;if(!pollsEnabled.value||busy.value||pendingVotes.value[post.id])return;pendingVotes.value[post.id]=true;error.value='';
 const apply=(poll:TreeholePoll)=>{pollSnapshots.set(post.id,poll);for(const p of [post,...posts.value,...profilePosts.value,...routeHistory.flatMap(r=>[...(r.detail?[r.detail]:[]),...r.profilePosts]),...(detail.value?[detail.value]:[])])if(p.id===post.id)p.poll=poll;};
 try{const r=await api('polls.vote',{postId:post.id,optionId});if(alive&&epoch===accountEpoch&&r.post?.poll)apply(r.post.poll);}
 catch(e){if(epoch===accountEpoch&&treeholeErrorCode(e)==='poll_closed'&&post.poll)apply({...post.poll,closed:true});actionError(e,epoch);}
 finally{if(epoch===accountEpoch)delete pendingVotes.value[post.id];}
}
async function react(post:TreeholePost,kind:'like'|'save'){
 const key=post.id+':'+kind,epoch=accountEpoch;if(busy.value||pendingReactions.value[key])return;
 const before={liked:post.liked,saved:post.saved,likeCount:post.likeCount},enabled=kind==='like'?!post.liked:!post.saved;
 const apply=(value:Partial<TreeholePost>)=>{for(const p of [...posts.value,...profilePosts.value])if(p.id===post.id)Object.assign(p,value);if(detail.value?.id===post.id)Object.assign(detail.value,value);};
 pendingReactions.value[key]=true;error.value='';apply(kind==='like'?{liked:enabled,likeCount:Math.max(0,post.likeCount+(enabled?1:-1))}:{saved:enabled});
 try{const r=await api('reactions.set',{postId:post.id,kind,enabled});if(!alive||epoch!==accountEpoch||!r.post)return;apply(kind==='like'?{liked:r.post.liked,likeCount:r.post.likeCount}:{saved:r.post.saved});if(kind==='save'&&!r.post.saved&&scope.value==='saved')posts.value=posts.value.filter(item=>item.id!==post.id);}
 catch(e){if(epoch===accountEpoch)apply(kind==='like'?{liked:before.liked,likeCount:before.likeCount}:{saved:before.saved});actionError(e,epoch);}finally{if(epoch===accountEpoch)delete pendingReactions.value[key];}
}
async function respond(post:TreeholePost,kind:TreeholeResponseKind){
 const epoch=accountEpoch;if(!responsesEnabled.value||busy.value||pendingResponses.value[post.id])return;if(kind==='joy'&&!joyEnabled.value){notice.value='欢乐回应暂时不可用，稍后再试';return;}
 const before={myResponse:post.myResponse??null,responseCounts:{...post.responseCounts}},next=post.myResponse===kind?null:kind,counts={...post.responseCounts};
 if(before.myResponse)counts[before.myResponse]=Math.max(0,(counts[before.myResponse]||0)-1);if(next)counts[next]=(counts[next]||0)+1;
 const apply=(value:Partial<TreeholePost>)=>{const cached=[post,...posts.value,...profilePosts.value,...routeHistory.flatMap(r=>[...(r.detail?[r.detail]:[]),...r.profilePosts]),...(detail.value?[detail.value]:[])];for(const p of cached)if(p.id===post.id)Object.assign(p,value);};
 pendingResponses.value[post.id]=true;error.value='';apply({myResponse:next,responseCounts:counts});
 try{const r=await api('responses.set',{postId:post.id,kind:next});if(!alive||epoch!==accountEpoch||!r.post)return;apply({myResponse:r.post.myResponse,responseCounts:r.post.responseCounts});}
 catch(e){if(epoch===accountEpoch)apply(before);actionError(e,epoch);}finally{if(epoch===accountEpoch)delete pendingResponses.value[post.id];}
}
async function chooseAvatar(event:Event){const input=event.target as HTMLInputElement,file=input.files?.[0];input.value='';if(!file)return;await run(async()=>{const epoch=accountEpoch,prepared=await prepareTreeholeImage(file,true);if(alive&&epoch===accountEpoch)avatarCandidate.value=prepared;});}
function applyAvatar(updated:TreeholeUser){
 user.value=updated;feedNeedsRefresh=true;
 const update=(author:TreeholePost['author'])=>{if(!author.anonymous&&author.id===updated.id)author.avatar=updated.avatar;};
 for(const p of [...posts.value,...profilePosts.value,...(detail.value?[detail.value]:[])])update(p.author);
 for(const c of allComments.value)update(c.author);
 if(profile.value?.id===updated.id)profile.value.avatar=updated.avatar;
 for(const n of notifications.value)update(n.actor);
 // Previous route snapshots may include public authors. Refresh those projections on return.
 for(const route of routeHistory){if(route.profile?.id===updated.id)route.profile.avatar=updated.avatar;for(const p of [...route.profilePosts,...(route.detail?[route.detail]:[])])update(p.author);for(const c of route.comments){update(c.author);for(const reply of c.replies||[])update(reply.author);}}
}
function saveAvatar(){void run(async()=>{const candidate=avatarCandidate.value,epoch=accountEpoch;if(!candidate)return;
 if(!candidate.remote)candidate.remote=(await api('media.upload',{data:candidate.data,requestId:candidate.id,purpose:'avatar'})).image;
 if(!alive||epoch!==accountEpoch)return;if(!candidate.remote)throw Error('invalid_response');
 const result=await api('avatar.set',{imageId:candidate.remote.id});if(!alive||epoch!==accountEpoch)return;if(!result.user)throw Error('invalid_response');applyAvatar(result.user);avatarCandidate.value=null;notice.value='头像已更新';
});}
function cancelAvatar(){const old=avatarCandidate.value;avatarCandidate.value=null;if(old?.remote)void api('media.discard',{imageId:old.remote.id}).catch(()=>{});}
function removeAvatar(){confirmAction.value={title:'恢复默认头像？',run:async()=>{const epoch=accountEpoch,r=await api('avatar.set',{imageId:null});if(!alive||epoch!==accountEpoch)return;if(r.user)applyAvatar(r.user);cancelAvatar();confirmAction.value=null;notice.value='已恢复默认头像';}};}
function askDelete(post:TreeholePost,comment?:TreeholeComment){menu.value=null;confirmAction.value={title:comment?'删除这条评论？':'删除这条帖子和它的讨论？',run:async()=>{
 await api(comment?'comments.delete':'posts.delete',{postId:post.id,commentId:comment?.id});confirmAction.value=null;
 if(comment)await loadDetail(post);else{posts.value=posts.value.filter(p=>p.id!==post.id);screen.value='feed';detail.value=null;}
}};}
function report(post:TreeholePost,comment?:TreeholeComment){menu.value=null;reportTarget.value={postId:post.id,...(comment?{commentId:comment.id}:{})};reason.value='';}
function submitReport(){if(!reportTarget.value)return;void run(async()=>{await api('reports.create',{...reportTarget.value,reason:reason.value});reportTarget.value=null;notice.value='举报已提交，管理员会查看处理';});}
function block(post:TreeholePost,comment?:TreeholeComment){menu.value=null;const anon=comment?comment.author.anonymous:post.anonymous;confirmAction.value={title:anon?'隐藏这条讨论？':'屏蔽此人的昵称发言？匿名内容不会关联屏蔽。',run:async()=>{await api('blocks.set',{postId:post.id,commentId:comment?.id});if(!anon){const id=(comment?.author||post.author).id;followingRevision++;followingLoading.value=false;following.value=following.value.filter(p=>p.id!==id);if(profile.value&&profile.value.id===id)profile.value={...profile.value,following:false};}routeHistory.length=0;confirmAction.value=null;detail.value=null;screen.value='feed';await feed();}};}
const accountEntry=defineModel<boolean>('accountEntry');
watch([accountEntry,ready,busy,user,recovery],()=>{
 if(!accountEntry.value||!ready.value||busy.value||!user.value||recovery.value)return;
 accountEntry.value=false;
 if(screen.value!=='compose'&&!commentBody.value.trim()&&!commentImages.value.length)account();
},{flush:'post'});
function account(){screen.value='account';void refreshSocial();void refreshUnread();nickname.value=user.value?.nickname||'';bio.value=user.value?.bio||'';password.value='';newPassword.value='';accountAction.value='overview';}
function saveAccount(){void run(async()=>{
 if(accountAction.value==='profile'){const r=await api('profile.update',{nickname:nickname.value,...(engagementEnabled.value?{bio:bio.value}:{})});user.value=r.user!;feedNeedsRefresh=true;notice.value='资料已更新';}
 else if(accountAction.value==='password'){const r=await api('password.change',{password:password.value,newPassword:newPassword.value});password.value='';newPassword.value='';optionalRecovery.value='';recovery.value=r.recoveryCode||'';notice.value='密码已更新，其他设备已退出';}
 else confirmAction.value={title:'注销邯院通账号？你的帖子、评论、私信历史和登录状态将被删除，学校课表不受影响。',run:async()=>{await api('account.delete',{password:password.value});await clearDraft();confirmAction.value=null;clearAccount();notice.value='账号已注销';}};
});}
function logout(){confirmAction.value={title:'退出邯院通账号？',run:async()=>{await api('logout');await clearDraft();confirmAction.value=null;clearAccount();}};}
function adminChanged(removedPostId?:string){
 if(removedPostId){
  // Discard any page request that started before the server confirmed deletion.
  feedRevision.value++;feedLoadingMore.value=false;
  posts.value=posts.value.filter(post=>post.id!==removedPostId);
  profilePosts.value=profilePosts.value.filter(post=>post.id!==removedPostId);
 }
 feedNeedsRefresh=true;detail.value=null;routeHistory.length=0;
}
function manageContent(){if(!actionPost.value)return;adminTarget.value={postId:actionPost.value.id,commentId:actionComment.value?.id};menu.value=null;screen.value='moderate';}
function moderate(){adminTarget.value=null;if(moderationEnabled.value){screen.value='moderate';return;}void run(async()=>{const r=await api('admin.reports');reports.value=r.reports||[];screen.value='moderate';});}
function resolveReport(r:TreeholeReport,decision:string){confirmAction.value={title:`确认${({remove:'删除内容',lock:'暂停回复',ban:'禁言 7 天',dismiss:'忽略举报'} as Record<string,string>)[decision]}？`,run:async()=>{
 await api('admin.resolve',{reportId:r.id,decision,reason:r.reason});feedNeedsRefresh=true;confirmAction.value=null;const result=await api('admin.reports');reports.value=result.reports||[];notice.value='已处理';
}};}
async function leaveEditor(){if(screen.value==='compose')await clearDraft();discard.value=false;body.value='';commentBody.value='';commentImages.value=[];reply.value=null;returnFeed();}
function requestBack(){
 if(busy.value||recovery.value)return true;
 if(boardPicker.value){boardPicker.value=null;return true;}
 if(buddyRoster.value){buddyRoster.value=null;return true;}
 if(gallery.value){gallery.value=null;return true;}
 if(replyExpanded.value){closeReply();return true;}
 if(confirmAction.value){confirmAction.value=null;return true;}if(reportTarget.value){reportTarget.value=null;return true;}if(discard.value){discard.value=false;return true;}
 if(menu.value){menu.value=null;return true;}
 if((screen.value==='compose'&&(body.value.trim()||postTitle.value.trim()||images.value.length||pollDraft.value||buddyDraft.value))||(screen.value==='detail'&&(commentBody.value.trim()||commentImages.value.length))){discard.value=true;return true;}
 if(screen.value==='account'&&accountAction.value!=='overview'){accountAction.value='overview';password.value='';newPassword.value='';return true;}
 if(screen.value==='messages'&&messagesView.value?.back())return true;
 if(screen.value!=='feed'){previousRoute();return true;}
 if(searchOpen.value){searchOpen.value=false;return true;}
 if(!user.value&&auth.value!=='login'){auth.value='login';password.value='';return true;}return false;
}
function flushDraft(){clearTimeout(draftTimer);saveDraft();if(!document.hidden)void refreshUnread();}
function bindEvents(){document.addEventListener('visibilitychange',flushDraft);document.addEventListener('keydown',trapKeys,true);window.addEventListener('resize',sizePostInput,{passive:true});window.addEventListener('scroll',trackDetailScroll,{passive:true});window.addEventListener('wheel',manualScroll,{passive:true});if(!unreadTimer)unreadTimer=setInterval(()=>void refreshUnread(),180000);}
function unbindEvents(){document.removeEventListener('visibilitychange',flushDraft);document.removeEventListener('keydown',trapKeys,true);window.removeEventListener('resize',sizePostInput);window.removeEventListener('scroll',trackDetailScroll);window.removeEventListener('wheel',manualScroll);cancelAnimationFrame(scrollFrame);clearInterval(unreadTimer);unreadTimer=undefined;}
defineExpose({requestBack,refresh});
onMounted(()=>{void initialize();bindEvents();});
onActivated(()=>{active=true;bindEvents();publishTabNavigation();void refreshUnread();});
onDeactivated(()=>{active=false;unbindEvents();flushDraft();password.value='';newPassword.value='';});
onUnmounted(()=>{clearTimeout(draftTimer);saveDraft();alive=false;active=false;clearTimeout(noticeTimer);unbindEvents();if(dialogOpen.value)document.body.style.overflow=previousOverflow;password.value='';newPassword.value='';});
</script>

<template>
 <section class="treehole" aria-label="邯院通树洞" :aria-busy="busy" :class="{'keyboard-navigation':keyboardNavigation,'is-composing':screen==='compose','has-replies':screen==='detail'&&detail&&!recovery,'with-tab-navigation':props.tabRoot&&screen==='feed'}" @pointerdown.capture="keyboardNavigation=false" @keydown.capture="($event.key==='Tab'||$event.key.startsWith('Arrow'))&&(keyboardNavigation=true)" @touchstart.passive="edgeDown" @touchmove.passive="edgeMove" @touchend.passive="edgeEnd" @touchcancel="edgeStart=null;edgeOffset=0">
  <div :inert="dialogOpen">
   <header class="th-nav">
    <button v-if="!props.tabRoot||screen!=='feed'" class="th-icon" :aria-label="screen==='feed'?'返回上一页':'返回社区'" :disabled="busy||!!recovery" @click="navigationBack"><ArrowLeft :size="22"/></button>
    <div v-if="screen==='detail'" class="th-detail-tabs"><button :aria-pressed="detailTab==='body'" @click="windowTop">正文</button><button :aria-pressed="detailTab==='comments'" @click="scrollDiscussion">评论</button></div><h1 v-else>{{title}}</h1>
    <template v-if="user&&screen==='feed'&&!recovery"><button class="th-icon" aria-label="搜索帖子" :aria-expanded="searchOpen" :disabled="busy" @click="toggleSearch"><Search :size="21"/></button><button v-if="engagementEnabled" class="th-icon th-inbox-entry" aria-label="互动消息" :disabled="busy" @click="showInbox"><Bell :size="21"/><span v-if="unreadCount+messageUnread" class="th-unread-badge">{{unreadCount+messageUnread>99?'99+':unreadCount+messageUnread}}</span></button><button class="th-self" :aria-label="user.nickname" :disabled="busy" @click="account"><TreeholeAvatar :name="user.nickname" :url="user.avatar?.url" :size="34"/></button></template>
    <button v-else-if="user&&screen==='compose'&&!recovery" class="th-publish" form="treehole-compose" :aria-label="anonymous?'匿名发布':'以昵称发布'" :disabled="busy||!pollValid||!buddyValid||!!buddyDraft&&!buddiesEnabled||(!body.trim()&&!images.length&&!pollDraft)||!!pollDraft&&!pollsEnabled">{{busy&&postUpload?(postUpload.phase==='uploading'?'上传中':'发布中'):'发布'}}</button>
    <span v-else class="th-nav-spacer"/>
    <div v-if="busy" class="th-progress" role="status" aria-label="正在处理"/>
   </header>
   <div class="th-content">
    <div v-if="error" class="th-alert" role="alert"><AlertCircle :size="18"/><div>{{error}}<button v-if="!ready" :disabled="busy" @click="initialize">重试连接</button><button v-else-if="user&&screen==='feed'" :disabled="busy" @click="run(()=>feed())">重新加载</button></div></div>
    <div v-if="notice" class="th-notice" role="status"><component :is="notice.includes('不可用')?AlertCircle:notice.startsWith('正在')?RefreshCw:Check" :size="16"/>{{notice}}</div>
    <section v-if="recovery" class="th-card th-recovery"><span class="th-illustration"><ShieldCheck :size="34"/></span><h2>保存你的账号恢复码</h2><p>忘记密码时，用登录账号和这串恢复码找回。请保存到密码管理器或安全位置。</p><code data-testid="recovery-code">{{recovery}}</code><p class="th-muted">只在这次显示，请勿分享给他人。</p><button class="th-primary th-wide" :disabled="busy" @click="recovery=''">我已保存恢复码</button></section>
    <template v-else>
     <div v-if="!ready&&!error" class="th-skeleton" aria-label="正在连接树洞"><span/><span/><span/></div>
     <template v-if="!user&&ready">
      <div class="th-welcome"><div class="th-welcome-art" aria-hidden="true"><span class="th-bubble"><MessageCircle :size="37"/></span><span class="th-mask"><VenetianMask :size="29"/></span><Sparkles class="th-spark" :size="22"/></div><p class="th-eyebrow">邯院通 · 校园社区</p><h2>{{auth==='login'?'说说校园里的那些事':auth==='register'?'遇见校园里的同频人':'把账号找回来'}}</h2><p>分享日常，认真倾听。<br>用昵称相遇，也可以匿名说说心里话。</p></div>
      <form class="th-card th-auth" @submit.prevent="authenticate">
       <div class="th-form-heading"><h3>{{auth==='login'?'登录邯院通':auth==='register'?'创建邯院通账号':'找回邯院通账号'}}</h3><span>与教务账号独立</span></div>
       <label>登录账号<input v-model="username" autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="64" placeholder="中文、数字、邮箱或其他账号" required :disabled="busy"/></label>
       <label v-if="auth==='recover'">账号恢复码<input v-model="recoveryInput" autocomplete="off" autocapitalize="none" spellcheck="false" maxlength="64" placeholder="注册时保存的恢复码" required :disabled="busy"/></label>
       <label>{{auth==='recover'?'新密码':'密码'}}<span class="th-password"><input v-model="password" :type="showPassword?'text':'password'" :autocomplete="auth==='login'?'current-password':'new-password'" minlength="10" maxlength="128" placeholder="至少 10 位" required :disabled="busy"/><button type="button" :aria-label="showPassword?'隐藏密码':'显示密码'" :disabled="busy" @click="showPassword=!showPassword"><EyeOff v-if="showPassword" :size="18"/><Eye v-else :size="18"/></button></span></label>
       <p v-if="auth==='register'" class="th-muted">点击「创建账号」即同意下方社区规则。公开昵称会自动生成，可随时修改。</p>
       <button class="th-primary th-wide" type="submit" :disabled="busy||auth==='register'&&!registration">{{auth==='login'?'登录树洞':auth==='register'?'创建账号':'重设密码并登录'}}<ChevronRight :size="17"/></button>
       <div class="th-auth-links"><button v-if="auth!=='register'&&registration" type="button" :disabled="busy" @click="auth='register';password='';showPassword=false;error=''">注册账号</button><button v-if="auth!=='login'" type="button" :disabled="busy" @click="auth='login';password='';showPassword=false;error=''">返回登录</button><button v-if="auth==='login'" type="button" :disabled="busy" @click="auth='recover';password='';showPassword=false;error=''">忘记密码</button></div>
       <p v-if="!registration" class="th-muted">新账号注册暂未开放，已有账号可以直接登录。</p>
      </form>
      <details class="th-rules"><summary><ShieldCheck :size="15"/>树洞规则与匿名说明</summary><p>尊重同学，勿发布他人隐私、辱骂、骚扰、垃圾广告或违法内容。可举报、删除自己的内容和注销账号。匿名会对其他用户隐藏昵称与账号，后台保留账号关联用于处理举报；不同帖子使用不同匿名代号。同一帖子内的匿名发言可关联。昵称发帖后改为匿名回复时，请留意内容本身是否暴露身份。</p><p>账号服务保存登录账号、昵称、密码加密摘要、帖子、关注关系、私信、互动与举报记录，用于登录及社区服务。私信不公开展示，内容存储在社区服务端；发送方和接收方使用邯院通昵称。教务账号与课表不会上传到社区。可以在账号设置中注销。</p></details>
     </template>
     <div v-if="user" :key="screen" class="th-screen-panel" :style="edgeOffset?{transform:'translateX('+edgeOffset+'px)',animation:'none',transition:'none'}:undefined" :class="'th-page-'+pageMotion" :data-screen="screen">
      <template v-if="screen==='feed'">
       <div class="th-feed-heading">
        <nav v-if="engagementEnabled" class="th-return-links" aria-label="社区内容">
         <button :aria-pressed="scope==='all'" :disabled="busy" @click="accountFeed('all')">广场</button>
         <button v-if="followingEnabled" aria-label="关注动态" :aria-pressed="scope==='following'" :disabled="busy" @click="accountFeed('following')">关注</button>
         <button :aria-pressed="continuing" :disabled="busy" @click="accountFeed(continueScope)">继续聊</button>
        </nav>
        <strong v-else class="th-feed-label">广场</strong>
        <div class="th-feed-tools">
         <label v-if="browseScope" class="th-sort-control"><select aria-label="帖子排序" :value="sort" :disabled="busy" @change="setSort(($event.target as HTMLSelectElement).value)"><option value="latest">最新</option><option value="hot">热门</option></select><ChevronDown :size="13"/></label>
         <button class="th-icon" aria-label="刷新树洞" :disabled="busy" @click="refresh"><RefreshCw :size="16"/></button>
        </div>
       </div>
       <form v-if="searchOpen" class="th-search" @submit.prevent="run(()=>feed())"><Search :size="18"/><input ref="searchInput" v-model="query" maxlength="80" aria-label="搜索树洞文字" placeholder="搜索你感兴趣的内容" :disabled="busy"/><button v-if="query" type="button" aria-label="清除搜索" :disabled="busy" @click="clearSearch"><X :size="17"/></button><button class="th-search-submit" :disabled="busy">搜索</button></form>
       <TreeholeBoards v-if="browseScope&&discoveryEnabled" :category="category" :interest="interest" :topics="boardsEnabled" :disabled="busy" @choose="selectCategory" @more="boardPicker='interests'"/>
       <TreeholeDestination v-else-if="browseScope" :category="category" :disabled="busy" @choose="selectCategory"/>
       <div v-else-if="continuing" class="th-continue-tabs" role="group" aria-label="继续聊的讨论"><button :aria-pressed="scope==='participated'" :disabled="busy" @click="accountFeed('participated')">我参与的</button><button :aria-pressed="scope==='watching'" :disabled="busy" @click="accountFeed('watching')">关注的讨论</button><span>新回复会在帖子上提醒</span></div>
       <div v-else class="th-scope"><strong>{{scopeLabels[scope]||'广场'}}</strong><button :disabled="busy" @click="changeScope('all')">查看全部</button></div>
       <button v-if="body||postTitle||images.length||pollDraft||buddyDraft" class="th-draft-resume" :disabled="busy" @click="compose()"><PenLine :size="15"/> 有一条未发布的草稿，继续编辑 <ChevronRight :size="15"/></button>
       <div v-if="query&&!searchOpen" class="th-query">正在看「{{query}}」的搜索结果<button aria-label="清除搜索" :disabled="busy" @click="clearSearch"><X :size="14"/></button></div>
       <div v-if="scope==='following'&&!posts.length&&!busy&&!error" class="th-empty"><h3>暂时没有公开动态</h3><p>{{query||category!=='all'?'可以换个筛选条件，再看看关注的同学分享了什么。':'在同学主页点一下关注，TA 的公开帖子会出现在这里。'}}</p><button :disabled="busy" @click="accountFeed('all')">去广场看看</button><button :disabled="busy" @click="showFollowing()">管理我关注的人</button></div>
       <div v-if="scope!=='following'&&!posts.length&&!busy&&!error" class="th-empty"><span class="th-empty-art"><MessageCircle :size="32"/><i><Leaf :size="20"/></i></span><h3>{{query?'还没找到这段回声':scope==='mine'?'你的故事，从这里开始':scope==='saved'?'把喜欢的瞬间留在这里':scope==='participated'?'聊过的话题，下次接着聊':scope==='watching'?'关心的讨论，留在这里':boardPrompt?'还没有'+boardName+'帖':'这里，等你说第一句话'}}</h3><p>{{query?'换个关键词，看看大家在聊什么。':scope==='saved'?'在帖子下方点一下收藏，下次就能找到。':scope==='participated'?'发过的帖子和参与过的讨论会出现在这里。':scope==='watching'?'在帖子里关注讨论，新回复会提醒你。':boardPrompt||'一件开心的小事，一个想问的问题，都可以。'}}</p><button v-if="!query&&['all','mine'].includes(scope)" class="th-text-link" :disabled="busy" @click="compose()">发个帖子 <ChevronRight :size="15"/></button></div>
       <TreeholePostCard v-for="post in posts" :key="post.id" :post="post" :buddies-enabled="buddiesEnabled" :buddy-pending="pendingBuddies[post.id]" @buddy-join="buddyAction(post,'join',$event)" @buddy-close="buddyAction(post,'close',$event)" @buddy-members="showBuddyMembers(post)" :polls-enabled="pollsEnabled" :voting="pendingVotes[post.id]" @vote="vote(post,$event)" :responses-enabled="responsesEnabled" :joy-enabled="joyEnabled" :responding="pendingResponses[post.id]" @response="respond(post,$event)" :busy="busy" :reacting="pendingReactions[post.id+':like']" @open="openPost(post)" @discussion="openPost(post,true)" @react="react(post,$event)" @menu="menu=post.id" @image="imageView(post,$event)" @author="openProfile" @category="selectCategory" @interest="selectInterest"/>
       <TreeholeFeedPage v-if="feedNext" :page-key="feedRevision+JSON.stringify(feedNext)" :loading="feedLoadingMore" :error="feedPageError" :disabled="busy||!!recovery||dialogOpen" @load="loadMoreFeed"/>
       <p v-else-if="posts.length" class="th-feed-end">暂时就这些，过一会儿再来看看吧</p>

      </template>
      <TreeholeMessages v-else-if="screen==='messages'" ref="messagesView" :initial-member="messageMember" :drafts="messageDrafts" @unread="messageUnread=$event" @expired="clearAccount" @title="messageTitle=$event" @blocked="feedNeedsRefresh=true;refreshSocial()"/>
      <TreeholeInbox v-else-if="screen==='inbox'" :messages-enabled="messagesEnabled" :message-unread="messageUnread" @messages="showMessages()" :items="notifications" :filter="inboxFilter" :loading="inboxLoading||busy" :error="inboxError" :more="!!inboxNext" :unread="unreadCount" @filter="filterInbox" @open="openNotification" @refresh="loadInbox()" @more="loadInbox(true)" @read="markVisibleRead"/>
      <TreeholeFollowing v-else-if="screen==='following'" :followers="peopleKind==='followers'" :people="following" :loading="followingLoading" :error="followingError" :more="!!followingNext" :disabled="busy" :pending="pendingFollows" :retry-more="followingRetryMore" @open="openProfile" @unfollow="setFollow($event,false)" @follow="setFollow($event,true)" @load="loadFollowing" @browse="accountFeed('all')"/>
      <template v-else-if="screen==='profile'&&profile"><div class="th-public-profile"><TreeholeAvatar :name="profile.nickname" :url="profile.avatar?.url" :size="64"/><h2>{{profile.nickname}}</h2><p>{{profile.bio||'还没有填写简介'}}</p><span>{{profile.postCount}} 条公开帖子</span><div v-if="socialEnabled&&profile.id===user.id" class="th-social-stats"><button aria-label="我的关注列表" @click="showFollowing()"><strong>{{social?.followingCount??'—'}}</strong><span>关注</span></button><button aria-label="我的粉丝列表" @click="showFollowing('followers')"><strong>{{social?.followerCount??'—'}}</strong><span>粉丝</span></button></div><button v-if="followingEnabled&&profile.id!==user.id" class="th-follow-person" :class="{selected:profile.following}" :aria-pressed="!!profile.following" :disabled="busy||pendingFollows[profile.id]" @click="setFollow(profile.id,!profile.following)">{{pendingFollows[profile.id]?'处理中…':profile.following?'已关注 · 取消关注':'关注 TA'}}</button><button v-if="messagesEnabled&&profile.id!==user.id" class="th-message-person" :disabled="busy" @click="showMessages(profile.id)"><MessageCircle :size="17"/>发私信</button></div><p class="th-profile-privacy"><ShieldCheck :size="14"/>这里展示公开帖子，匿名发言不会出现在主页</p><TreeholePostCard v-for="post in profilePosts" :key="post.id" :post="post" :buddies-enabled="buddiesEnabled" :buddy-pending="pendingBuddies[post.id]" @buddy-join="buddyAction(post,'join',$event)" @buddy-close="buddyAction(post,'close',$event)" @buddy-members="showBuddyMembers(post)" :polls-enabled="pollsEnabled" :voting="pendingVotes[post.id]" @vote="vote(post,$event)" :responses-enabled="responsesEnabled" :joy-enabled="joyEnabled" :responding="pendingResponses[post.id]" @response="respond(post,$event)" :busy="busy" :reacting="pendingReactions[post.id+':like']" @open="openPost(post)" @discussion="openPost(post,true)" @react="react(post,$event)" @menu="menu=post.id" @image="imageView(post,$event)" @author="openProfile" @category="selectCategory" @interest="selectInterest"/><div v-if="!profilePosts.length" class="th-empty"><p>还没有公开帖子</p></div><button v-if="profileNext" class="th-more" :disabled="busy" @click="moreProfile">更多公开帖子</button></template>
      <form v-else-if="screen==='compose'" id="treehole-compose" class="th-compose" @submit.prevent="publish">
       <div class="th-compose-identity"><TreeholeAvatar :name="identity" :url="user.avatar?.url" :anonymous="anonymous" :size="34"/><div><strong>{{identity}}</strong><small>{{anonymous?'匿名身份 · 仅本帖可关联':'公开昵称'}}</small></div><label class="th-anon-pill" :class="{selected:anonymous}"><input v-model="anonymous" type="checkbox" :disabled="busy||postCategory==='treehole'"/><VenetianMask :size="17"/><span>匿名发布</span><i aria-hidden="true"/></label></div>
       <button v-if="discoveryEnabled" type="button" class="th-board-trigger" aria-label="选择分区" aria-haspopup="dialog" :disabled="busy||!!buddyDraft" @click="boardPicker='compose'"><span>发布到</span><strong>{{treeholeDestinationName(postCategory,postInterest)}}</strong><ChevronRight :size="17" aria-hidden="true"/></button>
       <TreeholeDestination v-else compose :category="postCategory" :disabled="busy||!!buddyDraft" @choose="postCategory=$event;postInterest=''"/>
       <div class="th-compose-writing"><input v-model="postTitle" class="th-title-input" aria-label="帖子标题" placeholder="标题（选填）" maxlength="40" :disabled="busy"/>
       <label class="th-editor-label"><span class="th-sr-only">想说的话</span><textarea ref="postInput" v-model="body" maxlength="3000" rows="4" :required="!!buddyDraft||!images.length&&!pollDraft" placeholder="分享校园里的新鲜事…" :disabled="busy" @input="sizePostInput"/></label></div>
       <div v-if="images.length" class="th-draft-images" aria-label="待发布配图"><div v-for="(photo,index) in images" :key="photo.id" :class="{'is-selected':selectedPhoto===photo.id,'is-uploading':postUpload?.phase==='uploading'&&postUpload.currentId===photo.id,'is-upload-failed':postUpload?.phase==='failed'&&postUpload.currentId===photo.id}"><button class="th-photo-select" type="button" :aria-label="'调整图片 '+(index+1)+' 顺序'" :aria-pressed="selectedPhoto===photo.id" :disabled="busy" @click="selectedPhoto=photo.id"><img :src="'data:image/jpeg;base64,'+photo.data" :alt="'待发布图片 '+(index+1)"/><span>{{index+1}}</span><span v-if="photo.remote||postUpload?.currentId===photo.id" class="th-photo-upload-label">{{photo.remote?'已上传':postUpload?.phase==='failed'?'上传未完成':'正在上传'}}</span></button><button class="th-photo-remove" type="button" :aria-label="'移除图片 '+(index+1)" :disabled="busy" @click="removeImage(index)"><X :size="15"/></button></div></div>
       <div v-if="selectedPhoto&&images.some(i=>i.id===selectedPhoto)" class="th-photo-order"><span>第 {{images.findIndex(i=>i.id===selectedPhoto)+1}} 张</span><button type="button" :disabled="busy||images[0]?.id===selectedPhoto" @click="movePhoto(-1)"><ChevronLeft :size="18"/>前移</button><button type="button" :disabled="busy||images.at(-1)?.id===selectedPhoto" @click="movePhoto(1)">后移<ChevronRight :size="18"/></button></div>
       <TreeholeUploadStatus v-if="postUpload" :progress="postUpload" :disabled="busy||!pollValid||!buddyValid||(!body.trim()&&!images.length&&!pollDraft)" @retry="publish"/>
       <div class="th-compose-tools" role="group" aria-label="帖子附件"><label v-if="imagesEnabled" class="th-compose-tool" :class="{disabled:busy||images.length>=9}"><ImagePlus :size="20"/><span>图片<small v-if="images.length">{{images.length}}/9</small></span><input type="file" accept="image/*" multiple aria-label="添加图片" :disabled="busy||images.length>=9" @change="chooseImages"/></label><button v-if="pollsEnabled&&!buddyDraft" class="th-compose-tool" type="button" aria-label="添加投票" :aria-pressed="!!pollDraft" :disabled="busy" @click="pollDraft|| (pollDraft={question:'',options:['',''],durationHours:24})"><ChartNoAxesColumnIncreasing :size="20"/><span>投票</span></button><button v-if="buddiesEnabled&&postCategory==='buddies'&&!pollDraft" class="th-compose-tool" type="button" aria-label="设置时间、地点和报名" :aria-pressed="!!buddyDraft" :disabled="busy" @click="buddyDraft||(buddyDraft=newBuddyDraft())"><CalendarPlus :size="20"/><span>招募</span></button><span class="th-compose-count" :class="{'near-limit':body.length>2800}">{{body.length}} / 3000</span></div>
       <TreeholeBuddyEditor v-if="buddyDraft" v-model="buddyDraft" :disabled="busy||!buddiesEnabled" @remove="buddyDraft=null"/><p v-if="buddyDraft&&!buddiesEnabled" class="th-draft-status">报名暂不可用，草稿已保留。</p>
       <TreeholePollEditor v-if="pollDraft" v-model="pollDraft" :disabled="busy||!pollsEnabled" @remove="pollDraft=null"/><p v-if="pollDraft&&!pollsEnabled" class="th-draft-status">投票暂不可用，草稿已保留。</p>
       <div class="th-compose-footnote"><span class="th-draft-status"><Check v-if="draftSaved==='草稿已保存'" :size="12"/>{{draftSaved}}</span><button v-if="draftSaved.startsWith('草稿保存失败')" type="button" class="th-draft-retry" :disabled="busy" @click="retryDraft">重试保存</button><span v-else>友善表达，尊重隐私</span></div>
       <div class="th-compose-note"><ShieldCheck :size="15"/><p>{{anonymous?'其他同学看不到你的昵称和账号，本帖内使用同一匿名代号。':'帖子显示你的邯院通昵称，可在上方切换匿名。'}} 发布后身份固定。</p></div>
      </form>
      <template v-else-if="screen==='detail'&&detail">
       <TreeholePostCard :post="detail" :buddies-enabled="buddiesEnabled" :buddy-pending="pendingBuddies[detail.id]" @buddy-join="buddyAction(detail,'join',$event)" @buddy-close="buddyAction(detail,'close',$event)" @buddy-members="showBuddyMembers(detail)" :polls-enabled="pollsEnabled" :voting="pendingVotes[detail.id]" @vote="vote(detail,$event)" :responses-enabled="responsesEnabled" :joy-enabled="joyEnabled" :responding="pendingResponses[detail.id]" @response="respond(detail,$event)" full :busy="busy" @open="focusReply()" @react="react(detail,$event)" @menu="menu=detail.id" @image="imageView(detail,$event)" @author="openProfile" @category="selectCategory" @interest="selectInterest"/>
       <div class="th-discussion-title"><div><h2>评论 <span aria-hidden="true">{{detail.commentCount}}</span></h2><small>按时间排序</small></div><button v-if="engagementEnabled" class="th-watch-toggle" :aria-label="detail.watching?'取消关注':'关注讨论'" :aria-pressed="!!detail.watching" :title="detail.watching?'已关注，新回复会出现在互动消息':'关注后，新回复会出现在互动消息'" :disabled="busy||watchPending" @click="toggleWatch(detail)"><Check v-if="detail.watching" :size="15"/><Bell v-else :size="15"/>{{detail.watching?'已关注讨论':'关注讨论'}}</button></div>
       <div v-if="detailError" class="th-detail-error" role="alert"><AlertCircle :size="18"/><div><strong>暂时没有加载完整</strong><p>{{detailError}}，当前正文已保留。</p></div><button :disabled="detailLoading" @click="loadDetail(detail!)">重试</button></div>
       <section v-if="focusedThread" class="th-focus-context" aria-label="消息对应的回复"><div class="th-context-heading"><span>消息对应的回复</span><button @click="focusedThread=null;scrollDiscussion()">查看全部讨论</button></div><TreeholeCommentThread :comment="focusedThread" :busy="busy" :locked="detail.locked" :expanded="true" :loading="loadingThreads[focusedThread.id]" :pending-likes="pendingLikes" :more="(focusedThread.replyCount||0)>(focusedThread.replies?.length||0)" @image="commentImageView" @reply="focusReply" @like="commentLike" @menu="menu=$event.id" @expand="expandThread(focusedThread)"/></section>
       <div class="th-comments">
        <div v-if="detailLoading&&!comments.length" class="th-comment-loading" role="status"><span/><span/><span/><p>正在加载评论…</p></div>
        <div v-else-if="!comments.length&&!detailError" class="th-no-comments"><MessageCircle :size="25"/><strong>第一声回应，就从你开始</strong><p>一句关心、一个想法，都很好。</p></div>
        <TreeholeCommentThread v-for="comment in comments" :key="comment.id" :comment="comment" :busy="busy" :locked="detail.locked" :expanded="expandedReplies[comment.id]" :loading="loadingThreads[comment.id]" :pending-likes="pendingLikes" :more="!!replyPages[comment.id]" @image="commentImageView" @reply="focusReply" @like="commentLike" @menu="menu=$event.id" @expand="expandThread(comment)" @collapse="expandedReplies[comment.id]=false"/>
       </div>
       <button v-if="commentNext" class="th-more" :disabled="busy||detailLoading" @click="loadDetail(detail!,true)">{{detailLoading?'正在加载…':'加载更多评论'}}</button>
       <p v-if="detail.locked" class="th-locked"><LockKeyhole :size="16"/>这条讨论已暂停回复。</p>

      </template>
      <template v-else-if="screen==='account'">
       <div class="th-profile"><TreeholeAvatar :name="user.nickname" :url="user.avatar?.url" :size="68"/><h2>{{user.nickname}}</h2><p><AtSign :size="13"/>{{user.username}}</p><span>邯院通账号 · 昵称由你决定</span></div>
       <div v-if="socialEnabled&&accountAction==='overview'" class="th-social-stats"><button aria-label="我的关注列表" :disabled="busy" @click="showFollowing()"><strong>{{social?.followingCount??'—'}}</strong><span>关注</span></button><button aria-label="我的粉丝列表" :disabled="busy" @click="showFollowing('followers')"><strong>{{social?.followerCount??'—'}}</strong><span>粉丝</span></button><button v-if="messagesEnabled" aria-label="我的私信" :disabled="busy" @click="showMessages()"><strong>{{messageUnread||0}}</strong><span>未读私信</span></button></div><p v-if="socialError" class="th-social-error" role="alert">{{socialError}} <button @click="refreshSocial">重试统计</button></p>
       <section v-if="avatarsEnabled&&accountAction==='overview'" class="th-avatar-editor" aria-label="设置头像">
        <template v-if="avatarCandidate"><img :src="'data:image/jpeg;base64,'+avatarCandidate.data" alt="新头像预览"/><p>预览头像 · 居中裁切</p><div><button class="th-primary" :disabled="busy" @click="saveAvatar">使用这张头像</button><button :disabled="busy" @click="cancelAvatar">取消</button></div></template>
        <label v-else class="th-avatar-upload" :class="{disabled:busy}"><ImagePlus :size="18"/>更换头像<input type="file" accept="image/*" aria-label="选择头像图片" :disabled="busy" @change="chooseAvatar"/></label>
        <button v-if="user.avatar&&!avatarCandidate" :disabled="busy" @click="removeAvatar">恢复默认头像</button><small>公开昵称发言使用此头像，匿名发言仍使用匿名图标。</small>
       </section>
       <p v-if="user.bannedUntil&&new Date(user.bannedUntil)>new Date()" class="th-alert">禁言至 {{date(user.bannedUntil)}}</p>
       <template v-if="accountAction==='overview'">
        <div v-if="buddiesEnabled" class="th-profile-shortcuts"><button :disabled="busy" @click="accountFeed('joined')"><MessagesSquare :size="22"/><strong>我报名的</strong><small>查看进展、回来继续聊</small></button></div>
        <div class="th-profile-shortcuts"><button :disabled="busy" @click="accountFeed('mine')"><PenLine :size="22"/><strong>我的帖子</strong><small>记录校园里的日常</small></button><button :disabled="busy" @click="accountFeed('saved')"><Bookmark :size="22"/><strong>我的收藏</strong><small>留住喜欢的内容</small></button></div>
        <div v-if="engagementEnabled" class="th-profile-shortcuts"><button :disabled="busy" @click="accountFeed('participated')"><MessagesSquare :size="22"/><strong>我参与的</strong><small>把上次的话接着聊</small></button><button :disabled="busy" @click="showInbox"><Bell :size="22"/><strong>互动消息 <span v-if="unreadCount">{{unreadCount}}</span></strong><small>回应与讨论的后续</small></button></div>
        <section class="th-settings"><button v-if="optionalRecovery" :disabled="busy" @click="recovery=optionalRecovery;optionalRecovery=''"><ShieldCheck :size="19"/><span>保存账号恢复码（选填）</span><ChevronRight :size="17"/></button><button v-if="followingEnabled" :disabled="busy" @click="showFollowing()"><AtSign :size="19"/><span>我关注的人</span><ChevronRight :size="17"/></button><button :disabled="busy" @click="accountAction='profile'"><PenLine :size="19"/><span>修改昵称</span><ChevronRight :size="17"/></button><button :disabled="busy" @click="accountAction='password'"><LockKeyhole :size="19"/><span>修改密码与恢复码</span><ChevronRight :size="17"/></button><button :disabled="busy" @click="run(async()=>{await api('blocks.clear');feedNeedsRefresh=true;notice='已恢复屏蔽的内容'})"><Eye :size="19"/><span>恢复已屏蔽的内容</span><ChevronRight :size="17"/></button><button v-if="user.role==='moderator'" :disabled="busy" @click="moderate"><ShieldCheck :size="19"/><span>{{moderationEnabled?'管理中心':'处理举报'}}</span><ChevronRight :size="17"/></button></section>
        <button class="th-logout" :disabled="busy" @click="logout"><LogOut :size="17"/>退出邯院通账号</button><button class="th-account-delete" :disabled="busy" @click="accountAction='delete'">注销账号</button>
       </template>
       <form v-else class="th-card" @submit.prevent="saveAccount"><h3>{{accountAction==='profile'?'换个喜欢的昵称':accountAction==='password'?'更新账号密码':'注销邯院通账号'}}</h3><label v-if="accountAction==='profile'">公开昵称<input v-model="nickname" minlength="2" maxlength="20" required :disabled="busy"/></label><label v-if="accountAction==='profile'&&engagementEnabled">个人简介<textarea v-model="bio" maxlength="120" rows="3" placeholder="简单介绍自己（选填）" :disabled="busy"/></label><template v-if="accountAction!=='profile'"><label>当前密码<input v-model="password" type="password" autocomplete="current-password" required minlength="10" :disabled="busy"/></label><label v-if="accountAction==='password'">新密码<input v-model="newPassword" type="password" autocomplete="new-password" minlength="10" maxlength="128" required :disabled="busy"/></label><p v-else class="th-muted">注销将删除你的树洞帖子、评论、双方私信历史和登录状态。学校课表保留。</p></template><button class="th-primary th-wide" :disabled="busy">{{accountAction==='delete'?'继续注销':'保存'}}</button></form>
      </template>
      <TreeholeAdmin v-else-if="screen==='moderate'&&moderationEnabled" :request="api" :initial-target="adminTarget" @changed="adminChanged" @expired="clearAccount"/>
      <section v-else-if="screen==='moderate'"><div class="th-feed-intro"><h2>举报处理</h2><p>认真对待每一次反馈。</p></div><p v-if="!reports.length" class="th-empty">暂无待处理举报。</p><article v-for="r in reports" :key="r.id" class="th-card"><p class="th-full-body">{{r.body}}</p><p class="th-muted">举报原因：{{r.reason}}</p><div class="th-moderation-actions"><button v-for="(name,key) in {remove:'删除',lock:'锁帖',ban:'禁言 7 天',dismiss:'忽略'}" :key="key" :disabled="busy" @click="resolveReport(r,key)">{{name}}</button></div></article></section>
     </div>
    </template>
   </div>
   <button v-if="user&&screen==='feed'&&!recovery" class="th-fab" :class="{'is-collapsed':fabCollapsed}" aria-label="发帖" :disabled="busy" @click="compose()"><PenLine :size="20"/><span>发帖</span></button>
   <div v-if="user&&screen==='detail'&&detail&&!recovery" class="th-readbar" aria-label="帖子互动"><button class="th-reply-entry" :disabled="busy||detail.locked" @click="focusReply()"><PenLine :size="17"/><span>{{detail.locked?'讨论已暂停':commentBody||commentImages.length?'继续编辑回复…':'说点什么吧…'}}</span></button><TreeholeLike class="th-read-action" detail :liked="detail.liked" :count="detail.likeCount" :disabled="busy||pendingReactions[detail.id+':like']" @toggle="react(detail,'like')"/><button class="th-read-action" :aria-label="detail.saved?'取消收藏':'收藏'" :aria-pressed="detail.saved" :disabled="busy||pendingReactions[detail.id+':save']" @click="react(detail,'save')"><Bookmark :size="21" :fill="detail.saved?'currentColor':'none'"/><span>{{detail.saved?'已收藏':'收藏'}}</span></button><button class="th-read-action" aria-label="查看评论" @click="scrollDiscussion"><MessageCircle :size="21"/><span>{{detail.commentCount||'评论'}}</span></button></div>
  </div>
  <Transition :name="dialogMotion" @before-enter="(el:Element)=>{el.removeAttribute('inert');el.removeAttribute('aria-hidden')}" @before-leave="(el:Element)=>{el.setAttribute('inert','');el.setAttribute('aria-hidden','true')}">
  <div v-if="dialogOpen" class="th-dialog-backdrop" :class="{'is-gallery':!!gallery}" @click.self="!busy&&requestBack()">
   <section ref="dialogElement" class="th-dialog" :class="{'th-gallery':!!gallery,'th-reply-sheet':replyExpanded}" role="dialog" aria-modal="true" :aria-label="boardPicker==='compose'?'选择分区':boardPicker==='interests'?'更多兴趣':'树洞操作'"><div class="th-sheet-grip"/>
    <TreeholeBoardPicker v-if="boardPicker" :mode="boardPicker" :category="boardPicker==='compose'?postCategory:category" :interest="boardPicker==='compose'?postInterest:interest" :topics="boardsEnabled" @choose="pickBoard" @close="boardPicker=null"/>
    <div v-else-if="buddyRoster" class="th-buddy-roster"><div class="th-editor-heading"><h3>报名名单 · {{buddyRoster.post.buddy?.count||0}} 人</h3><button class="th-icon" aria-label="关闭报名名单" @click="buddyRoster=null"><X :size="20"/></button></div><p>仅你作为发起人可见，请尊重同学的隐私。</p><p v-if="buddyRoster.error" role="alert">{{buddyRoster.error}}</p><div class="th-buddy-roster-list"><div v-for="member in buddyRoster.members" :key="member.id"><TreeholeAvatar :name="member.nickname" :url="member.avatar?.url" :size="36"/><strong>{{member.nickname}}</strong><small>{{date(member.joinedAt)}}</small></div></div><p v-if="!buddyRoster.loading&&!buddyRoster.members.length&&!buddyRoster.error">还没有同学报名，可以在评论里聊聊具体安排。</p><button class="th-more" :disabled="buddyRoster.loading" @click="showBuddyMembers(buddyRoster.post)">{{buddyRoster.loading?'正在加载…':'刷新报名名单'}}</button></div>
    <template v-else-if="gallery"><div class="th-gallery-bar"><button class="th-icon" aria-label="关闭大图" @click="gallery=null"><X :size="23"/></button><span>{{gallery.index+1}} / {{gallery.post.images?.length}}</span><button class="th-icon" :aria-label="zoomed?'缩小图片':'放大图片'" @click="zoomed=!zoomed"><Search :size="22"/></button></div><div class="th-gallery-stage" :class="{zoomed}" @touchstart="galleryX=$event.touches[0].clientX" @touchend="imageGesture" @dblclick="zoomed=!zoomed"><img v-if="currentImage?.url&&!galleryFailed" :src="currentImage.url" alt="帖子原图" referrerpolicy="no-referrer" @error="galleryFailed=true"/><button v-else @click="renewImage">图片暂未加载，点击重试</button></div><div class="th-gallery-actions"><button :disabled="gallery.index===0" @click="galleryStep(-1)"><ChevronLeft :size="22"/>上一张</button><button :disabled="gallery.index===(gallery.post.images?.length||1)-1" @click="galleryStep(1)">下一张<ChevronRight :size="22"/></button></div></template>
    <form v-else-if="replyExpanded" class="th-reply-box" @submit.prevent="sendComment"><div class="th-editor-heading"><strong>{{reply?'回复 '+reply.author.name:'写评论'}}</strong><button type="button" class="th-icon" aria-label="收起回复编辑器" :disabled="busy" @click="closeReply"><X :size="20"/></button></div><div v-if="reply" class="th-reply-target"><span>{{reply.body}}</span><button type="button" aria-label="取消回复" :disabled="busy" @click="reply=null"><X :size="15"/></button></div><label class="th-reply-input"><span class="th-sr-only">你的回复</span><textarea ref="replyInput" v-model="commentBody" maxlength="1000" rows="4" :required="!commentImages.length" :disabled="busy" placeholder="说说你的想法…"/></label><div class="th-comment-photo-editor"><div v-for="(photo,index) in commentImages" :key="photo.id"><img :src="'data:image/jpeg;base64,'+photo.data" :alt="'评论图片预览 '+(index+1)"/><button type="button" :disabled="busy" :aria-label="'移除评论图片 '+(index+1)" @click="removeCommentImage(index)"><X :size="16"/></button></div><label v-if="commentImagesEnabled&&commentImages.length<3" class="th-comment-photo-picker"><ImagePlus :size="23"/><span>配图 {{commentImages.length}}/3</span><input type="file" accept="image/*" multiple aria-label="添加评论图片" :disabled="busy" @change="chooseCommentImages"/></label></div><TreeholeUploadStatus v-if="commentUpload" comment :progress="commentUpload" :disabled="busy||!commentBody.trim()&&!commentImages.length||!!detail?.locked" @retry="sendComment"/><div class="th-reply-bottom"><label class="th-anon-pill" :class="{selected:commentAnon||forceCommentAnon}"><input :checked="commentAnon||forceCommentAnon" type="checkbox" :disabled="busy||forceCommentAnon" @change="commentAnon=($event.target as HTMLInputElement).checked"/><VenetianMask :size="16"/>{{detail?.category==='treehole'?'本区统一匿名':forceCommentAnon?'保持楼主匿名身份':'匿名回复'}}</label><small>{{commentBody.length}} / 1000</small><button class="th-send" :disabled="busy||(!commentBody.trim()&&!commentImages.length)">发布回复<ArrowUp :size="16"/></button></div><p v-if="error" role="alert">{{error}}</p></form>
    <template v-else-if="discard"><span class="th-dialog-symbol"><PenLine :size="25"/></span><h3>放弃还没发布的文字？</h3><p>尚未发布的内容会被清除。</p><button class="th-primary th-wide" @click="discard=false">继续编辑</button><button v-if="screen==='compose'" class="th-more" :disabled="busy" @click="saveAndLeave">保存草稿并返回</button><button class="th-more" @click="leaveEditor">放弃并返回</button></template>
    <form v-else-if="reportTarget" @submit.prevent="submitReport"><span class="th-dialog-symbol"><Flag :size="25"/></span><h3>举报内容</h3><p>告诉我们发生了什么，管理员会认真查看。</p><label>原因<textarea v-model="reason" minlength="2" maxlength="300" rows="4" :required="!commentImages.length" :disabled="busy" placeholder="例如：泄露隐私、骚扰、垃圾广告"/></label><p v-if="error" role="alert">{{error}}</p><button class="th-primary th-wide" :disabled="busy">提交举报</button><button type="button" class="th-more" :disabled="busy" @click="reportTarget=null">取消</button></form>
    <template v-else-if="confirmAction"><span class="th-dialog-symbol"><ShieldCheck :size="25"/></span><h3>{{confirmAction.title}}</h3><p v-if="error" role="alert">{{error}}</p><button class="th-primary th-wide" :disabled="busy" @click="run(confirmAction!.run)">确认</button><button class="th-more" :disabled="busy" @click="confirmAction=null">取消</button></template>
    <template v-else-if="menu&&actionPost"><h3>{{actionComment?'评论操作':'帖子操作'}}</h3><div class="th-sheet-actions"><button v-if="user?.role==='moderator'&&moderationEnabled" :disabled="busy" @click="manageContent"><ShieldCheck :size="20"/>管理此内容</button><button v-if="(actionComment||actionPost).author.mine" :disabled="busy" @click="askDelete(actionPost,actionComment)"><Trash2 :size="20"/>{{actionComment?'删除评论':'删除帖子'}}</button><template v-else><button :disabled="busy" @click="report(actionPost,actionComment)"><Flag :size="20"/>举报</button><button :disabled="busy" @click="block(actionPost,actionComment)"><VolumeX :size="20"/>{{(actionComment?.author.anonymous??actionPost.anonymous)?'隐藏这条讨论':'屏蔽昵称发言'}}</button></template></div><button class="th-more" @click="menu=null">取消</button></template>
   </section>
  </div>
  </Transition>
 </section>
</template>
<style scoped src="./Treehole.css"></style>
<style scoped src="./TreeholeRedesign.css"></style>
