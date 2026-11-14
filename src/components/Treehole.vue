<script setup lang="ts">
import {ref,computed,onMounted,onUnmounted} from 'vue';
import {MessageCircle,Heart,Bookmark,Plus,ArrowLeft,UserRound,ShieldCheck,MoreHorizontal,Leaf} from 'lucide-vue-next';
import {treeholeRequest as api,treeholeError,treeholeErrorCode,type TreeholeUser,type TreeholePost,type TreeholeComment,type TreeholeReport} from '../services/treehole';

const user=ref<TreeholeUser|null>(null),busy=ref(false),ready=ref(false),error=ref(''),notice=ref('');
const registration=ref(false),inviteRequired=ref(false),auth=ref<'login'|'register'|'recover'>('login');
const username=ref(''),password=ref(''),nickname=ref(''),invite=ref(''),agreed=ref(false),recoveryInput=ref(''),recovery=ref('');
const screen=ref<'feed'|'compose'|'detail'|'account'|'moderate'>('feed');
const posts=ref<TreeholePost[]>([]),scope=ref('all'),query=ref(''),feedNext=ref<Record<string,string>|null>(null);
const detail=ref<TreeholePost|null>(null),comments=ref<TreeholeComment[]>([]),commentNext=ref<Record<string,string>|null>(null),reply=ref<TreeholeComment|null>(null);
const body=ref(''),anonymous=ref(false),commentBody=ref(''),commentAnon=ref(false),postKey=ref(crypto.randomUUID()),commentKey=ref(crypto.randomUUID());
const reports=ref<TreeholeReport[]>([]),newPassword=ref(''),accountAction=ref<'profile'|'password'|'delete'>('profile');
const menu=ref<string|null>(null),reportTarget=ref<{postId:string;commentId?:string}|null>(null),reason=ref(''),discard=ref(false);
const confirmAction=ref<{title:string;run:()=>Promise<void>}|null>(null);
let alive=true;
const identity=computed(()=>anonymous.value?'匿名同学':user.value?.nickname||'邯院通昵称');
const forceCommentAnon=computed(()=>!!detail.value?.anonymous&&!!detail.value?.author.mine);
function date(value:string){return new Date(value).toLocaleString('zh-CN',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'});}
async function run(work:()=>Promise<void>){
 if(busy.value)return;busy.value=true;error.value='';notice.value='';
 try{await work();}catch(e){if(alive){error.value=treeholeError(e);if(treeholeErrorCode(e)==='session_expired'){clearAccount();}}}
 finally{if(alive)busy.value=false;}
}
function clearAccount(){user.value=null;posts.value=[];detail.value=null;comments.value=[];body.value='';commentBody.value='';reply.value=null;recovery.value='';password.value='';newPassword.value='';recoveryInput.value='';screen.value='feed';menu.value=null;reportTarget.value=null;}
async function feed(more=false){const r=await api('posts.list',{scope:scope.value,query:query.value,...(more?feedNext.value:{})});if(!alive)return;posts.value=more?[...posts.value,...r.posts||[]]:r.posts||[];feedNext.value=r.next||null;}
async function initialize(){await run(async()=>{
 const config=await api('config');if(!alive)return;registration.value=!!config.registrationEnabled;inviteRequired.value=!!config.requiresInvite;
 try{const r=await api('me');if(!alive)return;user.value=r.user!;nickname.value=r.user!.nickname;await feed();}
 catch(e){if(treeholeErrorCode(e)!=='session_expired')throw e;}
 ready.value=true;
});}
function authenticate(){void run(async()=>{
 const r=await api(auth.value,{username:username.value,password:password.value,nickname:nickname.value,invite:invite.value,agreed:agreed.value,recoveryCode:recoveryInput.value});
 password.value='';recoveryInput.value='';if(!alive)return;user.value=r.user!;nickname.value=r.user!.nickname;recovery.value=r.recoveryCode||'';screen.value='feed';posts.value=[];scope.value='all';query.value='';await feed();
});}
function changeScope(next:string){if(busy.value)return;scope.value=next;void run(()=>feed());}
function compose(){body.value='';anonymous.value=false;postKey.value=crypto.randomUUID();screen.value='compose';error.value='';}
async function loadDetail(post:TreeholePost,more=false){
 const r=await api('posts.get',{postId:post.id,...(more?commentNext.value:{})});if(!alive)return;detail.value=r.post!;comments.value=more?[...comments.value,...r.comments||[]]:r.comments||[];commentNext.value=r.next||null;
}
function openPost(post:TreeholePost){void run(async()=>{await loadDetail(post);if(!alive)return;screen.value='detail';commentBody.value='';reply.value=null;commentAnon.value=false;commentKey.value=crypto.randomUUID();menu.value=null;});}
function publish(){void run(async()=>{const r=await api('posts.create',{body:body.value,anonymous:anonymous.value,requestId:postKey.value});if(!alive)return;body.value='';postKey.value=crypto.randomUUID();posts.value=[r.post!,...posts.value];await loadDetail(r.post!);screen.value='detail';notice.value='已发布';});}
function sendComment(){if(!detail.value)return;const post=detail.value;void run(async()=>{
 await api('comments.create',{postId:post.id,body:commentBody.value,anonymous:commentAnon.value||forceCommentAnon.value,requestId:commentKey.value,replyTo:reply.value?.id||null});
 commentBody.value='';reply.value=null;commentKey.value=crypto.randomUUID();await loadDetail(post);notice.value='回复已发布';
});}
function react(post:TreeholePost,kind:'like'|'save'){void run(async()=>{const r=await api('reactions.set',{postId:post.id,kind,enabled:kind==='like'?!post.liked:!post.saved});if(!alive)return;posts.value=posts.value.map(p=>p.id===post.id?r.post!:p);if(detail.value?.id===post.id)detail.value=r.post!;});}
function askDelete(post:TreeholePost,comment?:TreeholeComment){menu.value=null;confirmAction.value={title:comment?'删除这条评论？':'删除这条帖子和它的讨论？',run:async()=>{
 await api(comment?'comments.delete':'posts.delete',{postId:post.id,commentId:comment?.id});confirmAction.value=null;
 if(comment)await loadDetail(post);else{posts.value=posts.value.filter(p=>p.id!==post.id);screen.value='feed';detail.value=null;}
}};}
function report(post:TreeholePost,comment?:TreeholeComment){menu.value=null;reportTarget.value={postId:post.id,...(comment?{commentId:comment.id}:{})};reason.value='';}
function submitReport(){if(!reportTarget.value)return;void run(async()=>{await api('reports.create',{...reportTarget.value,reason:reason.value});reportTarget.value=null;notice.value='举报已提交，管理员会查看处理';});}
function block(post:TreeholePost,comment?:TreeholeComment){menu.value=null;const anon=comment?comment.author.anonymous:post.anonymous;confirmAction.value={title:anon?'隐藏这条讨论？':'屏蔽此人的昵称发言？匿名内容不会关联屏蔽。',run:async()=>{await api('blocks.set',{postId:post.id,commentId:comment?.id});confirmAction.value=null;detail.value=null;screen.value='feed';await feed();}};}
function account(){screen.value='account';nickname.value=user.value?.nickname||'';password.value='';newPassword.value='';accountAction.value='profile';}
function saveAccount(){void run(async()=>{
 if(accountAction.value==='profile'){const r=await api('profile.update',{nickname:nickname.value});user.value=r.user!;notice.value='昵称已更新';}
 else if(accountAction.value==='password'){const r=await api('password.change',{password:password.value,newPassword:newPassword.value});password.value='';newPassword.value='';recovery.value=r.recoveryCode||'';notice.value='密码已更新，其他设备已退出';}
 else confirmAction.value={title:'注销邯院通账号？你的帖子、评论和登录状态将被删除，学校课表不受影响。',run:async()=>{await api('account.delete',{password:password.value});confirmAction.value=null;clearAccount();notice.value='账号已注销';}};
});}
function logout(){confirmAction.value={title:'退出邯院通账号？',run:async()=>{await api('logout');confirmAction.value=null;clearAccount();}};}
function moderate(){void run(async()=>{const r=await api('admin.reports');reports.value=r.reports||[];screen.value='moderate';});}
function resolveReport(r:TreeholeReport,decision:string){confirmAction.value={title:`确认${({remove:'删除内容',lock:'暂停回复',ban:'禁言 7 天',dismiss:'忽略举报'} as Record<string,string>)[decision]}？`,run:async()=>{
 await api('admin.resolve',{reportId:r.id,decision,reason:r.reason});confirmAction.value=null;const result=await api('admin.reports');reports.value=result.reports||[];notice.value='已处理';
}};}
function leaveEditor(){discard.value=false;body.value='';commentBody.value='';reply.value=null;screen.value='feed';detail.value=null;error.value='';}
function requestBack(){
 if(busy.value||recovery.value)return true;
 if(confirmAction.value){confirmAction.value=null;return true;}if(reportTarget.value){reportTarget.value=null;return true;}if(discard.value){discard.value=false;return true;}
 if(menu.value){menu.value=null;return true;}
 if((screen.value==='compose'&&body.value.trim())||(screen.value==='detail'&&commentBody.value.trim())){discard.value=true;return true;}
 if(screen.value!=='feed'){screen.value='feed';detail.value=null;password.value='';newPassword.value='';error.value='';void run(()=>feed());return true;}
 if(!user.value&&auth.value!=='login'){auth.value='login';password.value='';return true;}return false;
}
defineExpose({requestBack});onMounted(initialize);onUnmounted(()=>{alive=false;password.value='';newPassword.value='';});
</script>

<template>
 <section class="treehole" aria-label="邯院通树洞" :aria-busy="busy">
  <p v-if="error" class="th-alert" role="alert">{{error}} <button v-if="!ready" :disabled="busy" @click="initialize">重试连接</button><button v-else-if="user&&screen==='feed'" :disabled="busy" @click="run(()=>feed())">重新加载</button></p>
  <p v-if="notice" class="th-notice" role="status">{{notice}}</p>
  <div v-if="busy" class="th-loading" role="status">正在处理…</div>
  <section v-if="recovery" class="th-card th-recovery">
   <ShieldCheck/><h2>保存你的账号恢复码</h2><p>忘记密码时，用登录账号和这串恢复码找回。恢复码只在这次显示，请保存到密码管理器或安全位置。</p>
   <code data-testid="recovery-code">{{recovery}}</code><p>请勿把它发到树洞或分享给他人。</p><button class="th-primary" :disabled="busy" @click="recovery=''">我已保存恢复码</button>
  </section>
  <template v-else>
   <form v-if="!user&&ready" class="th-card th-auth" @submit.prevent="authenticate">
    <span class="th-mark"><Leaf :size="30"/></span><h2>{{auth==='login'?'说说校园里的那些事':auth==='register'?'创建邯院通账号':'找回邯院通账号'}}</h2>
    <p>树洞使用独立的邯院通账号，昵称由你决定。学校账号继续用于课表和成绩。</p>
    <label>登录账号<input v-model="username" autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="24" placeholder="4–24 位字母、数字或下划线" required :disabled="busy"/></label>
    <label v-if="auth==='register'">公开昵称<input v-model="nickname" autocomplete="nickname" minlength="2" maxlength="20" placeholder="同学们看到的名字" required :disabled="busy"/></label>
    <label v-if="auth==='recover'">账号恢复码<input v-model="recoveryInput" autocomplete="off" autocapitalize="none" spellcheck="false" maxlength="64" required :disabled="busy"/></label>
    <label>{{auth==='recover'?'新密码':'密码'}}<input v-model="password" type="password" :autocomplete="auth==='login'?'current-password':'new-password'" minlength="10" maxlength="128" placeholder="至少 10 位" required :disabled="busy"/></label>
    <label v-if="auth==='register'&&inviteRequired">内测邀请码<input v-model="invite" autocomplete="off" required :disabled="busy"/></label>
    <details class="th-rules"><summary>树洞规则与匿名说明</summary><p>尊重同学，勿发布他人隐私、辱骂、骚扰、垃圾广告或违法内容。可举报、删除自己的内容和注销账号。匿名会对其他用户隐藏昵称与账号，后台保留账号关联用于处理举报；不同帖子使用不同匿名代号。同一帖子内的匿名发言可关联。昵称发帖后改为匿名回复时，请留意内容本身是否暴露身份。</p><p>账号服务保存登录账号、昵称、密码加密摘要、帖子、互动与举报记录，用于登录及社区服务。教务账号与课表不会上传到社区。可以在账号设置中注销。</p></details>
    <label v-if="auth==='register'" class="th-check"><input v-model="agreed" type="checkbox" required :disabled="busy"/>我已阅读并同意树洞规则与账号服务说明</label>
    <button class="th-primary" type="submit" :disabled="busy||auth==='register'&&(!agreed||!registration)">{{auth==='login'?'登录树洞':auth==='register'?'创建账号':'重设密码并登录'}}</button>
    <div class="th-row"><button v-if="auth!=='register'&&registration" type="button" :disabled="busy" @click="auth='register';password='';error=''">注册账号</button><button v-if="auth!=='login'" type="button" :disabled="busy" @click="auth='login';password='';error=''">返回登录</button><button v-if="auth==='login'" type="button" :disabled="busy" @click="auth='recover';password='';error=''">忘记密码</button></div>
    <p v-if="!registration" class="th-muted">树洞正在准备内测，暂未开放新账号注册。</p>
   </form>
   <template v-if="user">
    <div class="th-top"><button v-if="screen!=='feed'" :disabled="busy" @click="requestBack"><ArrowLeft :size="18"/>返回树洞</button><span v-else class="th-greeting"><Leaf :size="18"/> 校园里的小小回声</span><button v-if="screen==='feed'" :disabled="busy" @click="account"><UserRound :size="17"/>{{user.nickname}}</button></div>
    <template v-if="screen==='feed'">
     <div class="th-intro"><div><h2>邯院树洞</h2><p>分享日常，也听听彼此。</p></div><button class="th-primary" :disabled="busy" @click="compose"><Plus :size="18"/>发帖</button></div>
     <div class="th-tabs" aria-label="帖子筛选"><button v-for="(label,key) in {all:'最新',mine:'我的帖子',saved:'收藏'}" :key="key" :aria-pressed="scope===key" :disabled="busy" @click="changeScope(key)">{{label}}</button></div>
     <form class="th-search" @submit.prevent="run(()=>feed())"><input v-model="query" maxlength="80" aria-label="搜索帖子" placeholder="搜索树洞里的文字" :disabled="busy"/><button :disabled="busy">搜索</button><button type="button" :disabled="busy" @click="query='';run(()=>feed())">刷新</button></form>
     <div v-if="!posts.length&&!busy&&!error" class="th-empty"><MessageCircle :size="35"/><h3>{{scope==='mine'?'你还没有发过帖子':scope==='saved'?'还没有收藏':'这里还很安静'}}</h3><p>{{query?'换个关键词试试':'从一句想说的话开始。'}}</p></div>
     <article v-for="post in posts" :key="post.id" class="th-card th-post">
      <header><span class="th-avatar" :class="{anon:post.anonymous}">{{post.anonymous?'树':post.author.name.slice(0,1)}}</span><div><strong>{{post.author.name}}</strong><small>{{date(post.createdAt)}}<span v-if="post.author.mine"> · 我</span></small></div><span v-if="post.locked" class="th-muted">已锁帖</span></header>
      <button class="th-post-body" :disabled="busy" @click="openPost(post)">{{post.body}}</button>
      <div class="th-actions"><button :aria-pressed="post.liked" :disabled="busy" @click="react(post,'like')"><Heart :size="18"/>{{post.likeCount||'点赞'}}</button><button :disabled="busy" @click="openPost(post)"><MessageCircle :size="18"/>{{post.commentCount||'评论'}}</button><button :aria-pressed="post.saved" :disabled="busy" @click="react(post,'save')"><Bookmark :size="18"/>{{post.saved?'已收藏':'收藏'}}</button></div>
     </article>
     <button v-if="feedNext" class="th-more" :disabled="busy" @click="run(()=>feed(true))">加载更多</button>
    </template>
    <form v-else-if="screen==='compose'" class="th-card th-compose" @submit.prevent="publish">
     <h2>发一条树洞</h2><label>想说的话<textarea v-model="body" maxlength="3000" rows="9" required placeholder="最近发生了什么，或有什么想聊的？" :disabled="busy"/></label>
     <span class="th-count">{{body.length}} / 3000</span><label class="th-check"><input v-model="anonymous" type="checkbox" :disabled="busy"/>匿名发布</label><p class="th-identity">发布身份：<strong>{{identity}}</strong></p><p class="th-muted">{{anonymous?'其他同学看不到你的昵称和账号。本帖内的匿名回复使用同一代号。':'帖子显示你的邯院通昵称。'}} 发布后身份方式固定。</p>
     <button class="th-primary" :disabled="busy||!body.trim()">{{anonymous?'匿名发布':'以昵称发布'}}</button>
    </form>
    <template v-else-if="screen==='detail'&&detail">
     <article class="th-card th-detail"><header><span class="th-avatar" :class="{anon:detail.anonymous}">{{detail.anonymous?'树':detail.author.name.slice(0,1)}}</span><div><strong>{{detail.author.name}}</strong><small>{{date(detail.createdAt)}}{{detail.author.mine?' · 我':''}}</small></div><button aria-label="帖子操作" :disabled="busy" @click="menu=menu===detail.id?null:detail.id"><MoreHorizontal/></button></header>
      <div v-if="menu===detail.id" class="th-menu"><button v-if="detail.author.mine" :disabled="busy" @click="askDelete(detail)">删除帖子</button><template v-else><button :disabled="busy" @click="report(detail)">举报</button><button :disabled="busy" @click="block(detail)">{{detail.anonymous?'隐藏这条讨论':'屏蔽昵称发言'}}</button></template><button @click="menu=null">收起</button></div>
      <p class="th-full-body">{{detail.body}}</p><div class="th-actions"><button :aria-pressed="detail.liked" :disabled="busy" @click="react(detail,'like')"><Heart :size="18"/>{{detail.likeCount||'点赞'}}</button><span>{{detail.commentCount}} 条评论</span><button :aria-pressed="detail.saved" :disabled="busy" @click="react(detail,'save')"><Bookmark :size="18"/>{{detail.saved?'已收藏':'收藏'}}</button></div>
     </article>
     <h3>聊一聊</h3><p v-if="!comments.length" class="th-muted">还没有评论。</p>
     <article v-for="comment in comments" :key="comment.id" class="th-card th-comment"><header><div><strong>{{comment.author.name}} <em v-if="comment.isOriginalPoster">楼主</em><em v-if="comment.author.mine">我</em></strong><small>{{date(comment.createdAt)}}</small></div><button v-if="!comment.deleted" aria-label="评论操作" :disabled="busy" @click="menu=menu===comment.id?null:comment.id"><MoreHorizontal :size="20"/></button></header><small v-if="comment.replyTo" class="th-muted">回复了一条评论</small><p class="th-full-body">{{comment.body}}</p>
      <div v-if="menu===comment.id" class="th-menu"><button v-if="comment.author.mine" :disabled="busy" @click="askDelete(detail,comment)">删除评论</button><template v-else><button :disabled="busy" @click="report(detail,comment)">举报</button><button :disabled="busy" @click="block(detail,comment)">{{comment.author.anonymous?'隐藏这条讨论':'屏蔽昵称发言'}}</button></template><button @click="menu=null">收起</button></div>
      <button v-if="!comment.deleted&&!detail.locked" class="th-reply" :disabled="busy" @click="reply=comment;menu=null">回复</button>
     </article><button v-if="commentNext" class="th-more" :disabled="busy" @click="run(()=>loadDetail(detail!,true))">加载更多评论</button>
     <p v-if="detail.locked" class="th-muted">这条讨论已暂停回复。</p>
     <form v-else class="th-card" @submit.prevent="sendComment"><div v-if="reply" class="th-row">回复 {{reply.author.name}}<button type="button" :disabled="busy" @click="reply=null">取消</button></div><label>你的回复<textarea v-model="commentBody" maxlength="1000" rows="3" required :disabled="busy" placeholder="友善交流，认真倾听"/></label><label class="th-check"><input :checked="commentAnon||forceCommentAnon" type="checkbox" :disabled="busy||forceCommentAnon" @change="commentAnon=($event.target as HTMLInputElement).checked"/>{{forceCommentAnon?'保持楼主匿名身份':'匿名回复'}}</label><p class="th-muted">{{commentAnon||forceCommentAnon?'匿名同学 · 本帖内代号保持一致':'以 '+user.nickname+' 的昵称回复'}}</p><button class="th-primary" :disabled="busy||!commentBody.trim()">发布回复</button></form>
    </template>
    <template v-else-if="screen==='account'">
     <div class="th-card"><h2>邯院通账号</h2><p>登录账号：{{user.username}}</p><p class="th-muted">公开昵称与学校资料分别管理。</p><p v-if="user.bannedUntil&&new Date(user.bannedUntil)>new Date()">禁言至 {{date(user.bannedUntil)}}</p></div>
     <form class="th-card" @submit.prevent="saveAccount"><div class="th-tabs"><button v-for="(name,key) in {profile:'昵称',password:'修改密码',delete:'注销账号'}" :key="key" type="button" :aria-pressed="accountAction===key" :disabled="busy" @click="accountAction=key;password='';newPassword=''">{{name}}</button></div>
      <label v-if="accountAction==='profile'">公开昵称<input v-model="nickname" minlength="2" maxlength="20" required :disabled="busy"/></label><template v-else><label>当前密码<input v-model="password" type="password" autocomplete="current-password" required minlength="10" :disabled="busy"/></label><label v-if="accountAction==='password'">新密码<input v-model="newPassword" type="password" autocomplete="new-password" minlength="10" maxlength="128" required :disabled="busy"/></label><p v-else>注销将删除你的树洞帖子、评论和登录状态。学校课表保留。</p></template><button class="th-primary" :disabled="busy">{{accountAction==='delete'?'继续注销':'保存'}}</button>
     </form><button v-if="user.role==='moderator'" class="th-more" :disabled="busy" @click="moderate">处理举报</button><button class="th-more" :disabled="busy" @click="run(async()=>{await api('blocks.clear');notice='已恢复屏蔽的内容'})">恢复已屏蔽的内容</button><button class="th-more" :disabled="busy" @click="logout">退出邯院通账号</button>
    </template>
    <section v-else-if="screen==='moderate'"><h2>举报处理</h2><p v-if="!reports.length" class="th-muted">暂无待处理举报。</p><article v-for="r in reports" :key="r.id" class="th-card"><p class="th-full-body">{{r.body}}</p><p>举报原因：{{r.reason}}</p><div class="th-actions"><button v-for="(name,key) in {remove:'删除',lock:'锁帖',ban:'禁言 7 天',dismiss:'忽略'}" :key="key" :disabled="busy" @click="resolveReport(r,key)">{{name}}</button></div></article></section>
   </template>
  </template>
  <div v-if="confirmAction||reportTarget||discard" class="th-dialog-backdrop">
   <section class="th-card th-dialog" role="dialog" aria-modal="true" aria-label="确认树洞操作">
    <template v-if="discard"><h3>放弃还没发布的文字？</h3><button class="th-primary" @click="discard=false">继续编辑</button><button class="th-more" @click="leaveEditor">放弃并返回</button></template>
    <form v-else-if="reportTarget" @submit.prevent="submitReport"><h3>举报内容</h3><label>原因<textarea v-model="reason" minlength="2" maxlength="300" rows="4" required :disabled="busy" placeholder="例如：泄露隐私、骚扰、垃圾广告"/></label><p v-if="error" role="alert">{{error}}</p><button class="th-primary" :disabled="busy">提交举报</button><button type="button" class="th-more" :disabled="busy" @click="reportTarget=null">取消</button></form>
    <template v-else-if="confirmAction"><h3>{{confirmAction.title}}</h3><p v-if="error" role="alert">{{error}}</p><button class="th-primary" :disabled="busy" @click="run(confirmAction!.run)">确认</button><button class="th-more" :disabled="busy" @click="confirmAction=null">取消</button></template>
   </section>
  </div>
 </section>
</template>

<style scoped>
.treehole{max-width:680px;margin:0 auto;padding-bottom:20px;--th-green:#3f7668}.treehole button{min-height:44px}.th-card{border:1px solid var(--color-border);background:var(--color-surface,#fff);border-radius:20px;padding:18px;margin:14px 0}.th-card h2{margin-bottom:8px}.th-card p{font-size:14px}.th-card label{display:grid;gap:8px;margin:16px 0 10px;font-size:14px;font-weight:550}.treehole input:not([type=checkbox]),.treehole textarea{width:100%;min-width:0;border:1px solid var(--color-border);border-radius:12px;padding:12px;background:var(--color-bg);color:var(--color-text);font:inherit;line-height:1.5}.treehole textarea{resize:vertical;min-height:96px}.th-primary{display:inline-flex;gap:6px;align-items:center;justify-content:center;background:var(--th-green);color:#fff;border-radius:13px;padding:10px 18px;font-weight:600}.th-card>.th-primary,.th-card form>.th-primary{width:100%;margin-top:14px}.th-row,.th-top,.th-intro{display:flex;justify-content:space-between;align-items:center;gap:10px}.th-row button,.th-top button{color:var(--th-green);display:inline-flex;align-items:center;gap:6px}.th-top{font-size:13px}.th-top button:last-child{max-width:52%;overflow:hidden;overflow-wrap:anywhere}.th-intro{margin:18px 0}.th-intro p,.th-muted,.th-count{font-size:12px;color:var(--color-muted)}.th-greeting{display:flex;gap:6px;align-items:center;color:var(--th-green)}.th-mark{background:#e9f2ec;color:var(--th-green);border-radius:16px;padding:12px;display:inline-flex;margin-bottom:14px}.th-tabs{display:flex;gap:6px;border-bottom:1px solid var(--color-border)}.th-tabs button{padding:10px 14px;color:var(--color-muted)}.th-tabs button[aria-pressed=true]{color:var(--th-green);font-weight:650;border-bottom:2px solid var(--th-green)}.th-search{display:flex;gap:6px;margin:14px 0}.th-search input{flex:1}.th-search button{white-space:nowrap;font-size:13px}.th-empty{text-align:center;padding:38px 10px;color:var(--color-muted)}.th-empty h3{margin:12px 0 4px}.th-post header,.th-detail header,.th-comment header{display:flex;align-items:center;gap:10px}.th-post header>div,.th-detail header>div,.th-comment header>div{flex:1;min-width:0;overflow-wrap:anywhere}.th-card header strong{font-size:13px}.th-card header small{display:block;font-size:11px;color:var(--color-muted);margin-top:4px}.th-avatar{width:36px;height:36px;display:grid;place-items:center;border-radius:13px;background:#eee9f9;color:#7a62a6;font-size:14px;flex-shrink:0}.th-avatar.anon{background:#edf4ed;color:var(--th-green)}.th-post-body{display:-webkit-box;-webkit-line-clamp:5;-webkit-box-orient:vertical;overflow:hidden;text-align:left;white-space:pre-wrap;overflow-wrap:anywhere;padding:0;margin:16px 0;width:100%;font-size:15px;line-height:1.75}.th-full-body{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.8;margin:14px 0}.th-actions{display:flex;align-items:center;justify-content:space-between;gap:8px;font-size:12px;color:var(--color-muted);border-top:1px solid var(--color-border);padding-top:6px}.th-actions button{display:flex;align-items:center;gap:6px}.th-actions button[aria-pressed=true]{color:var(--th-green)}.th-more{width:100%;color:var(--th-green);margin:4px 0}.th-check{display:flex!important;align-items:center;gap:10px!important;font-weight:400!important}.th-check input{width:20px;height:20px;accent-color:var(--th-green);flex-shrink:0}.th-count{display:block;text-align:right}.th-identity{margin:14px 0 4px}.th-rules{font-size:13px;margin-top:14px}.th-rules summary{padding:8px 0;color:var(--th-green)}.th-rules p{font-size:12px;line-height:1.8}.th-recovery code{display:block;overflow-wrap:anywhere;padding:16px;background:var(--color-bg);border:1px dashed var(--th-green);border-radius:12px;margin:14px 0;user-select:all}.th-alert,.th-notice{padding:12px 14px;border-radius:12px;background:#fff0ea;color:#863d22;font-size:13px;margin-bottom:10px;overflow-wrap:anywhere}.th-notice{background:#edf4ed;color:#345f40}.th-alert button{text-decoration:underline}.th-loading{font-size:12px;color:var(--color-muted);text-align:center;margin:8px}.th-menu{display:flex;flex-wrap:wrap;gap:6px;border-radius:10px;background:var(--color-bg);padding:4px 8px;margin-top:8px;font-size:12px;color:var(--th-green)}.th-reply{font-size:12px;color:var(--th-green)}.th-comment em{font-style:normal;font-size:10px;margin-left:5px;color:var(--th-green);background:#edf4ed;border-radius:4px;padding:2px 5px}.th-dialog-backdrop{position:fixed;inset:0;background:#1f293755;z-index:120;display:flex;align-items:center;justify-content:center;padding:20px}.th-dialog{width:min(100%,430px);max-height:85dvh;overflow:auto;background:var(--color-surface,#fff)}.th-dialog h3{line-height:1.7}.th-dialog>.th-more{margin-top:10px}.th-auth>p{color:var(--color-muted);line-height:1.8}.th-auth .th-row{margin-top:8px;font-size:13px}
</style>
