// Operator-only. The interactive operator supplies an independently confirmed stable
// ID; the original audited owner binding must identify exactly that same account.
import {pathToFileURL} from 'node:url';
import {sql} from '../../cloudbase/functions/community/database.mjs';
export function developerBinding(id) {
 if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(id))throw Error('invalid_member_id');
 return `DO $bind$
 DECLARE remembered uuid; target public.hyt_members%rowtype;
 BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('hyt-one-developer'));
  SELECT moderator_id INTO STRICT remembered FROM public.hyt_moderation WHERE action='grant_moderator'
   AND reason='Initial moderator binding explicitly authorized by repository owner, 2026-11-16';
  IF remembered<>'${id}'::uuid THEN RAISE EXCEPTION 'owner_evidence_mismatch'; END IF;
  SELECT * INTO STRICT target FROM public.hyt_members WHERE id=remembered AND deleted_at IS NULL AND role='moderator' FOR UPDATE;
  IF target.banned_until>now() THEN RAISE EXCEPTION 'inactive_owner'; END IF;
  IF target.developer_since IS NOT NULL THEN RETURN; END IF;
  UPDATE public.hyt_members SET developer_since=now() WHERE id=remembered;
  INSERT INTO public.hyt_honor_history(id,actor,target,change) VALUES(gen_random_uuid(),remembered,remembered,'{"operation":"bind","reason":"Verified original owner binding"}');
 END $bind$;`;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 await sql(developerBinding(process.env.CONFIRMED_OWNER_UUID??''));
 console.log('Verified owner binding completed');
}
