import {sql} from '../../cloudbase/functions/community/database.mjs';
// Server credentials only. Run from an external scheduler, never from a client request.
if(process.env.COMMUNITY_CONTESTS!=='enabled')throw Error('contest_scheduler_disabled');
if(!process.env.CLOUDBASE_ENV_ID||!process.env.CLOUDBASE_APIKEY)throw Error('missing_server_credentials');
const rows=await sql('SELECT public.hyt_contest_tick() AS result');
console.log(JSON.stringify(rows[0]?.result));
