/** Browser focus, visibility and the native resume event can describe one resume.
 * Share in-flight work and briefly suppress duplicate completed events. */
export function foregroundRefresh(work:()=>Promise<void>, visible:()=>boolean, now=Date.now) {
 let pending:Promise<void>|undefined, completedAt=-Infinity;
 return function refresh():Promise<void> {
  if(!visible())return Promise.resolve();
  if(pending)return pending;
  if(now()-completedAt<1000)return Promise.resolve();
  pending=Promise.resolve().then(work).finally(()=>{completedAt=now();pending=undefined;});
  return pending;
 };
}
