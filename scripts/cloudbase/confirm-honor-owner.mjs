import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {sql} from '../../cloudbase/functions/community/database.mjs';
import {developerBinding} from './bind-developer.mjs';
assert.equal(process.env.GITHUB_REF,'refs/heads/ops/confirm-community-owner-20261118');
assert.equal(process.env.GITHUB_REPOSITORY,'zthy3375-wq/fish');
process.env.CLOUDBASE_APIKEY=process.env.CLOUDBASE_API_KEY;
const authorizedWorkflow=execFileSync('git',['show','02cd214ea3821d80e5260b8b1bdb0713d450a168:.github/workflows/community-owner-bind.yml'],{encoding:'utf8'});
const pinned=authorizedWorkflow.match(/COMMUNITY_TARGET_SHA256:\s*['"]?([a-f0-9]{64})/);
assert(pinned,'original audited account pin');
const lookup=await sql(`SELECT jsonb_build_object('id',id,'active',deleted_at IS NULL AND (banned_until IS NULL OR banned_until<=now()),'role',role) AS result
 FROM public.hyt_members WHERE encode(sha256(convert_to(username,'UTF8')),'hex')=$1`,[pinned[1]]);
assert.equal(lookup.length,1);const account=lookup[0].result;assert.equal(account.active,true);assert.equal(account.role,'moderator');
await sql(developerBinding(account.id));
const v=await sql(`SELECT jsonb_build_object(
 'one',(SELECT count(*)=1 FROM public.hyt_members WHERE developer_since IS NOT NULL),
 'projected',(public.hyt_member_json(m)->'badges'->'official'->>'code')='developer',
 'public',(public.hyt_profile_json(m,m.id)->'badges'->'official'->>'code')='developer',
 'named',(public.hyt_author_json(m.id,gen_random_uuid(),false,m.id)->'badges'->'official'->>'code')='developer',
 'anon',NOT(public.hyt_author_json(m.id,gen_random_uuid(),true,m.id)?'badges'),
 'audited',(SELECT count(*)=1 FROM public.hyt_honor_history WHERE actor=m.id AND target=m.id AND change->>'operation'='bind')
 ) AS result FROM public.hyt_members m WHERE m.id=$1::uuid AND encode(sha256(convert_to(m.username,'UTF8')),'hex')=$2`,[account.id,pinned[1]]);
assert.equal(v.length,1);assert.deepEqual(v[0].result,{one:true,projected:true,public:true,named:true,anon:true,audited:true});
console.log('PASS: exact originally authorized account and stable ID matched, one developer, private/public/named badge projections, anonymous privacy and exactly one audit event. No other account changed.');
