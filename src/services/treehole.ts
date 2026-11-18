import type {Identity,HonorHall,AdminMember,HonorLog} from '../domain/communityHonors';
import {Capacitor,registerPlugin} from '@capacitor/core';
export interface TreeholeUser {showcase?:string[];badges?:Identity;caps?:string[];id:string;username:string;nickname:string;role:'member'|'moderator';bannedUntil:string|null;bio?:string;avatar?:TreeholeImage|null}
export interface TreeholeAuthor {badges?:Identity;id?:string;name:string;anonymous:boolean;mine:boolean;avatar?:TreeholeImage|null}
export interface TreeholeImage {id:string;url:string|null;width:number;height:number}
export interface TreeholePollDraft {question:string;options:string[];durationHours:number}
export interface TreeholePoll {version:number;question:string;options:Array<{id:string;text:string;count:number}>;total:number;myOptionId:string|null;closesAt:string;closed:boolean}
export interface TreeholeBuddyDraft {location:string;startsAt:string;capacity:number}
export interface TreeholeBuddy extends TreeholeBuddyDraft {version:number;count:number;joined:boolean;closed:boolean;expired:boolean}
export interface TreeholeBuddyMember {id:string;nickname:string;avatar?:TreeholeImage|null;joinedAt:string}
export type TreeholeResponseKind='same'|'hug'|'useful'|'joy';
export interface TreeholePost {buddy?:TreeholeBuddy|null;poll?:TreeholePoll|null;title?:string;category?:string;interest?:string;images?:TreeholeImage[];id:string;body:string;anonymous:boolean;author:TreeholeAuthor;createdAt:string;locked:boolean;commentCount:number;likeCount:number;liked:boolean;saved:boolean;watching?:boolean;newReplyCount?:number;myResponse?:TreeholeResponseKind|null;responseCounts?:Partial<Record<TreeholeResponseKind,number>>}
export interface TreeholeComment {images?:TreeholeImage[];rootId?:string|null;replies?:TreeholeComment[];replyCount?:number;likeCount?:number;liked?:boolean;id:string;postId:string;body:string;author:TreeholeAuthor;createdAt:string;replyTo:string|null;deleted:boolean;isOriginalPoster:boolean}
export interface TreeholeReport {id:string;postId:string;commentId:string|null;body:string;reason:string;createdAt:string}
export interface TreeholeNotification {id:string;kind:'reply'|'post_reply'|'thread_reply'|'post_like'|'comment_like'|'post_response'|'buddy';postId:string;commentId:string|null;rootId:string|null;actor:TreeholeAuthor;postTitle:string;excerpt:string;createdAt:string;readAt:string|null}
export interface TreeholeProfile {showcase?:string[];badges?:Identity;id:string;nickname:string;bio:string;postCount:number;following?:boolean;avatar?:TreeholeImage|null}
export interface TreeholeFollow {id:string;nickname:string;bio:string;followedAt:string;following?:boolean;avatar?:TreeholeImage|null}
export interface TreeholeSocial {followingCount:number;followerCount:number}
export interface TreeholeConversation {id:string;member:{id:string;nickname:string;avatar?:TreeholeImage|null};lastSeq:string;updatedAt:string;lastMessage:string|null;unreadCount:number}
export interface TreeholeMessage {id:string;seq:string;body:string;mine:boolean;createdAt:string;requestId:string|null}
export interface TreeholeMessageDraft {body:string;requestId:string;failed?:boolean}
export interface TreeholeModeration {id:string;postId:string|null;commentId:string|null;action:string;reason:string;operator:string|null;createdAt:string}
export interface TreeholeResult {updatedIdentity?:{id:string;badges:Identity;showcase:string[]};awardOwner?:string;unlocks?:string[];honorsEnabled?:boolean;hall?:HonorHall;members?:AdminMember[];audit?:HonorLog[];config?:TreeholeResult;simpleRegistration?:boolean;combinedUnread?:boolean;boardsEnabled?:boolean;moderationEnabled?:boolean;removed?:boolean;history?:TreeholeModeration[];responseKinds?:TreeholeResponseKind[];socialEnabled?:boolean;messagesEnabled?:boolean;social?:TreeholeSocial;followers?:TreeholeFollow[];conversations?:TreeholeConversation[];conversation?:TreeholeConversation;messages?:TreeholeMessage[];message?:TreeholeMessage;messageUnreadCount?:number;buddiesEnabled?:boolean;participants?:TreeholeBuddyMember[];pollsEnabled?:boolean;commentImagesEnabled?:boolean;followingEnabled?:boolean;following?:TreeholeFollow[];discoveryEnabled?:boolean;avatarsEnabled?:boolean;responsesEnabled?:boolean;image?:TreeholeImage;imagesEnabled?:boolean;user?:TreeholeUser;post?:TreeholePost;comment?:TreeholeComment;posts?:TreeholePost[];comments?:TreeholeComment[];reports?:TreeholeReport[];next?:Record<string,string>|null;recoveryCode?:string;registrationEnabled?:boolean;requiresInvite?:boolean;engagementEnabled?:boolean;notifications?:TreeholeNotification[];unreadCount?:number;context?:TreeholeComment;focusCommentId?:string;profile?:TreeholeProfile}
const native=registerPlugin<{request(options:{action:string;body:Record<string,unknown>}):Promise<TreeholeResult>}>('Treehole');
const messages:Record<string,string>={owner_transfer_required:'请先由所有者办理开发者身份交接',invalid_showcase:'只能佩戴已获得的荣誉，成就最多展示三项',recommendation_required:'需先收到创作者推荐',permanent_honor:'种子用户荣誉永久保留',report_resolved:'这条举报已被处理，请刷新列表',conversation_unavailable:'这段私信暂不可用，对方可能已注销或双方已屏蔽',buddy_time:'请选择未来 90 天内的活动时间',buddy_full:'已经招满了，可以稍后再看看',buddy_closed:'已停止报名，仍可在帖子下继续交流',buddy_host:'发起人不占报名名额',poll_closed:'投票已截止，结果已保留',following_limit:'关注已达到上限，请先整理关注名单',
 invalid_image:'这张图片暂不支持，请换一张 JPG、PNG 或截图',image_too_large:'图片较大，请缩小后再添加',images_unavailable:'图片服务暂时不可用，请稍后重试',image_unavailable:'图片已过期或不可用，请移除后重新添加',upload_limit:'今天上传的图片较多，请明天再试',
 session_expired:'请登录邯院通账号',invalid_credentials:'账号、密码或恢复码不正确',username_unavailable:'这个登录账号已被使用，请换一个',
 invalid_username:'账号可用 1–32 个可见字符，例如中文、数字或邮箱。请去掉控制字符',password_length:'密码需为 10–128 位',
 invalid_request:'请检查填写内容和字数',agreement_required:'请先阅读并同意树洞规则',registration_closed:'树洞注册暂未开放',
 too_many_requests:'操作较频繁，请稍后重试',posting_too_fast:'发言较频繁，请休息一会儿',account_muted:'账号暂时禁言，可以继续浏览和管理自己的内容',
 not_found:'内容已删除、已隐藏或暂时不可用',forbidden:'你没有这项操作权限',post_locked:'这条讨论已暂停回复',reply_unavailable:'回复目标已删除，请重新选择',
 request_conflict:'这次提交的内容已变化，请重新打开编辑',network_unavailable:'连接失败，请检查网络后重试',temporarily_unavailable:'树洞服务暂时不可用，请稍后重试',
 secure_storage_failed:'无法安全保存登录状态，请重试',invalid_response:'服务返回异常，请稍后重试',native_required:'请在邯院通安装版中使用树洞',
};
export function treeholeError(error:unknown){const code=(error as {code?:string;message?:string})?.code||(error as Error)?.message;return messages[code]||'操作未完成，请稍后重试';}
export function treeholeErrorCode(error:unknown){return (error as {code?:string})?.code||(error as Error)?.message;}
export async function treeholeRequest(action:string,body:Record<string,unknown>={}):Promise<TreeholeResult>{
 if(!Capacitor.isPluginAvailable('Treehole'))throw new Error('native_required');
 return native.request({action,body:{...body,timeAwards:true}});
}
