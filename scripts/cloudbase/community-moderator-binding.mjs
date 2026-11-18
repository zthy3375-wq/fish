// Server-side owner-authorized bootstrap, never exposed as a client action.
export function moderatorBindingSQL(usernameDigest,memberId){
 if(!/^[a-f0-9]{64}$/.test(usernameDigest)||!/^[a-f0-9-]{36}$/.test(memberId))throw Error('invalid_binding_target');
 return `DO $bind_owner$
 DECLARE target public.hyt_members%ROWTYPE; original jsonb; updated jsonb; affected integer;
 BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('hyt-owner-moderator-bootstrap'));
  SELECT * INTO STRICT target FROM public.hyt_members
   WHERE id='${memberId}'::uuid AND encode(sha256(convert_to(username,'UTF8')),'hex')='${usernameDigest}' FOR UPDATE;
  IF target.deleted_at IS NOT NULL OR target.banned_until>now() THEN RAISE EXCEPTION 'binding_target_inactive'; END IF;
  IF target.role='moderator' THEN RETURN; END IF;
  IF target.role<>'member' THEN RAISE EXCEPTION 'unexpected_binding_role'; END IF;
  original=to_jsonb(target)-'role';
  UPDATE public.hyt_members SET role='moderator' WHERE id=target.id AND role='member';
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>1 THEN RAISE EXCEPTION 'binding_update_count'; END IF;
  SELECT to_jsonb(m)-'role' INTO updated FROM public.hyt_members m WHERE m.id=target.id;
  IF updated IS DISTINCT FROM original THEN RAISE EXCEPTION 'binding_changed_other_fields'; END IF;
  INSERT INTO public.hyt_moderation(moderator_id,action,reason)
   VALUES(target.id,'grant_moderator','Initial moderator binding explicitly authorized by repository owner, 2026-11-16');
 END $bind_owner$;`;
}
