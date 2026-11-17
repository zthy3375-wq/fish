// @vitest-environment jsdom
import {createApp,nextTick} from 'vue';
import {it,expect,vi} from 'vitest';
import Admin from '../src/components/TreeholeAdmin.vue';

it('previews the reported comment and requires a second submit before applying a decision',async()=>{
 const request=vi.fn(async(action:string)=>action==='admin.context'?{post:{id:'p',author:{name:'作者'},body:'原帖',createdAt:'2026-11-01'},comment:{id:'c',author:{name:'同学'},body:'目标评论'}}:{});
 const root=document.createElement('div');document.body.append(root);
 const app=createApp(Admin,{request:request as never,initialTarget:{postId:'p',commentId:'c'}});
 vi.spyOn(window,'scrollTo').mockImplementation(()=>{});
 try{
  app.mount(root);await vi.waitFor(()=>expect(root.querySelector('input[value="remove"]')).toBeTruthy());
  expect(root.querySelector('input[value="unlock"]')).toBeNull();
  root.querySelector<HTMLInputElement>('input[value="remove"]')!.click();
  const reason=root.querySelector('textarea')!;reason.value='处理测试';reason.dispatchEvent(new Event('input'));await nextTick();
  const form=root.querySelector('form')!;form.dispatchEvent(new Event('submit',{cancelable:true}));await nextTick();
  expect(root.querySelector('.admin-confirm blockquote')?.textContent).toBe('目标评论');
  expect(request.mock.calls.map(x=>x[0])).not.toContain('admin.action');
  form.dispatchEvent(new Event('submit',{cancelable:true}));await vi.waitFor(()=>expect(request.mock.calls.map(x=>x[0])).toContain('admin.action'));
 }finally{app.unmount();root.remove();vi.restoreAllMocks()}
});
