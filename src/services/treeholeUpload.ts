import type {DraftImage} from './treeholeDrafts';
import type {TreeholeResult} from './treehole';

export interface TreeholeUploadProgress {
  phase:'uploading'|'publishing'|'failed';
  completed:number;
  total:number;
  currentId?:string;
}

/** Count confirmed uploads only. Retain remote IDs and request IDs across retries. */
export async function uploadTreeholeImages(
  images:DraftImage[], purpose:'post'|'comment',
  request:(action:string,payload:Record<string,unknown>)=>Promise<TreeholeResult>,
  progress:(value:TreeholeUploadProgress)=>void,
  current:()=>boolean,
  uploaded?:()=>void,
):Promise<boolean> {
  let currentId:string|undefined;
  const completed=()=>images.filter(image=>image.remote).length;
  const report=(phase:TreeholeUploadProgress['phase'])=>{
    if(current())progress({phase,completed:completed(),total:images.length,currentId});
  };
  try {
    for(const image of images){
      if(!current())return false;
      if(image.remote)continue;
      currentId=image.id;report('uploading');
      const result=await request('media.upload',{data:image.data,requestId:image.id,...(purpose==='comment'?{purpose}:{})});
      if(!current())return false;
      if(!result.image?.id)throw Error('image_unavailable');
      image.remote=result.image;uploaded?.();report('uploading');
    }
    if(!current())return false;
    currentId=undefined;report('publishing');return true;
  }catch(error){
    if(!current())return false;
    report('failed');throw error;
  }
}
