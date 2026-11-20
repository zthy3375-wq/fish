import { readFileSync } from 'node:fs';
import { createSqlClient } from '../../cloudbase/functions/community/database.mjs';
import { communityRpcDigest, honorsMigration } from './community-honors-migration.mjs';

const env = 'hanyuantong-d8gjzt1jh12370215';
const key = process.env.CLOUDBASE_API_KEY?.trim();
const expectedBranch = 'deploy/community-honors-members-20261120';
const endpoint = 'https://' + env + '-1527874185.ap-shanghai.app.tcloudbase.com/hyt-community';
if (!key || process.env.GITHUB_EVENT_NAME !== 'pull_request' || process.env.GITHUB_HEAD_REF !== expectedBranch) {
  throw Error('Unexpected production deployment context');
}

async function config(requireHonors) {
  for (let attempt = 0; attempt < 8; attempt++) {
    try {
      const response = await fetch(endpoint + '/v1/config', { signal:AbortSignal.timeout(8000) });
      const live = await response.json();
      if (response.ok && live.schema === 15 && live.contestsEnabled && live.registrationEnabled &&
          live.honorsEnabled && live.imagesEnabled && live.messagesEnabled &&
          (!requireHonors || (live.honorCollectionEnabled && live.registeredMembersEnabled))) return;
    } catch { /* Wait for the existing HTTPS gateway or new code to become active. */ }
    await new Promise(resolve => setTimeout(resolve,2500));
  }
  throw Error(requireHonors ? 'New community capabilities did not activate' : 'Expected existing community service is not healthy');
}

if (process.argv[2] === 'verify') {
  await config(true);
  for (const action of ['admin.members', 'collection.profile', 'collection.archive', 'contests.list']) {
    const response = await fetch(endpoint + '/v1/' + action, {
      method:'POST', headers:{'Content-Type':'application/json',Accept:'application/json'},
      body:'{}', signal:AbortSignal.timeout(15000),
    });
    const body = await response.json();
    if (response.status !== 401 || body.error !== 'session_expired') throw Error('Unexpected anonymous result for ' + action);
  }
  console.log('Live capabilities active; anonymous member, honor and contest calls rejected');
} else if (process.argv[2] === 'migrate') {
  await config(false);
  const baseline = readFileSync('/tmp/hyt-honors-live-before.sql','utf8');
  const current = readFileSync('cloudbase/community-schema.sql','utf8');
  const identity = await fetch('https://' + env + '.api.tcloudbasegateway.com/v1/rdb/exec-pgsql', {
    method:'POST', headers:{Authorization:'Bearer ' + key,'Content-Type':'application/json'},
    body:JSON.stringify({sql:'SELECT current_user AS role',parameters:[]}), signal:AbortSignal.timeout(20000),
  });
  const httpRole = (await identity.json())?.[0]?.role;
  if (!identity.ok || !httpRole) throw Error('Unable to verify the HTTP database role');
  const db = createSqlClient({
    settings:()=>({env,key}),
    fetcher:async (url, opts) => {
      if (opts.headers?.['X-TC-Action'] !== 'ExecutePGSql') return fetch(url,opts);
      const response = await fetch(url,{...opts,signal:AbortSignal.timeout(110000)});
      const failure = (await response.clone().json().catch(()=>null))?.Response?.Error;
      if (failure) {
        const message = String(failure.Message ?? '');
        const categories = [
          ['rpc_revision','Unexpected live community RPC'], ['permission_boundary','access remains'],
          ['row_preservation','Existing community rows changed'], ['smoke','smoke failed'],
          ['role_boundary','administrator boundary failed'], ['missing_live_identity','query returned no rows'],
          ['lock','lock timeout'], ['missing_object','does not exist'],
        ];
        const reason = categories.find(([, fragment])=>message.includes(fragment))?.[0] ?? 'unclassified';
        console.error('Community migration error category:',reason);
      }
      return response;
    },
  });
  const digest = "SELECT md5(prosrc) AS digest FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure";
  const old = communityRpcDigest(baseline);
  const next = communityRpcDigest(current);
  const [before] = await db(digest);
  if (!before || ![old,next].includes(before.digest)) throw Error('The production database RPC differs from the reviewed baseline');
  await db(honorsMigration({base:baseline,current,httpRole}));
  const [after] = await db(digest);
  if (after?.digest !== next) throw Error('Production RPC revision did not activate');
  console.log('Live migration passed original row preservation and scoped permission checks; smoke sessions rolled back');
} else {
  throw Error('Unknown community deployment step');
}
