import {spawnSync} from 'node:child_process';
import {chmodSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import {credentials} from '../../cloudbase/functions/analytics/database.mjs';

const envId = 'hanyuantong-d8gjzt1jh12370215';
const region = 'ap-shanghai';
const origin = 'https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com';
if (process.env.CLOUDBASE_ENV_ID !== envId) throw Error('Unexpected CloudBase environment');
process.env.CLOUDBASE_APIKEY = process.env.CLOUDBASE_API_KEY;
const credential = await credentials();
const cliEnv = {...process.env, TENCENTCLOUD_SECRETID:credential.TmpSecretId,
  TENCENTCLOUD_SECRETKEY:credential.TmpSecretKey, TENCENTCLOUD_SESSIONTOKEN:credential.Token};
delete cliEnv.CLOUDBASE_API_KEY;
delete cliEnv.CLOUDBASE_APIKEY;

function run(binary, args) {
  const p = spawnSync(binary, args, {env:cliEnv, encoding:'utf8', timeout:300000, maxBuffer:4*1024*1024});
  // Raw CLI diagnostics can include function environment variables.
  if (p.status !== 0) {
    const code = ((p.stdout || '')+(p.stderr || '')).match(/(?:UnauthorizedOperation|AuthFailure|InvalidParameter|ResourceNotFound|FailedOperation|Unauthorized)[.\w]*/i);
    throw Error(binary+' '+args.slice(0,3).join(' ')+' failed ('+(code?.[0] || p.status || p.error?.code || 'unknown')+')');
  }
  if (binary === 'python3') console.log(p.stdout.trim());
}
async function check(base, path, method) {
  const res = await fetch(base+path, {method, signal:AbortSignal.timeout(12000)});
  if (!res.ok) return false;
  const result = await res.json();
  return result.ok === true && result.collection === false &&
    (path !== '/internal/flush' || result.processed === 0);
}
run('npm', ['ci','--prefix','cloudbase/functions/analytics','--omit=dev','--ignore-scripts','--no-audit','--no-fund']);
chmodSync('cloudbase/functions/analytics/scf_bootstrap', 0o755);
for (const name of ['hyt-analytics-canary','hyt-analytics']) {
  const base = origin+'/'+name;
  if (!await check(base, '/health', 'GET').catch(()=>false)) {
    run('tcb', ['fn','code','update',name,'--dir','cloudbase/functions/analytics','--yes','--json','-e',envId,'-r',region]);
  }
  let ready = false;
  for (let attempt=0; attempt<20; attempt++) {
    if (await check(base, '/health','GET').catch(()=>false)) { ready=true; break; }
    await delay(3000);
  }
  if (!ready) throw Error(name+' retirement health check failed');
  for (const path of ['/api/metrics/enroll','/api/metrics/record','/internal/flush']) {
    if (!await check(base, path,'POST')) throw Error(name+' retirement check failed at '+path);
  }
  console.log(name+' verified: collection=false on enroll and record, flush processed=0');
}
run('python3', ['scripts/cloudbase/retire-analytics-timer.py']);
