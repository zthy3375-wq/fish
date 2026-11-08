import type {Course} from '../domain/academic';
export const coursePalette=['#b9e6fa','#d3ccff','#ffe3a0','#ffcbd5','#b8eee0','#ffdab6','#d8e9b2','#e8c9f0','#bed6ff','#f0dbb5','#c9e3d7','#f3c5e3'];
const key='handan.course.colors.v1';
let assignments:Record<string,number>=Object.create(null);
try {const saved=JSON.parse(localStorage.getItem(key)||'{}');for(const [k,v] of Object.entries(saved))if(Number.isInteger(v)&&Number(v)>=0&&Number(v)<coursePalette.length)assignments[k]=Number(v)} catch {}
export function courseTint(course:Course){
 const id=course.courseId||course.name.trim();
 if(assignments[id]===undefined){const used=new Set(Object.values(assignments));const available=coursePalette.findIndex((_,i)=>!used.has(i));let hash=0;for(const c of id)hash=(Math.imul(hash,31)+c.charCodeAt(0))|0;assignments[id]=available<0?(hash>>>0)%coursePalette.length:available;try{localStorage.setItem(key,JSON.stringify(assignments))}catch{}}
 return {background:coursePalette[assignments[id]],color:'#243348'};
}
