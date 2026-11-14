import {Capacitor,registerPlugin} from '@capacitor/core';
export interface TreeholeUser {id:string;username:string;nickname:string;role:'member'|'moderator';bannedUntil:string|null}
export interface TreeholeAuthor {name:string;anonymous:boolean;mine:boolean}
export interface TreeholePost {id:string;body:string;anonymous:boolean;author:TreeholeAuthor;createdAt:string;locked:boolean;commentCount:number;likeCount:number;liked:boolean;saved:boolean}
export interface TreeholeComment {id:string;postId:string;body:string;author:TreeholeAuthor;createdAt:string;replyTo:string|null;deleted:boolean;isOriginalPoster:boolean}
export interface TreeholeReport {id:string;postId:string;commentId:string|null;body:string;reason:string;createdAt:string}
export interface TreeholeResult {user?:TreeholeUser;post?:TreeholePost;comment?:TreeholeComment;posts?:TreeholePost[];comments?:TreeholeComment[];reports?:TreeholeReport[];next?:Record<string,string>|null;recoveryCode?:string;registrationEnabled?:boolean;requiresInvite?:boolean}
const native=registerPlugin<{request(options:{action:string;body:Record<string,unknown>}):Promise<TreeholeResult>}>('Treehole');
const messages:Record<string,string>={
 session_expired:'请登录邯院通账号',invalid_credentials:'账号、密码或恢复码不正确',username_unavailable:'这个登录账号已被使用，请换一个',
 invalid_username:'登录账号需以字母开头，使用 4–24 位字母、数字或下划线',password_length:'密码需为 10–128 位',
 invalid_request:'请检查填写内容和字数',agreement_required:'请先阅读并同意树洞规则',registration_closed:'树洞注册暂未开放',invite_invalid:'内测邀请码不正确',
 too_many_requests:'操作较频繁，请稍后重试',posting_too_fast:'发言较频繁，请休息一会儿',account_muted:'账号暂时禁言，可以继续浏览和管理自己的内容',
 not_found:'内容已删除、已隐藏或暂时不可用',forbidden:'你没有这项操作权限',post_locked:'这条讨论已暂停回复',reply_unavailable:'回复目标已删除，请重新选择',
 request_conflict:'这次提交的内容已变化，请重新打开编辑',network_unavailable:'连接失败，请检查网络后重试',temporarily_unavailable:'树洞服务暂时不可用，请稍后重试',
 secure_storage_failed:'无法安全保存登录状态，请重试',invalid_response:'服务返回异常，请稍后重试',native_required:'请在邯院通安装版中使用树洞',
};
export function treeholeError(error:unknown){const code=(error as {code?:string;message?:string})?.code||(error as Error)?.message;return messages[code]||'操作未完成，请稍后重试';}
export function treeholeErrorCode(error:unknown){return (error as {code?:string})?.code||(error as Error)?.message;}
export async function treeholeRequest(action:string,body:Record<string,unknown>={}):Promise<TreeholeResult>{
 if(!Capacitor.isPluginAvailable('Treehole'))throw new Error('native_required');
 return native.request({action,body});
}
