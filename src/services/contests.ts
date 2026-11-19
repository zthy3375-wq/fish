import {treeholeRequest,type TreeholeImage} from './treehole';
export interface Contest {
 id:string;title:string;type:string;edition:string;description:string;rules:string;state:string;paused:boolean;
 startsAt:string;submissionEnds:string;votingStarts:string;votingEnds:string;awardAt:string;
 formats:string[];maxEntries:number;votesPerUser:number;minEntries:number;minAccountHours:number;excellence:number;autoPublish:boolean;version:number;
 entryCount:number;participantCount:number;coverPostId:string|null;cover?:TreeholeImage|null;
}
export interface ContestAward {id:string;kind:string;rank:number|null;at?:string;awarded_at?:string;title?:string;edition?:string;contest_id?:string;entry_id?:string}
export interface ContestEntry {id:string;contestId:string;memberId:string;title:string;body:string;postId:string|null;status:string;author:string;mine:boolean;createdAt:string;voted:boolean;votes:number|null;images:TreeholeImage[];awards:ContestAward[];version:number}
export interface ContestTheme {id:string;title:string;status:string;votes:number;voted:boolean;merged_into?:string|null}
export interface ContestAudit {id:string;action:string;reason:string;target_id:string|null;created_at:string}
export interface ContestVote {id:string;entry_id:string;member_id:string;enabled:boolean;excluded:boolean;risk:string|null}
export interface ContestResult {
 contests?:Contest[];contest?:Contest;entries?:ContestEntry[];entry?:ContestEntry;serverTime?:string;votesUsed?:number;
 stats?:{participations:number;champions:number;podiums:number};awards?:ContestAward[];worn?:string|null;annual?:number[];
 themes?:ContestTheme[];solicitation?:boolean;leaders?:{id:string;nickname:string;score:number}[];
 votes?:ContestVote[];audit?:ContestAudit[];reports?:{id:string;entry_id:string;reason:string}[];metrics?:Record<string,number>;
}
export const contestLabels:Record<string,string>={draft:'草稿',upcoming:'未开始',submitting:'投稿中',waiting:'等待投票',voting:'投票中',reviewing:'结果审核中',ended:'已结束',cancelled:'已取消'};
export const awardLabels:Record<string,string>={champion:'冠军',silver:'亚军',bronze:'季军',excellent:'优秀作品',participation:'参赛纪念'};
export function contestStage(c:Contest,now=Date.now()):string {
 if(['cancelled','ended','draft'].includes(c.state))return c.state;
 if(now<Date.parse(c.startsAt))return 'upcoming';
 if(now<Date.parse(c.submissionEnds))return 'submitting';
 if(now<Date.parse(c.votingStarts))return 'waiting';
 return now<Date.parse(c.votingEnds)?'voting':'reviewing';
}
export function contestRemaining(c:Contest,now=Date.now()):string {
 const phase=contestStage(c,now),end={upcoming:c.startsAt,submitting:c.submissionEnds,waiting:c.votingStarts,voting:c.votingEnds,reviewing:c.awardAt}[phase];
 if(!end)return '';const minutes=Math.ceil((Date.parse(end)-now)/60000);
 if(minutes<=0)return '等待公布';return minutes>=1440?`${Math.floor(minutes/1440)}天 ${Math.floor(minutes%1440/60)}小时`:`${Math.floor(minutes/60)}小时 ${minutes%60}分`;
}
const cache=new Map<string,{until:number;result:ContestResult}>();
export async function contestRequest(owner:string,action:string,body:Record<string,unknown>={},fresh=false):Promise<ContestResult> {
 const key=owner+action+JSON.stringify(body),read=['contests.list','contests.profile'].includes(action),saved=cache.get(key);
 if(read&&!fresh&&saved&&saved.until>Date.now())return saved.result;
 const result=await treeholeRequest(action,body) as ContestResult;
 if(read){if(cache.size>30)cache.clear();cache.set(key,{until:Date.now()+120000,result});}
 else if(!['contests.get','contests.entries','contests.themes','contests.year','contests.admin'].includes(action))for(const key of cache.keys())if(key.startsWith(owner))cache.delete(key);
 return result;
}
