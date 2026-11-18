import {byCode,type Collectible} from './globalAchievements';
import type {Badge,Identity} from './communityHonors';

export interface ShowcaseOwner {id:string;badges?:Identity;showcase?:string[]}
export function publicMedals(codes:string[]=[]):Collectible[]{
  return [...new Set(codes)].map(code=>byCode.get(code)).filter((a):a is Collectible=>a?.source==='community').slice(0,3);
}
export function featuredHonor(identity?:Identity):Badge|undefined{
  const worn=identity?.worn,official=identity?.official;
  if(worn&&['seed','creator','contributor'].includes(worn.code))return worn;
  if(official&&['developer','moderator'].includes(official.code))return official;
}
export function personalDisplay(stamps:Record<string,string>,pins:string[],accountPins:string[]){
  const sorted=Object.keys(stamps).filter(code=>byCode.has(code)&&Number.isFinite(Date.parse(stamps[code])))
    .sort((a,b)=>Date.parse(stamps[b])-Date.parse(stamps[a])||a.localeCompare(b));
  const pinned=[...new Set([...pins,...accountPins])].filter(code=>sorted.includes(code)).slice(0,3);
  const choices=pinned.length?pinned:sorted.slice(0,3);
  return {medals:choices.map(code=>byCode.get(code)!),latest:byCode.get(sorted[0]),pinned:pinned.length>0};
}
