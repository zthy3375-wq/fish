// Deliberate private-test activation only; never publishes an APK or update manifest.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,chmodSync,unlinkSync} from 'node:fs';
import {createHmac,randomBytes,randomUUID} from 'node:crypto';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {cloudMedia} from '../../cloudbase/functions/community/media.mjs';
import jpeg from '../../cloudbase/functions/community/node_modules/jpeg-js/index.js';
import {createCommunity} from '../../cloudbase/functions/community/core.mjs';
const envId='hanyuantong-d8gjzt1jh12370215',region='ap-shanghai';
const base=`https://${envId}-1527874185.${region}.app.tcloudbase.com/hyt-community`;
const activation=JSON.parse(readFileSync('cloudbase/community-test-deploy.json','utf8'));
if(activation.mode!=='private-treehole-test'||activation.service!=='hyt-community'||activation.registration!=='invite'||!/^[0-9a-f]{64}$/.test(activation.inviteHash))throw Error('Invalid private-test activation');
if(process.env.GITHUB_REF&&!['refs/heads/feature/treehole-accounts-20261114','refs/heads/deploy/community-test12-20261116'].includes(process.env.GITHUB_REF))throw Error('Unexpected deployment branch');
const key=process.env.CLOUDBASE_API_KEY?.trim();if(!key)throw Error('CloudBase deployment key unavailable');
const response=await fetch(`https://${envId}.${region}.tcb-api.tencentcloudapi.com/capi/credential`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({env:envId}),signal:AbortSignal.timeout(25000)});
const envelope=await response.json();if(envelope.code!==0)throw Error('CloudBase credential exchange failed');const credentials=envelope.data;
const rateSalt=createHmac('sha256',key).update('hyt-community-rate-v1').digest('hex');
const privateValues=[key,credentials.Token,credentials.TmpSecretKey,credentials.TmpSecretId,rateSalt].filter(Boolean);
const redact=s=>privateValues.reduce((value,secret)=>value.replaceAll(secret,'[redacted]'),s);
const childEnv={...process.env,CLOUDBASE_API_KEY:'',TENCENTCLOUD_SECRETID:credentials.TmpSecretId,TENCENTCLOUD_SECRETKEY:credentials.TmpSecretKey,TENCENTCLOUD_SESSIONTOKEN:credentials.Token};
function cli(args){const r=spawnSync('tcb',[...args,'-e',envId,'-r',region],{env:childEnv,encoding:'utf8',timeout:300000,maxBuffer:4*1024*1024});if(r.status!==0){console.error(redact((r.stderr||'')+(r.stdout||'')));throw Error('CloudBase operation failed: '+args.slice(0,2).join(' '));}return r.stdout;}
// Identify the HTTP database role and explicitly deny its implicit table grants.
const identityResponse=await fetch(`https://${envId}.api.tcloudbasegateway.com/v1/rdb/exec-pgsql`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({sql:'SELECT current_user AS role',parameters:[]}),signal:AbortSignal.timeout(20000)});
const identity=await identityResponse.json(),dbRole=identity[0]?.role;
if(!/^[a-zA-Z0-9_-]{1,120}$/.test(dbRole||'')||['anon','authenticated','public'].includes(dbRole))throw Error('Unable to verify database role');
// One transaction, only hyt_ community objects. Existing analytics/academic rows are untouched.
const schema=readFileSync('cloudbase/community-schema.sql','utf8');
cli(['db','execute','--sql','BEGIN;\n'+schema+`\nDO $$ DECLARE obj record; BEGIN
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN
 ('hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_thread_aliases','hyt_reactions','hyt_blocks','hyt_hidden_threads','hyt_reports','hyt_moderation','hyt_community_rate','hyt_media','hyt_comment_likes','hyt_thread_watches','hyt_thread_visits','hyt_notifications','hyt_responses','hyt_follows','hyt_polls','hyt_poll_votes','hyt_buddies','hyt_buddy_members') LOOP
 EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,'${dbRole}'); END LOOP;
 FOR obj IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('hyt_community','hyt_member_json','hyt_author_json','hyt_post_json','hyt_comment_json','hyt_media_json','hyt_visible_notifications','hyt_notification_json','hyt_notify_comment','hyt_avatar_json','hyt_profile_json','hyt_poll_json','hyt_comment_image_visible','hyt_buddy_json') LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.signature,'${dbRole}'); END LOOP; END $$;\nCOMMIT;`,'--json']);
console.log('Community schema installed with direct-client access denied');
await cloudMedia({env:envId,key}).ensureBucket();
cli(['db','execute','--sql',`BEGIN;
DROP POLICY IF EXISTS hyt_community_private_objects ON storage.objects;
CREATE POLICY hyt_community_private_objects ON storage.objects AS RESTRICTIVE FOR ALL TO anon,authenticated USING(bucket_id<>'hyt-community') WITH CHECK(bucket_id<>'hyt-community');
DROP POLICY IF EXISTS hyt_community_private_bucket ON storage.buckets;
CREATE POLICY hyt_community_private_bucket ON storage.buckets AS RESTRICTIVE FOR ALL TO anon,authenticated USING(id<>'hyt-community') WITH CHECK(id<>'hyt-community');
COMMIT;`,'--json']);

const config={envId,functionRoot:'cloudbase/functions',functions:[{name:'hyt-community',type:'HTTP',runtime:'Nodejs20.19',timeout:30,memorySize:512,installDependency:false,public:true,gatewayPath:'/hyt-community',envVariables:{CLOUDBASE_ENV_ID:envId,CLOUDBASE_APIKEY:key,COMMUNITY_REGISTRATION:'open',COMMUNITY_INVITE_HASH:activation.inviteHash,COMMUNITY_RATE_SALT:rateSalt}}]};
writeFileSync('cloudbaserc.json',JSON.stringify(config),{mode:0o600});chmodSync('cloudbase/functions/community/scf_bootstrap',0o755);
try{cli(['fn','deploy','hyt-community','--httpFn','--dir','cloudbase/functions/community','--force','--json']);}finally{unlinkSync('cloudbaserc.json');}
let configuration;
for(let attempt=0;attempt<12;attempt++){
 try{configuration=await fetch(base+'/v1/config',{signal:AbortSignal.timeout(10000)}).then(async r=>({ok:r.ok,value:await r.json()}));}catch{configuration=null;}
 if(configuration?.ok&&configuration.value.registrationEnabled&&configuration.value.requiresInvite&&configuration.value.imagesEnabled&&configuration.value.schema===8&&configuration.value.engagementEnabled===true&&configuration.value.avatarsEnabled===true&&configuration.value.responsesEnabled===true&&configuration.value.discoveryEnabled===true&&configuration.value.followingEnabled===true&&configuration.value.pollsEnabled===true&&configuration.value.commentImagesEnabled===true&&configuration.value.buddiesEnabled===true)break;
 await new Promise(resolve=>setTimeout(resolve,2500));
}
if(!configuration?.ok||!configuration.value.registrationEnabled||!configuration.value.requiresInvite||!configuration.value.imagesEnabled||configuration.value.schema!==8||configuration.value.engagementEnabled!==true||configuration.value.avatarsEnabled!==true||configuration.value.responsesEnabled!==true||configuration.value.discoveryEnabled!==true||configuration.value.followingEnabled!==true||configuration.value.pollsEnabled!==true||configuration.value.commentImagesEnabled!==true||configuration.value.buddiesEnabled!==true)throw Error('Invite gate did not activate');
const http=async(action,body={},token='')=>{const r=await fetch(base+'/v1/'+action,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});return {status:r.status,body:await r.json()};};
if((await http('posts.list')).status!==401)throw Error('Anonymous read access unexpectedly enabled');
if((await http('credentials',{username:'test'})).status!==404)throw Error('Internal endpoint was exposed');
if((await http('register',{username:'invalid_invite_test',nickname:'测试',password:'invalid-invite-password',agreed:true,invite:'wrong'})).status!==403)throw Error('Registration gate failed');
// Create disposable accounts through the exact core with the privileged server adapter.
process.env.CLOUDBASE_ENV_ID=envId;process.env.CLOUDBASE_APIKEY=key;
const db=async(a,b,t)=>(await sql('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t]))[0]?.result;
const local=createCommunity({db,storage:cloudMedia({env:envId,key}),registrationEnabled:true,rateSalt});
const testAccounts=[];const testPosts=[];
try{
 for(let i=0;i<3;i++){
  const password=randomBytes(24).toString('base64url');const r=await local.execute('register',{username:'smoke_'+randomBytes(6).toString('hex'),nickname:'联调测试'+i,password,agreed:true},'','deployment');
  testAccounts.push({...r,password});
 }
 const [author,reader,other]=testAccounts;
 const fixture=jpeg.encode({width:4,height:4,data:Buffer.alloc(4*4*4,125)},75).data;
 const uploaded=await http('media.upload',{data:fixture.toString('base64'),requestId:randomUUID()},author.sessionToken);
 if(uploaded.status!==200||!uploaded.body.image?.url)throw Error('Live image upload failed');
 const actual=await fetch(uploaded.body.image.url);if(!actual.ok||(await actual.arrayBuffer()).byteLength<10)throw Error('Live image read failed');
 const created=await http('posts.create',{title:'分区图文联调',category:'study',images:[uploaded.body.image.id],body:'[自动联调测试，完成即清理]',anonymous:true,requestId:randomUUID()},author.sessionToken);
 if(created.status!==201)throw Error('Live post creation failed');testPosts.push(created.body.post.id);
 const seen=await http('posts.get',{postId:created.body.post.id},reader.sessionToken);
 if(seen.body.post?.category!=='study'||seen.body.post?.images?.length!==1)throw Error('Live image post projection failed');
 if(seen.status!==200||seen.body.post.author.mine||JSON.stringify(seen.body).includes(author.user.id)||JSON.stringify(seen.body).includes(author.user.nickname))throw Error('Live anonymity projection failed');
 if((await http('posts.delete',{postId:created.body.post.id},reader.sessionToken)).status!==403)throw Error('Live ownership enforcement failed');
 const commented=await http('comments.create',{postId:created.body.post.id,body:'[联调评论]',anonymous:false,requestId:randomUUID()},author.sessionToken);
 if(commented.status!==201||!commented.body.comment.author.anonymous)throw Error('Live anonymous-author reply failed');
 const nested=await http('comments.create',{postId:created.body.post.id,body:'[楼中楼联调]',anonymous:false,replyTo:commented.body.comment.id,requestId:randomUUID()},reader.sessionToken);
 if(nested.status!==201||nested.body.comment.rootId!==commented.body.comment.id)throw Error('Live thread grouping failed');
 const threaded=await http('posts.get',{postId:created.body.post.id,threaded:true},reader.sessionToken);
 if(threaded.body.comments?.[0]?.replies?.length!==1)throw Error('Live reply preview failed');
 const inbox=await http('notifications.list',{},author.sessionToken);
 if(inbox.status!==200||inbox.body.notifications?.length!==1||inbox.body.notifications[0].commentId!==nested.body.comment.id)throw Error('Live reply notification failed');
 const selected=inbox.body.notifications[0];
 const context=await http('comments.context',{postId:created.body.post.id,commentId:selected.commentId},author.sessionToken);
 if(context.body.context?.replies?.[0]?.id!==selected.commentId)throw Error('Live notification context failed');
 await http('notifications.read',{ids:[selected.id]},author.sessionToken);
 if((await http('notifications.unread',{},author.sessionToken)).body.unreadCount!==0)throw Error('Live read-state failed');
 const profile=await http('posts.list',{scope:'author',memberId:author.user.id},reader.sessionToken);
 if(profile.body.posts?.some(p=>p.id===created.body.post.id))throw Error('Anonymous post leaked through profile');
 // Explicit test.8 verification on disposable identities only.
 const avatar=await http('media.upload',{data:fixture.toString('base64'),purpose:'avatar',requestId:randomUUID()},reader.sessionToken);
 if(avatar.status!==200||avatar.body.image?.width!==avatar.body.image?.height)throw Error('Live avatar upload failed');
 const avatarSet=await http('avatar.set',{imageId:avatar.body.image.id},reader.sessionToken);
 if(avatarSet.body.user?.avatar?.id!==avatar.body.image.id)throw Error('Live avatar confirmation failed');
 if((await http('avatar.set',{imageId:avatar.body.image.id},author.sessionToken)).status!==400)throw Error('Avatar ownership check failed');
 const publicReader=await http('profile.get',{memberId:reader.user.id},author.sessionToken);
 if(publicReader.body.profile?.avatar?.id!==avatar.body.image.id)throw Error('Live avatar public projection failed');
 const named=await http('posts.create',{body:'[公开头像联调，完成即清理]',anonymous:false,requestId:randomUUID()},reader.sessionToken);
 if(named.status!==201)throw Error('Live named avatar post failed');testPosts.push(named.body.post.id);
 if(named.body.post.author.avatar?.id!==avatar.body.image.id)throw Error('Live named author avatar missing');
 const anonReply=await http('comments.create',{postId:created.body.post.id,body:'[匿名头像隔离联调]',anonymous:true,requestId:randomUUID()},reader.sessionToken);
 if(anonReply.status!==201||'avatar' in anonReply.body.comment.author||'id' in anonReply.body.comment.author)throw Error('Live avatar anonymity failed');
 for(const kind of ['same','same','hug']){const r=await http('responses.set',{postId:created.body.post.id,kind},reader.sessionToken);if(r.status!==200||r.body.post.myResponse!==kind||r.body.post.responseCounts[kind]!==1||Object.values(r.body.post.responseCounts).reduce((n,x)=>n+x,0)!==1)throw Error('Live response switch/idempotence failed');}
 const responseNotices=(await http('notifications.list',{filter:'likes'},author.sessionToken)).body.notifications;
 const responseNotice=responseNotices?.find(n=>n.kind==='post_response');
 if(!responseNotice||responseNotice.excerpt!=='抱抱'||responseNotice.actor.name!=='一位同学'||'avatar' in responseNotice.actor||'id' in responseNotice.actor)throw Error('Live response privacy failed');
 await http('notifications.read',{ids:[responseNotice.id]},author.sessionToken);
 await http('responses.set',{postId:created.body.post.id,kind:'useful'},reader.sessionToken);
 const updatedNotice=(await http('notifications.list',{filter:'likes'},author.sessionToken)).body.notifications.find(n=>n.kind==='post_response');
 if(updatedNotice?.id!==responseNotice.id||!updatedNotice.readAt)throw Error('Live response read-state failed');
 const cancelled=await http('responses.set',{postId:created.body.post.id,kind:null},reader.sessionToken);
 if(cancelled.body.post?.myResponse!==null||Object.keys(cancelled.body.post.responseCounts).length)throw Error('Live response cancellation failed');
 if((await http('notifications.list',{filter:'likes'},author.sessionToken)).body.notifications.some(n=>n.kind==='post_response'))throw Error('Cancelled response notice remains visible');
 await http('avatar.set',{imageId:null},reader.sessionToken);
 if((await http('me',{},reader.sessionToken)).body.user?.avatar!==null)throw Error('Live avatar removal failed');
 const discovery=await http('posts.create',{category:'entertainment',interest:'games',body:'[兴趣筛选联调，完成即清理]',anonymous:false,requestId:randomUUID()},author.sessionToken);
 if(discovery.status!==201||discovery.body.post.interest!=='games')throw Error('Live discovery publish failed');testPosts.push(discovery.body.post.id);
 const games=await http('posts.list',{scope:'mine',section:'entertainment',interest:'games',query:'兴趣筛选'},author.sessionToken);
 if(games.body.posts?.length!==1||games.body.posts[0].id!==discovery.body.post.id)throw Error('Live discovery filter failed');
 const oldStudy=await http('posts.list',{scope:'mine',section:'daily',category:'study'},author.sessionToken);
 if(!oldStudy.body.posts?.some(p=>p.id===created.body.post.id&&p.category==='study'&&p.anonymous))throw Error('Live legacy study preservation failed');
 if((await http('posts.create',{category:'treehole',body:'[不得创建的实名树洞]',anonymous:false,requestId:randomUUID()},author.sessionToken)).status!==400)throw Error('Anonymous section identity guard failed');
 const quiet=await http('posts.create',{category:'treehole',body:'[匿名分区联调，完成即清理]',anonymous:true,requestId:randomUUID()},author.sessionToken);
 if(quiet.status!==201||'id' in quiet.body.post.author||'avatar' in quiet.body.post.author)throw Error('Live anonymous section failed');testPosts.push(quiet.body.post.id);
 const quietReply=await http('comments.create',{postId:quiet.body.post.id,body:'[树洞匿名回复联调]',anonymous:false,requestId:randomUUID()},reader.sessionToken);
 if(quietReply.status!==201||!quietReply.body.comment.author.anonymous||'id' in quietReply.body.comment.author)throw Error('Live anonymous section reply failed');
 const followed=await http('follows.set',{memberId:author.user.id,enabled:true},reader.sessionToken);
 if(followed.body.profile?.following!==true)throw Error('Live follow failed');
 const followingFeed=await http('posts.list',{scope:'following'},reader.sessionToken);
 if(!followingFeed.body.posts?.some(p=>p.id===discovery.body.post.id)||followingFeed.body.posts.some(p=>p.anonymous))throw Error('Live following privacy failed');
 const followingList=await http('follows.list',{},reader.sessionToken);
 if(followingList.body.following?.[0]?.id!==author.user.id||'username' in followingList.body.following[0])throw Error('Live private following list failed');
 await http('follows.set',{memberId:author.user.id,enabled:false},reader.sessionToken);
 if((await http('posts.list',{scope:'following'},reader.sessionToken)).body.posts?.length!==0)throw Error('Live unfollow failed');
 const pollBody={body:'',anonymous:true,requestId:randomUUID(),poll:{question:'[投票联调，完成即清理]',options:['选项甲','选项乙'],durationHours:24}};
 const pollCreated=await http('posts.create',pollBody,author.sessionToken);
 if(pollCreated.status!==201||pollCreated.body.post.poll?.total!==0)throw Error('Live poll creation failed');
 const pollId=pollCreated.body.post.id;testPosts.push(pollId);
 const repeated=await http('posts.create',pollBody,author.sessionToken);
 if(repeated.body.post?.id!==pollId||repeated.body.post.poll.closesAt!==pollCreated.body.post.poll.closesAt)throw Error('Live poll retry changed definition/deadline');
 for(const optionId of ['0','0','1',null]){
  const voted=await http('polls.vote',{postId:pollId,optionId},reader.sessionToken);
  if(voted.status!==200||voted.body.post?.poll?.myOptionId!==optionId||voted.body.post.poll.total!==(optionId===null?0:1))throw Error('Live vote select/switch/cancel failed');
  if(JSON.stringify(voted.body.post.poll).includes(reader.user.id)||JSON.stringify(voted.body.post.poll).includes(reader.user.nickname))throw Error('Live voter privacy failed');
 }
 const commentImage=await http('media.upload',{data:fixture.toString('base64'),purpose:'comment',requestId:randomUUID()},reader.sessionToken);
 if(commentImage.status!==200)throw Error('Live comment upload failed');
 const imageBody={postId:pollId,body:'',images:[commentImage.body.image.id],anonymous:true,requestId:randomUUID()};
 const imageComment=await http('comments.create',imageBody,reader.sessionToken);
 if(imageComment.status!==201||imageComment.body.comment?.images?.length!==1||'id' in imageComment.body.comment.author)throw Error('Live image-only comment failed');
 const retryComment=await http('comments.create',imageBody,reader.sessionToken);
 if(retryComment.body.comment?.id!==imageComment.body.comment.id)throw Error('Live image comment retry duplicated');
 const projected=await http('posts.get',{postId:pollId,threaded:true},author.sessionToken);
 if(projected.body.post.images?.length!==0||projected.body.comments?.[0]?.images?.length!==1)throw Error('Live comment attachment projection failed');
 const renewed=await http('media.url',{postId:pollId,imageId:commentImage.body.image.id},author.sessionToken);
 if(renewed.status!==200||!(await fetch(renewed.body.image.url)).ok)throw Error('Live comment image URL failed');
 const deletedImageComment=await http('comments.delete',{postId:pollId,commentId:imageComment.body.comment.id},reader.sessionToken);
 if(deletedImageComment.status!==200)throw Error('Live comment delete request failed');
 if((await http('media.url',{postId:pollId,imageId:commentImage.body.image.id},author.sessionToken)).status===200)throw Error('Deleted comment image remained accessible');
 const buddyBody={category:'buddies',body:'[搭子联调，完成即清理]',anonymous:true,requestId:randomUUID(),buddy:{location:'合成集合点',startsAt:new Date(Date.now()+3600000).toISOString(),capacity:1}};
 const buddyCreated=await http('posts.create',buddyBody,author.sessionToken);
 if(buddyCreated.status!==201||buddyCreated.body.post.buddy?.count!==0)throw Error('Live buddy creation failed');
 const buddyId=buddyCreated.body.post.id;testPosts.push(buddyId);
 if((await http('posts.create',buddyBody,author.sessionToken)).body.post?.id!==buddyId)throw Error('Live buddy publish retry failed');
 const racers=await Promise.all([reader,other].map(u=>http('buddies.join',{postId:buddyId,enabled:true},u.sessionToken)));
 if(racers.filter(r=>r.status===200).length!==1||racers.filter(r=>r.body.error==='buddy_full').length!==1)throw Error('Live buddy last-seat race failed');
 const winner=racers[0].status===200?reader:other;
 const joined=await http('buddies.join',{postId:buddyId,enabled:true},winner.sessionToken);
 if(joined.body.post?.buddy?.count!==1||!joined.body.post.buddy.joined)throw Error('Live buddy join retry failed');
 const roster=await http('buddies.members',{postId:buddyId},author.sessionToken);
 if(roster.body.participants?.length!==1||roster.body.participants[0].id!==winner.user.id||'username' in roster.body.participants[0])throw Error('Live buddy roster failed');
 if((await http('buddies.members',{postId:buddyId},winner.sessionToken)).status!==403)throw Error('Live buddy roster privacy failed');
 if(!(await http('posts.list',{scope:'joined'},winner.sessionToken)).body.posts?.some(p=>p.id===buddyId))throw Error('Live joined feed failed');
 const closed=await http('buddies.close',{postId:buddyId,closed:true},author.sessionToken);
 if(!closed.body.post?.buddy?.closed)throw Error('Live buddy close failed');
 const buddyNotices=(await http('notifications.list',{filter:'replies'},winner.sessionToken)).body.notifications?.filter(n=>n.kind==='buddy'&&n.postId===buddyId);
 if(buddyNotices?.length!==1||'id' in buddyNotices[0].actor||'avatar' in buddyNotices[0].actor)throw Error('Live buddy notification privacy failed');
 const left=await http('buddies.join',{postId:buddyId,enabled:false},winner.sessionToken);
 if(left.body.post?.buddy?.count!==0||left.body.post.buddy.joined)throw Error('Live buddy cancellation failed');
 if((await http('buddies.close',{postId:buddyId,closed:false},author.sessionToken)).body.post?.buddy?.closed!==false)throw Error('Live buddy reopen failed');
 console.log('Live test.12 buddy checks passed: immutable publish retry, simultaneous last seat, private roster, joined feed, notifications, close/reopen and cancellation');
 console.log('Live test.11 checks passed: poll-only publish/retry, immutable deadline, select/switch/cancel, voter privacy, image-only comment/retry/projection/URL and delete');
 console.log('Live test.10 checks passed: follow/unfollow, viewer-owned list, public following feed and anonymous exclusion');
 console.log('Live test.9 checks passed: interest publication/filter/search, legacy study category and identity preserved, anonymous section guard');
 console.log('Live test.8 checks passed: avatar upload/confirmation/public projection/ownership/removal, anonymous avatar isolation, response select/switch/cancel/retry, generic notice/read state');
 console.log('Live HTTP/PG checks passed: inbox, notification context, read-state, private profile, images, categories, threads, invite gate, login boundary, posts, cross-account anonymity, deletion ownership, comments');
}finally{
 for(const u of testAccounts){await local.execute('account.delete',{password:u.password},u.sessionToken,'deployment');}
 // Verify every disposable image is removed before deleting its metadata, retrying transient storage failures.
 const media=cloudMedia({env:envId,key});
 for(const u of testAccounts){
  const rows=await sql('SELECT object_key FROM hyt_media WHERE member_id=$1::uuid',[u.user.id]);
  for(const row of rows){let removed=false;for(let attempt=0;attempt<3;attempt++){try{await media.remove(row.object_key);removed=true;break;}catch{await new Promise(r=>setTimeout(r,500));}}if(!removed)throw Error('Disposable image cleanup failed; metadata retained');}
  await sql('DELETE FROM hyt_media WHERE member_id=$1::uuid',[u.user.id]);
 }
 // Remove only these generated test identities/content, never real user rows.
 for(const pid of testPosts){await sql('DELETE FROM hyt_buddy_members WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_buddies WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_poll_votes WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_polls WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_responses WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_notifications WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_thread_watches WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_thread_visits WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_comment_likes WHERE comment_id IN (SELECT id FROM hyt_comments WHERE post_id=$1::uuid)',[pid]);await sql('DELETE FROM hyt_media WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_thread_aliases WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_comments WHERE post_id=$1::uuid',[pid]);await sql('DELETE FROM hyt_posts WHERE id=$1::uuid',[pid]);}
 for(const u of testAccounts)await sql('DELETE FROM hyt_members WHERE id=$1::uuid AND deleted_at IS NOT NULL',[u.user.id]);
}
console.log('Disposable accounts, posts, comments, poll votes and media cleared');
console.log(JSON.stringify({service:'hyt-community',mode:'invite-only',apkPublished:false,updateChannelChanged:false}));
