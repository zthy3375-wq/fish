import type {TreeholeImage} from './treehole';
export interface DraftImage {id:string;data:string;width:number;height:number;remote?:TreeholeImage}
export interface TreeholeDraft {title:string;body:string;category:string;anonymous:boolean;requestId:string;images:DraftImage[]}
let database:Promise<IDBDatabase>|undefined;
function open(){return database??=new Promise<IDBDatabase>((resolve,reject)=>{const r=indexedDB.open('hyt-treehole-drafts-v1',1);r.onupgradeneeded=()=>r.result.createObjectStore('drafts');r.onsuccess=()=>resolve(r.result);r.onerror=()=>{database=undefined;reject(r.error);};});}
async function operation<T>(id:string,mode:IDBTransactionMode,work:(store:IDBObjectStore)=>IDBRequest){const db=await open();return new Promise<T>((resolve,reject)=>{const tx=db.transaction('drafts',mode),r=work(tx.objectStore('drafts'));tx.oncomplete=()=>resolve(r.result);tx.onerror=tx.onabort=()=>reject(tx.error);});}
export const readTreeholeDraft=(id:string)=>operation<TreeholeDraft|undefined>(id,'readonly',s=>s.get(id));
export const writeTreeholeDraft=(id:string,draft:TreeholeDraft)=>operation(id,'readwrite',s=>s.put(JSON.parse(JSON.stringify(draft)),id));
export const deleteTreeholeDraft=(id:string)=>operation(id,'readwrite',s=>s.delete(id));
export async function prepareTreeholeImage(file:File):Promise<DraftImage>{
 if(file.size>20_000_000)throw Error('image_too_large');
 let bitmap:ImageBitmap;try{bitmap=await createImageBitmap(file);}catch{throw Error('invalid_image');}
 try{
  const scale=Math.min(1,1600/Math.max(bitmap.width,bitmap.height));const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
  const ctx=canvas.getContext('2d');if(!ctx)throw Error('invalid_image');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);
  let data='';for(const quality of [.82,.7,.55,.4]){data=canvas.toDataURL('image/jpeg',quality).split(',')[1];if(data.length<=1_600_000)break;}
  if(!data||data.length>1_600_000)throw Error('image_too_large');return {id:crypto.randomUUID(),data,width:canvas.width,height:canvas.height};
 }finally{bitmap.close();}
}
