import {sql} from './database.mjs';
import {createContestScheduler,RECOVERY_TRIGGER} from './contest-scheduler.mjs';
export function createContestWorker({query=sql,scheduler=createContestScheduler()}={}){
 return async event=>{
  if(event?.Type!=='Timer'||(!/^hytc-[a-f0-9]{32}$/.test(event.TriggerName||'')&&event.TriggerName!==RECOVERY_TRIGGER))throw Error('invalid_contest_timer');
  const rows=await query('SELECT public.hyt_contest_tick() AS result');
  if(event.TriggerName===RECOVERY_TRIGGER){
   const future=await query("SELECT id,award_at AS \"awardAt\",auto_publish AS \"autoPublish\" FROM public.hyt_contests WHERE published AND auto_publish AND NOT cancelled AND NOT paused AND announced_at IS NULL AND award_at>now() ORDER BY award_at LIMIT 100");
   for(const contest of future)await scheduler.ensure(contest);
  }else{
   // A completed one-off timer does not retain an enabled trigger indefinitely.
   try{await scheduler.remove(event.TriggerName)}catch{console.warn('Contest trigger cleanup will be retried by deployment maintenance')}
  }
  return rows[0]?.result||{processed:0};
 };
}
