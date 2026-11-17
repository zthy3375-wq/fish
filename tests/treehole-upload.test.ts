import {describe,it,expect,vi} from 'vitest';
import {uploadTreeholeImages,type TreeholeUploadProgress} from '../src/services/treeholeUpload';
import type {DraftImage} from '../src/services/treeholeDrafts';

const photo=(id:string):DraftImage=>({id,data:'synthetic-base64',width:10,height:10});
const remote=(id:string)=>({id,url:null,width:10,height:10});
describe('confirmed community image upload progress',()=>{
 it('retains a confirmed image and retries only the failed image with its original request ID',async()=>{
  const images=[photo('one'),photo('two')],states:TreeholeUploadProgress[]=[];
  const request=vi.fn().mockResolvedValueOnce({image:remote('remote-one')}).mockRejectedValueOnce(Error('network_unavailable')).mockResolvedValueOnce({image:remote('remote-two')});
  await expect(uploadTreeholeImages(images,'post',request,p=>states.push(p),()=>true)).rejects.toThrow('network_unavailable');
  expect(images[0].remote?.id).toBe('remote-one');expect(images[1].id).toBe('two');
  expect(states.at(-1)).toEqual({phase:'failed',completed:1,total:2,currentId:'two'});
  await expect(uploadTreeholeImages(images,'post',request,p=>states.push(p),()=>true)).resolves.toBe(true);
  expect(request.mock.calls.map(c=>c[1].requestId)).toEqual(['one','two','two']);
  expect(states.at(-1)).toEqual({phase:'publishing',completed:2,total:2,currentId:undefined});
 });
 it('keeps a text-only publish out of the upload stage',async()=>{
  const request=vi.fn(),progress=vi.fn();await uploadTreeholeImages([],'post',request,progress,()=>true);
  expect(request).not.toHaveBeenCalled();expect(progress).toHaveBeenCalledExactlyOnceWith({phase:'publishing',completed:0,total:0,currentId:undefined});
 });
 it('does not attach a late upload receipt or publish status after the active account changes',async()=>{
  const images=[photo('old-account')],progress=vi.fn();let active=true,resolve!:(value:object)=>void;
  const pending=uploadTreeholeImages(images,'post',()=>new Promise(r=>resolve=r),progress,()=>active);
  active=false;resolve({image:remote('private-receipt')});expect(await pending).toBe(false);
  expect(images[0].remote).toBeUndefined();expect(progress).toHaveBeenCalledTimes(1);
 });
 it('treats a missing server receipt as a failure and preserves local photo data',async()=>{
  const images=[photo('unconfirmed')],progress=vi.fn();
  await expect(uploadTreeholeImages(images,'post',async()=>({}),progress,()=>true)).rejects.toThrow('image_unavailable');
  expect(images[0]).toEqual(photo('unconfirmed'));expect(progress.mock.calls.at(-1)?.[0].completed).toBe(0);
 });
 it('keeps the existing comment upload purpose and calls persistence only for newly confirmed images',async()=>{
  const images=[{...photo('known'),remote:remote('already-uploaded')},photo('new')],request=vi.fn().mockResolvedValue({image:remote('new-receipt')}),persist=vi.fn();
  await uploadTreeholeImages(images,'comment',request,()=>{},()=>true,persist);
  expect(request).toHaveBeenCalledExactlyOnceWith('media.upload',{data:'synthetic-base64',requestId:'new',purpose:'comment'});
  expect(persist).toHaveBeenCalledTimes(1);
 });
});
