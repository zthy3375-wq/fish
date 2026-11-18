import {ref} from 'vue';
import {book,record,feedback,storageIssue} from './achievementJournal';
export const cues={
  puff:'咕噜！',dream:'呼……',goldfish:'版本号下面，藏着一串气泡。',
  timewalk:'从第一周游回来了。',freeday:'把今天留给自己吧。',
  mapfish:'水纹里探出一个脑袋。',emptyfish:'清单里游过一条小鱼。',lastline:'小金鱼在页尾签了名。'
} as const;
export type Discovery=keyof typeof cues;
export const moment=ref<Discovery|null>(null);
let animation=Promise.resolve();
const pending=new Set<Discovery>();
// Persist before playback finishes; the toast is queued only after the cue.
export async function discover(code:Discovery){
  if(pending.has(code))return;
  pending.add(code);
  try{
    if((await book('device')).stamps[code])return;
    const cue=animation.then(async()=>{
      moment.value=code;
      await new Promise<void>(resolve=>setTimeout(resolve,feedback.value.motion?940:600));
      moment.value=null;
    });
    animation=cue;
    await record(code,'device',new Date().toISOString(),false,cue);
  }catch{storageIssue.value='本机收藏暂时无法读取。';}
  finally{pending.delete(code);}
}
