import type {TreeholeBuddyDraft} from '../services/treehole';
// Campus events always use Beijing time, independent of device timezone.
export function buddyLocalTime(iso:string){const time=Date.parse(iso);return Number.isFinite(time)?new Date(time+8*3600_000).toISOString().slice(0,16):'';}
export function buddyISOTime(local:string){if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local))return '';const time=Date.parse(local+':00+08:00');if(!Number.isFinite(time))return '';const iso=new Date(time).toISOString();return buddyLocalTime(iso)===local?iso:'';}
export function newBuddyDraft():TreeholeBuddyDraft{return {location:'',startsAt:new Date(Math.ceil((Date.now()+3600_000)/60_000)*60_000).toISOString(),capacity:1};}
export function buddyDraftValid(value:TreeholeBuddyDraft,now=Date.now()){const time=Date.parse(value.startsAt);return !!value.location.trim()&&value.location.trim().length<=60&&Number.isInteger(value.capacity)&&value.capacity>=1&&value.capacity<=20&&time>now&&time<=now+90*86400_000;}
export function buddyTimeLabel(iso:string){return buddyLocalTime(iso).replace('T',' ')+' · 北京时间';}
