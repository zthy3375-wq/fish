import {createHash} from 'node:crypto';
import {createScf} from './scf.mjs';
export const SETTLEMENT_FUNCTION='hyt-contest-settlement';
export const RECOVERY_TRIGGER='hytc-daily-recovery';
export function contestTimer(contest,{now=Date.now(),offsetHours=8}={}){
 if(!contest?.id||!Number.isFinite(Date.parse(contest.awardAt)))throw Error('invalid_contest_schedule');
 const when=Math.ceil(Math.max(Date.parse(contest.awardAt),now+60000)/1000)*1000;
 const local=new Date(when+offsetHours*3600000);
 if(local.getUTCFullYear()>2099)throw Error('contest_schedule_year');
 const cron=[local.getUTCSeconds(),local.getUTCMinutes(),local.getUTCHours(),local.getUTCDate(),local.getUTCMonth()+1,'?',local.getUTCFullYear()].join(' ');
 const name='hytc-'+createHash('sha256').update(contest.id+':'+when).digest('hex').slice(0,32);
 return {name,cron,when};
}
export function createContestScheduler({env=process.env.CLOUDBASE_ENV_ID,scf=createScf({env}),now=Date.now,offsetHours=Number(process.env.CONTEST_CRON_OFFSET_HOURS??8)}={}){
 const target={Namespace:env,FunctionName:SETTLEMENT_FUNCTION};
 return {
  async ensure(contest){
   if(!contest||!contest.autoPublish||contest.cancelled||contest.state==='ended')return null;
   const timer=contestTimer(contest,{now:now(),offsetHours});
   const list=await scf('ListTriggers',{...target,Limit:100});
   if((list.Triggers||[]).some(t=>t.TriggerName===timer.name&&t.Enable!==0))return timer;
   try{await scf('CreateTrigger',{...target,TriggerName:timer.name,Type:'timer',Enable:'OPEN',TriggerDesc:JSON.stringify({cron:timer.cron}),CustomArgument:JSON.stringify({contestId:contest.id})});}
   catch(error){if(!String(error.code).startsWith('ResourceInUse'))throw error;}
   return timer;
  },
  async remove(name){if(!/^hytc-[a-f0-9]{32}$/.test(name))return;await scf('DeleteTrigger',{...target,TriggerName:name,Type:'timer'});},
 };
}
