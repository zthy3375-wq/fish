import {test} from 'node:test';
import assert from 'node:assert/strict';
import {contestTimer,createContestScheduler,RECOVERY_TRIGGER} from '../functions/community/contest-scheduler.mjs';
import {createContestWorker} from '../functions/community/contest-worker.mjs';
const contest={id:'timer-fixture',awardAt:'2026-11-23T01:02:03Z',autoPublish:true};
test('one-off Shanghai cron uses server time and stable event/deadline identity',()=>{
 const t=contestTimer(contest,{now:0});assert.equal(t.cron,'3 2 9 23 11 ? 2026');
 assert.equal(t.name,contestTimer(contest,{now:0}).name);
 assert.notEqual(t.name,contestTimer({...contest,awardAt:'2026-11-24T01:02:03Z'},{now:0}).name);
 assert.equal(contestTimer({...contest,awardAt:'2020-01-01Z'},{now:Date.parse(contest.awardAt)}).when,Date.parse(contest.awardAt)+60000);
});
test('scheduler skips manual events, coalesces existing timer and propagates provider errors',async()=>{
 const calls=[];const scf=async(a,b)=>{calls.push([a,b]);return {Triggers:[]}};
 const s=createContestScheduler({env:'test',scf,now:()=>0});
 await s.ensure({...contest,autoPublish:false});assert.equal(calls.length,0);
 const t=await s.ensure(contest);assert.equal(calls[1][0],'CreateTrigger');assert.equal(calls[1][1].TriggerDesc,'3 2 9 23 11 ? 2026');
 await s.remove(RECOVERY_TRIGGER);assert.equal(calls.length,2);
 await s.remove(t.name);assert.equal(calls[2][0],'DeleteTrigger');
 const existing=createContestScheduler({env:'test',now:()=>0,scf:async a=>{assert.equal(a,'ListTriggers');return {Triggers:[{TriggerName:t.name,Enable:1}]}}});await existing.ensure(contest);
 await assert.rejects(createContestScheduler({env:'test',now:()=>0,scf:async()=>{throw Error('denied')}}).ensure(contest),/denied/);
});
test('worker validates timer source, settles once, removes only its own one-off; daily repair schedules future events',async()=>{
 const q=[],scheduled=[],removed=[];const worker=createContestWorker({query:async sql=>{q.push(sql);return sql.includes('tick()')?[{result:{processed:1}}]:[contest]},scheduler:{ensure:async c=>scheduled.push(c),remove:async n=>removed.push(n)}});
 await assert.rejects(worker({Type:'http',TriggerName:RECOVERY_TRIGGER}));assert.equal(q.length,0);
 const name=contestTimer(contest,{now:0}).name;assert.deepEqual(await worker({Type:'Timer',TriggerName:name}),{processed:1});assert.deepEqual(removed,[name]);
 await worker({Type:'Timer',TriggerName:RECOVERY_TRIGGER});assert.equal(scheduled.length,1);assert.equal(removed.length,1);
});
