import {BookHeart,Crown,Feather,Heart,HeartHandshake,LockKeyhole,MessageCircle,PenLine,ShieldCheck,Sparkles,Sprout,Star,Sunrise,UsersRound} from 'lucide-vue-next';
export const badges={
 developer:{short:'开发者',dark:'#e3b75c',name:'开发者',icon:Crown,color:'#97600a',tint:'#fff0ce',description:'邯院通的创建者。',method:'通过原始所有者授权记录和稳定账号 ID 核验，全平台唯一。'},
 moderator:{short:'管理员',dark:'#87b9f0',name:'管理员',icon:ShieldCheck,color:'#2762a6',tint:'#e8f2ff',description:'维护社区秩序，处理违规内容和举报。',method:'由开发者任命，权限按职责授予。'},
 seed:{short:'种子',dark:'#83c6a0',name:'种子用户',icon:Sprout,color:'#277449',tint:'#e3f4e8',description:'在社区刚萌芽时参与测试和建设的同学。',method:'由开发者授予，永久保留。'},
 creator:{short:'优质',dark:'#c0a2ee',name:'优质创作者',icon:Sparkles,color:'#7042ae',tint:'#f1e9fc',description:'持续为同学分享值得收藏的作品。',method:'管理员推荐，由开发者审核授予。'},
 contributor:{short:'贡献者',dark:'#f0a1ba',name:'社区贡献者',icon:HeartHandshake,color:'#a33f66',tint:'#fce9f0',description:'用反馈、建议或实际帮助改善社区。',method:'开发者核实贡献后授予。'}
};
export type BadgeCode=keyof typeof badges;
export type Badge={code:BadgeCode;at:string|null};
export function visibleBadges(items:(Badge|null|undefined)[],full=false):Badge[]{
  const valid=items.filter((b):b is Badge=>!!b&&Object.prototype.hasOwnProperty.call(badges,b.code));
  const unique=valid.filter((b,i)=>valid.findIndex(x=>x.code===b.code)===i);
  const official=unique.find(b=>b.code==='developer')??unique.find(b=>b.code==='moderator');
  const honors=unique.filter(b=>b.code!=='developer'&&b.code!=='moderator');
  return [...(official?[official]:[]),...(full?honors:honors.slice(0,1))];
}
export type Identity={official?:Badge|null;worn?:Badge|null;collection?:import("./honorCollection").CollectionBadge|null};
export const awards=[
 {code:'arrival',name:'初来乍到',icon:Sunrise,condition:'首次注册邯院通社区账号',description:'欢迎来到邯院的这一角。',metric:'registered',goal:1,tier:'普通'},
 {code:'firstpost',name:'第一声',icon:PenLine,condition:'发布第一篇有效帖子',description:'你在邯院通留下了第一篇帖子。',metric:'posts',goal:1,tier:'普通'},
 {code:'hello',name:'打个招呼',icon:MessageCircle,condition:'发表第一条有效评论',description:'一场讨论，因为你多了一句话。',metric:'threads',goal:1,tier:'普通'},
 {code:'liked',name:'有人喜欢',icon:Heart,condition:'收到其他同学的第一个有效赞',description:'有人喜欢你留下的内容。',metric:'likes',goal:1,tier:'普通'},
 {code:'sprout',name:'开始发芽',icon:Sprout,condition:'累计发布 5 篇有效帖子',description:'第五篇帖子，你的故事还在生长。',metric:'posts',goal:5,tier:'普通'},
 {code:'neighbor',name:'校园邻居',icon:UsersRound,condition:'在 10 篇不同帖子下参与有效讨论',description:'十场讨论里，都有你的身影。',metric:'threads',goal:10,tier:'稀有'},
 {code:'popular',name:'小有名气',icon:Star,condition:'帖子与评论累计收到 30 个有效赞',description:'你的表达被更多同学看到了。',metric:'likes',goal:30,tier:'稀有'},
 {code:'collector',name:'故事收藏家',icon:BookHeart,condition:'收藏 20 篇不同的有效帖子',description:'你为二十个故事留下了书签。',metric:'saves',goal:20,tier:'稀有'}
] as const;
export const lockedIcon=LockKeyhole;
export interface HonorHall {backfilled?:string[];id:string;nickname:string;badges:Identity;honors:Badge[];showcase:string[];showcaseUsed?:number;total:number;awards:Record<string,string>;progress?:Record<string,number>}
export interface AdminMember {id:string;nickname:string;official?:Badge|null;caps:string[];honors:BadgeCode[];bannedUntil?:string;recommendation?:string}
export interface HonorLog {at:string;target:string;actor:string;change:{operation:string;reason:string}}
export const operations:Record<string,string>={bind:'绑定开发者',appoint:'任命或调整管理员',dismiss:'解除管理员',mute:'禁言七天',unmute:'解除禁言',grant:'授予荣誉',revoke:'撤销荣誉',recommend:'推荐优质创作者',decline:'驳回推荐'};
export const capNames:Record<string,string>={content:'管理内容',reports:'处理举报',users:'管理违规用户',recommend:'推荐创作者'};
export function honorDate(value?:string|null){return value?new Date(value).toLocaleDateString('zh-CN'):'暂无可核实的日期';}
