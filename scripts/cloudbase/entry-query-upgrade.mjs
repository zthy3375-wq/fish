import {createHash} from 'node:crypto';

export function entryQueryUpgrade(oldSchema, newSchema) {
  const extract = schema => {
    const start = schema.indexOf('CREATE OR REPLACE FUNCTION public.hyt_community(');
    const end = schema.indexOf('$fn$;', schema.indexOf(' AS $fn$', start) + 9);
    if (start < 0 || end < 0) throw Error('Community function definition missing');
    const ddl = schema.slice(start, end+5);
    const body = ddl.split('$fn$')[1];
    return {ddl, md5:createHash('md5').update(body).digest('hex')};
  };
  const previous = extract(oldSchema), next = extract(newSchema);
  // Replacing this one routine preserves its owner, ACLs and all table contents.
  return `DO $upgrade$ DECLARE current_digest text; BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('hyt_community_entry_upgrade'));
    SELECT md5(prosrc) INTO STRICT current_digest FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure;
    IF current_digest='${next.md5}' THEN RETURN; END IF;
    IF current_digest<>'${previous.md5}' THEN RAISE EXCEPTION 'Unrecognized community query revision'; END IF;
    EXECUTE $ddl$${next.ddl}$ddl$;
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure)<>'${next.md5}' THEN RAISE EXCEPTION 'Community query verification failed'; END IF;
  END $upgrade$;`;
}
