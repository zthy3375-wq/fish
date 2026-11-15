import {describe,it,expect} from 'vitest';
import 'fake-indexeddb/auto';
import {writeTreeholeDraft,readTreeholeDraft,deleteTreeholeDraft,type TreeholeDraft} from './treeholeDrafts';
describe('community drafts',()=>{
 it('isolates accounts, snapshots image retries and clears only the published draft',async()=>{
  const draft:TreeholeDraft={title:'午后',body:'草稿',category:'study',anonymous:true,requestId:'request-a',images:[{id:'upload-a',data:'jpeg-bytes',width:4,height:3,remote:{id:'ready-a',url:null,width:4,height:3}}]};
  await writeTreeholeDraft('account-a',draft);draft.body='later edit';
  await writeTreeholeDraft('account-b',{...draft,title:'另一位同学',images:[]});
  const resumed=await readTreeholeDraft('account-a');expect(resumed?.body).toBe('草稿');expect(resumed?.images[0].remote?.id).toBe('ready-a');expect(resumed?.requestId).toBe('request-a');
  await deleteTreeholeDraft('account-a');expect(await readTreeholeDraft('account-a')).toBeUndefined();expect((await readTreeholeDraft('account-b'))?.title).toBe('另一位同学');
 });
});
