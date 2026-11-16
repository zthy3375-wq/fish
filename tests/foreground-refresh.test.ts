// @vitest-environment jsdom
import {it,expect,vi} from 'vitest';
import {foregroundRefresh} from '../src/services/foreground-refresh';
import {keyboardViewport} from '../src/services/keyboard-viewport';
it('resume event burst shares work; hidden events do not request; a later resume refreshes',async()=>{
 let visible=false,time=0,finish!:()=>void;
 const work=vi.fn(()=>new Promise<void>(r=>{finish=r}));
 const refresh=foregroundRefresh(work,()=>visible,()=>time);
 await refresh();expect(work).not.toHaveBeenCalled();visible=true;
 const first=refresh();expect(refresh()).toBe(first);await Promise.resolve();expect(work).toHaveBeenCalledTimes(1);finish();await first;
 await refresh();expect(work).toHaveBeenCalledTimes(1);time=1001;const next=refresh();await Promise.resolve();expect(work).toHaveBeenCalledTimes(2);finish();await next;
});
it('failed refresh unlocks subsequent resumes without creating an unhandled child promise',async()=>{
 let time=0;const work=vi.fn().mockRejectedValueOnce(Error('offline')).mockResolvedValueOnce(undefined);
 const refresh=foregroundRefresh(work,()=>true,()=>time);await expect(refresh()).rejects.toThrow('offline');time=1001;await refresh();expect(work).toHaveBeenCalledTimes(2);
});
it('keyboard detection requires editable focus, ignores zoom and clears when editing ends',()=>{
 const input=document.createElement('input'),view={height:420,scale:1};
 expect(keyboardViewport(844,view,input)).toBe(true);
 expect(keyboardViewport(844,{...view,scale:2},input)).toBe(false);
 expect(keyboardViewport(844,view,document.createElement('button'))).toBe(false);
 expect(keyboardViewport(844,{height:800,scale:1},input)).toBe(false);
 expect(keyboardViewport(844,null,input)).toBe(false);
});
