import {byCode} from '../domain/globalAchievements';
import type {TreeholeResult} from './treehole';

const presented=new Map<string,Set<string>>();
export function pendingAwards(result:TreeholeResult,owner:string) {
  if(!owner||owner!==result.awardOwner)return [];
  let seen=presented.get(owner);
  if(!seen){
    try{const value=JSON.parse(localStorage.getItem('hyt-presented:'+owner)||'[]');seen=new Set(Array.isArray(value)?value:[]);}catch{seen=new Set();}
    presented.set(owner,seen);
  }
  return (result.unlocks||[]).filter(code=>byCode.get(code)?.source==='community'&&!seen!.has(code));
}
export function markPresented(owner:string,code:string){
  if(!owner||byCode.get(code)?.source!=='community')return;
  const seen=presented.get(owner)??new Set<string>();
  seen.add(code);presented.set(owner,seen);
  try{localStorage.setItem('hyt-presented:'+owner,JSON.stringify([...seen]));}catch{}
}
