import {sql} from '../../cloudbase/functions/community/database.mjs';
import {moderatorBindingSQL} from './community-moderator-binding.mjs';

const expectedRef='refs/heads/ops/community-owner-bind-20261116';
if(process.env.GITHUB_REF!==expectedRef||process.env.GITHUB_REPOSITORY!=='zthy3375-wq/fish')throw Error('unexpected_binding_context');
const key=process.env.CLOUDBASE_API_KEY?.trim(),digest=process.env.COMMUNITY_TARGET_SHA256;
if(!key||!/^[a-f0-9]{64}$/.test(digest||''))throw Error('binding_configuration_unavailable');
process.env.CLOUDBASE_ENV_ID='hanyuantong-d8gjzt1jh12370215';process.env.CLOUDBASE_APIKEY=key;
const lookup=`SELECT id::text AS id,role,deleted_at IS NULL AND (banned_until IS NULL OR banned_until<=now()) AS active
 FROM public.hyt_members WHERE encode(sha256(convert_to(username,'UTF8')),'hex')=$1`;
const matches=await sql(lookup,[digest]);
if(matches.length!==1||matches[0].active!==true)throw Error('binding_requires_one_active_matching_account');
console.log('Verified exactly one active account matching the owner-provided login; current role: '+matches[0].role);
await sql(moderatorBindingSQL(digest,matches[0].id));
const result=await sql(`SELECT m.role,public.hyt_member_json(m)->>'role' AS projected_role,
 EXISTS(SELECT 1 FROM public.hyt_moderation a WHERE a.moderator_id=m.id AND a.action='grant_moderator') AS audited
 FROM public.hyt_members m WHERE m.id=$1::uuid AND encode(sha256(convert_to(m.username,'UTF8')),'hex')=$2`,[matches[0].id,digest]);
if(result.length!==1||result[0].role!=='moderator'||result[0].projected_role!=='moderator'||(matches[0].role==='member'&&!result[0].audited))throw Error('binding_post_verification_failed');
console.log(JSON.stringify({accountMatched:true,role:'moderator',clientProjectionVerified:true,audited:result[0].audited,previousRole:matches[0].role,clientRebuildRequired:false}));
