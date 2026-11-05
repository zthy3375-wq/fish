export interface Preferences { name:string; major:string; theme:'light'|'dark'|'system'; notifications:boolean; compact:boolean }
export const defaults:Preferences={name:'同学',major:'智能制造工程 · 2026级（模拟）',theme:'light',notifications:true,compact:false};
const key='handan-campus.preferences.v1';
export function loadPreferences():Preferences {try{ const raw=JSON.parse(localStorage.getItem(key)||'{}');return {name:typeof raw.name==='string'?raw.name.slice(0,20):defaults.name,major:typeof raw.major==='string'?raw.major.slice(0,50):defaults.major,theme:['light','dark','system'].includes(raw.theme)?raw.theme:'light',notifications:typeof raw.notifications==='boolean'?raw.notifications:true,compact:typeof raw.compact==='boolean'?raw.compact:false};}catch{return {...defaults}}}
export function savePreferences(p:Preferences):boolean {try{localStorage.setItem(key,JSON.stringify(p));return true}catch{return false}}
export function clearPreferences(){try{localStorage.removeItem(key);return true}catch{return false}}
