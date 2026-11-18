// Synthetic offline review data. Never imported by the product entry point.
export function adapter(campus){
 const user={id:'00000000-0000-4000-8000-000000000001',username:'preview',nickname:'小金鱼',bio:'记录邯院生活，也在这里认识同好。',role:'member',bannedUntil:null};
 const photo=(id)=>({id,url:campus,width:1536,height:1024});
 const post=(id,name,title,body,category,anonymous=false,images=[])=>({id,title,body,category,anonymous,images,author:{name,anonymous,mine:false,...(!anonymous?{id:'member-'+name}:{})},createdAt:new Date(Date.now()-(Number(id.slice(-1))||1)*3600000).toISOString(),locked:false,commentCount:0,likeCount:12,liked:false,saved:false});
 const posts=[post('post-1','落日收集员','邯院的秋天，值得慢一点','下课出来，刚好赶上这一阵晚霞。\n最近总在赶时间，今天想多走一会儿。你最喜欢校园里的哪个角落？','daily',false,[photo('campus-1')]),post('post-2','匿名同学 · 晴天','一个人吃饭，其实也挺自在的','以前总觉得独来独往有点尴尬。这周试着一个人去食堂、去图书馆，发现也可以把日子过得很舒服。\n慢慢找到自己的节奏吧。','daily',true),post('post-3','沿途','周末一起去图书馆？','想找几位一起学英语的同学，每次专注一小时，结束后交流一下今天学到了什么。愿意一起的可以在评论里聊聊。','buddies'),post('post-4','小陈同学','第一次做校园项目，有点小期待','从每天遇到的小问题开始，做一点真正有用的东西。设计、前端、安卓，或者只是有想法，都欢迎来聊聊。','study',false,[photo('campus-2'),photo('campus-3'),photo('campus-4'),photo('campus-5')])];
 posts.push({...post('buddy-8','慢跑同学','下课一起去操场慢跑','按自己的节奏跑两圈，结束后一起走走。','buddies'),buddy:{version:0,location:'东操场入口',startsAt:new Date(Date.now()+86400000).toISOString(),capacity:2,count:0,joined:false,closed:false,expired:false}});
 const comments=[{id:'comment-1',postId:'post-1',body:'图书馆出来的那条路！傍晚的光线很舒服。',author:{name:'晚风',anonymous:false,mine:false},createdAt:new Date(Date.now()-1800000).toISOString(),replyTo:null,rootId:null,deleted:false,isOriginalPoster:false,liked:false,likeCount:8,replyCount:2,replies:[{id:'reply-1',postId:'post-1',body:'我也喜欢那里，下次想带相机去。',author:{name:'落日收集员',anonymous:false,mine:false},createdAt:new Date().toISOString(),replyTo:'comment-1',rootId:'comment-1',deleted:false,isOriginalPoster:true,likeCount:2,liked:false},{id:'reply-2',postId:'post-1',body:'最近的落叶也好看。',author:{name:'小橘',anonymous:false,mine:false},createdAt:new Date().toISOString(),replyTo:'comment-1',rootId:'comment-1',deleted:false,isOriginalPoster:false,likeCount:0,liked:false}]},{id:'comment-2',postId:'post-1',body:'今天也辛苦啦，记得抬头看看天空。',author:{name:'匿名同学 · 微光',anonymous:true,mine:false},createdAt:new Date(Date.now()-900000).toISOString(),replyTo:null,rootId:null,deleted:false,isOriginalPoster:false,liked:false,likeCount:5,replyCount:0,replies:[]}];
 posts.push({...post('interest-6','周末玩家','最近在玩什么？','分享一款让你舍不得放下的游戏吧。','entertainment'),interest:'games'},post('quiet-7','匿名同学 · 微风','慢慢找到自己的节奏','有时候走得慢一点，也没关系。','treehole',true));
 posts.push(
  {...post('graduate-9','晨读同学','考研第一周怎么安排？','本科课程还有两门，这周先试着每天留出两小时做英语和数学。','study'),interest:'graduate'},
  {...post('reading-10','晚风','一起聊聊《百年孤独》','有没有哪一段让你读完想停下来想一会儿？','entertainment'),interest:'reading'},
  {...post('fitness-11','慢跑同学','记录今天的腿部训练','在健身房第一次试了保加利亚分腿蹲，下次打算把动作放慢一点。','entertainment'),interest:'fitness'},
 );
 posts[0].commentCount=4;posts[0].watching=true;posts[0].newReplyCount=2;
 const notifications=[
  {id:'notice-1',kind:'reply',postId:'post-1',commentId:'reply-2',rootId:'comment-1',actor:comments[0].replies[1].author,excerpt:'最近的落叶也好看。',postTitle:posts[0].title,createdAt:new Date(Date.now()-180000).toISOString(),readAt:null},
  {id:'notice-2',kind:'thread_reply',postId:'post-1',commentId:'comment-2',rootId:null,actor:comments[1].author,excerpt:comments[1].body,postTitle:posts[0].title,createdAt:new Date(Date.now()-900000).toISOString(),readAt:null},
  {id:'notice-3',kind:'post_like',postId:'post-3',commentId:null,rootId:null,actor:{name:'一位同学',anonymous:true,mine:false},excerpt:'',postTitle:posts[2].title,createdAt:new Date(Date.now()-3600000).toISOString(),readAt:null}
 ];
 posts[2].poll={version:0,question:'周末想怎么放松？',closesAt:new Date(Date.now()+3*86400000).toISOString(),closed:false,total:0,myOptionId:null,options:['散步拍照','一起运动','宿舍开黑'].map((text,i)=>({id:String(i),text,count:0}))};
 comments[0].images=[photo('comment-photo-1')];
 const followed=new Map();
 const unread=()=>notifications.filter(n=>!n.readAt).length;
 const copy=x=>JSON.parse(JSON.stringify(x));
 const dmThreads=[],dmMessages=[];let dmSequence=0;
 async function request(action,b={}){
  await new Promise(r=>setTimeout(r,action==='posts.get'?650:100));
  const p=posts.find(p=>p.id===b.postId);
  if(action==='config')return {imagesEnabled:true,registrationEnabled:false,engagementEnabled:true,schema:11,boardsEnabled:true,responseKinds:['useful','joy','hug'],socialEnabled:true,messagesEnabled:true,buddiesEnabled:true,pollsEnabled:true,commentImagesEnabled:true,followingEnabled:true,discoveryEnabled:true,avatarsEnabled:true,responsesEnabled:true};
  if(action==='follows.stats')return {social:{followingCount:followed.size,followerCount:1}};
  if(action==='followers.list')return {followers:[{id:posts[0].author.id,nickname:posts[0].author.name,bio:'分享校园里的小美好。',followedAt:new Date().toISOString(),following:followed.has(posts[0].author.id)}],next:null};
  if(action==='messages.open'){let t=dmThreads.find(t=>t.member.id===b.memberId);if(!t){const p=posts.find(p=>p.author.id===b.memberId);t={id:crypto.randomUUID(),member:{id:b.memberId,nickname:p?.author.name||'预览同学'},lastSeq:'0',updatedAt:new Date().toISOString(),lastMessage:null,unreadCount:0};dmThreads.push(t);}return {conversation:copy(t)};}
  if(action==='messages.inbox')return {conversations:copy(dmThreads.filter(t=>t.lastSeq!=='0')),messageUnreadCount:0,next:null};
  if(action==='messages.unread')return {messageUnreadCount:0};
  if(action==='messages.list')return {conversation:copy(dmThreads.find(t=>t.id===b.conversationId)),messages:copy(dmMessages.filter(m=>m.thread===b.conversationId&&(!b.afterSeq||BigInt(m.seq)>BigInt(b.afterSeq)))),next:null};
  if(action==='messages.read')return {};
  if(action==='messages.send'){let m=dmMessages.find(m=>m.requestId===b.requestId);if(!m){m={id:crypto.randomUUID(),thread:b.conversationId,seq:String(++dmSequence),body:b.body,mine:true,createdAt:new Date().toISOString(),requestId:b.requestId};dmMessages.push(m);}const t=dmThreads.find(t=>t.id===b.conversationId);t.lastMessage=m.body;t.lastSeq=m.seq;t.updatedAt=m.createdAt;return {message:copy(m),conversation:copy(t)};}
  if(action==='members.block'){followed.delete(b.memberId);dmThreads.splice(dmThreads.findIndex(t=>t.member.id===b.memberId),1);return {};}
  if(action==='avatar.set'){user.avatar=b.imageId?uploaded.get(b.imageId):null;for(const p of posts)if(!p.anonymous&&p.author.id===user.id)p.author.avatar=user.avatar;return {user:copy(user)};}
  if(action==='responses.set'){p.responseCounts||={};if(p.myResponse)p.responseCounts[p.myResponse]=Math.max(0,(p.responseCounts[p.myResponse]||0)-1);p.myResponse=b.kind;if(b.kind)p.responseCounts[b.kind]=(p.responseCounts[b.kind]||0)+1;return {post:copy(p)};}
  if(action==='buddies.members'){if(!p.author.mine)throw Error('forbidden');return {post:copy(p),participants:p.buddy.joined?[{id:user.id,nickname:user.nickname,avatar:user.avatar,joinedAt:new Date().toISOString()}]:[]};}
  if(action==='buddies.join'||action==='buddies.close'){const v=p.buddy;if(action==='buddies.close'){if(!p.author.mine)throw Error('forbidden');if(v.closed!==b.closed){v.closed=b.closed;v.version++;}}else{if(p.author.mine)throw Error('buddy_host');if(v.joined!==b.enabled){if(b.enabled&&(v.closed||Date.parse(v.startsAt)<=Date.now()))throw Error('buddy_closed');if(b.enabled&&v.count>=v.capacity)throw Error('buddy_full');v.joined=b.enabled;v.count+=b.enabled?1:-1;v.version++;}}return {post:copy(p)};}
  if(action==='polls.vote'){const poll=p.poll;if(poll.closed||Date.now()>=Date.parse(poll.closesAt))throw Error('poll_closed');if(poll.myOptionId!==null){poll.options.find(o=>o.id===poll.myOptionId).count--;poll.total--;}poll.myOptionId=b.optionId;if(b.optionId!==null){poll.options.find(o=>o.id===b.optionId).count++;poll.total++;}poll.version++;return {post:copy(p)};}
  if(action==='me')return {user};
  if(action==='posts.list')return {posts:copy(posts.filter(p=>(!b.category||b.category==='all'||p.category===b.category)&&(!b.section||b.section==='all'||(['help','study'].includes(p.category)?'daily':p.category)===b.section)&&(!b.interest||p.interest===b.interest)&&(!b.query||(p.title+p.body).includes(b.query))&&(b.scope!=='saved'||p.saved)&&(b.scope!=='mine'||p.author.mine)&&(b.scope!=='joined'||p.buddy?.joined)&&(b.scope!=='participated'||p.buddy?.joined||p.id==='post-1'||p.author.mine)&&(b.scope!=='watching'||p.watching)&&(b.scope!=='following'||!p.anonymous&&followed.has(p.author.id))&&(b.scope!=='author'||!p.anonymous&&p.author.id===b.memberId))),next:null};
  if(action==='posts.get'){p.newReplyCount=0;return {post:copy(p),comments:copy(comments.filter(c=>c.postId===b.postId)),next:null};}
  if(action==='notifications.unread')return {unreadCount:unread()};
  if(action==='notifications.list')return {notifications:copy(notifications.filter(n=>!b.filter||b.filter==='all'||(b.filter==='likes'?n.kind.endsWith('like'):!n.kind.endsWith('like')))),next:null,unreadCount:unread()};
  if(action==='notifications.read'){for(const n of notifications)if(b.ids.includes(n.id))n.readAt||=new Date().toISOString();return {unreadCount:unread()};}
  if(action==='threads.watch'){p.watching=!!b.enabled;return {post:copy(p)};}
  if(action==='comments.context'){return {context:copy(comments.find(c=>c.postId===b.postId&&(c.id===b.commentId||c.replies.some(r=>r.id===b.commentId))))};}
  if(action==='follows.set'){if(b.enabled)followed.set(b.memberId,followed.get(b.memberId)||new Date().toISOString());else followed.delete(b.memberId);return request('profile.get',b);}
  if(action==='follows.list')return {following:[...followed].map(([id,followedAt])=>({id,nickname:posts.find(p=>p.author.id===id)?.author.name||'同学',bio:'把校园里的小事，留在这里。',followedAt})),next:null};
  if(action==='profile.get'){const a=posts.find(p=>p.author.id===b.memberId)?.author;return {profile:{id:b.memberId,following:followed.has(b.memberId),nickname:a?.name||user.nickname,bio:'把校园里的小事，留在这里。',postCount:posts.filter(p=>!p.anonymous&&p.author.id===b.memberId).length}};}
  if(action==='media.url')return {image:copy(p?.images.find(i=>i.id===b.imageId)||posts.flatMap(p=>p.images).find(i=>i.id===b.imageId))};
  if(action==='reactions.set'){if(b.kind==='like'){p.likeCount+=b.enabled===p.liked?0:b.enabled?1:-1;p.liked=b.enabled;}else p.saved=b.enabled;return {post:copy(p)};}
  if(action==='comments.replies')return {comments:copy(comments.find(c=>c.id===b.rootId)?.replies||[]),next:null};
  if(action==='comments.like'){const c=comments.flatMap(c=>[c,...c.replies||[]]).find(c=>c.id===b.commentId);c.likeCount+=b.enabled===c.liked?0:b.enabled?1:-1;c.liked=b.enabled;return {comment:copy(c)};}
  if(action==='comments.create'){const c={id:crypto.randomUUID(),postId:b.postId,body:b.body,images:(b.images||[]).map(id=>uploaded.get(id)),author:{name:b.anonymous?'匿名同学 · 晴天':user.nickname,anonymous:!!b.anonymous,mine:true},createdAt:new Date().toISOString(),replyTo:b.replyTo,rootId:null,deleted:false,isOriginalPoster:p.author.mine,likeCount:0,liked:false,replyCount:0,replies:[]};if(b.replyTo){const root=comments.find(c=>c.id===b.replyTo||c.replies.some(r=>r.id===b.replyTo));c.rootId=root.id;root.replies.push(c);root.replyCount++;}else comments.push(c);p.commentCount++;return {comment:copy(c)};}
  if(action==='media.upload'){const image={id:b.requestId,url:'data:image/jpeg;base64,'+b.data,width:b.purpose==='avatar'?512:1200,height:b.purpose==='avatar'?512:800};uploaded.set(image.id,image);return {image};}
  if(action==='media.discard')return {};
  if(action==='posts.create'){const p=post(crypto.randomUUID(),b.anonymous?'匿名同学 · 晴天':user.nickname,b.title,b.body,b.category,b.anonymous,b.images.map(id=>uploaded.get(id)));if(b.buddy)p.buddy={...b.buddy,version:0,count:0,joined:false,closed:false,expired:false};if(b.poll)p.poll={version:0,question:b.poll.question,options:b.poll.options.map((text,i)=>({id:String(i),text,count:0})),total:0,myOptionId:null,closed:false,closesAt:new Date(Date.now()+b.poll.durationHours*3600000).toISOString()};p.interest=b.interest||'';p.createdAt=new Date().toISOString();p.author.mine=true;if(!p.anonymous){p.author.id=user.id;p.author.avatar=user.avatar;}p.watching=true;p.likeCount=0;posts.unshift(p);return {post:copy(p)};}
  if(action==='posts.delete'){posts.splice(posts.findIndex(p=>p.id===b.postId),1);return {};}
  if(action==='reports.create'||action==='blocks.clear')return {};
  if(action==='profile.update'){user.nickname=b.nickname;user.bio=b.bio||'';return {user};}
  throw Error('invalid_request');
 }
 const uploaded=new Map();
 window.androidBridge={};window.Capacitor={PluginHeaders:[{name:'Treehole',methods:[{name:'request',rtype:'promise'}]}],nativePromise:async(plugin,method,args)=>request(args.action,args.body)};
}
