import { createHash } from 'node:crypto';
import { preservationBegin, preservationEnd } from './community-preservation.mjs';

function routine(schema, name, { last = false } = {}) {
  const marker = 'CREATE OR REPLACE FUNCTION public.' + name + '(';
  const start = last ? schema.lastIndexOf(marker) : schema.indexOf(marker);
  if (start < 0) throw Error('Missing migration routine: ' + name);
  const declaration = /\bAS (\$[a-z]*\$)/.exec(schema.slice(start));
  if (!declaration) throw Error('Missing routine body: ' + name);
  const delimiter = declaration[1];
  const bodyStart = start + declaration.index + declaration[0].length;
  const end = schema.indexOf(delimiter + ';', bodyStart);
  if (end < 0) throw Error('Unterminated routine: ' + name);
  return { statement: schema.slice(start, end + delimiter.length + 1), body: schema.slice(bodyStart, end) };
}

export function communityRpcDigest(schema) {
  return createHash('md5').update(routine(schema, 'hyt_community').body).digest('hex');
}

function privileges(httpRole) {
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(httpRole) || /^(public|postgres)$/i.test(httpRole)) throw Error('Unexpected community HTTP database role');
  return `
DO $privileges$ DECLARE name text; role text; helper record; BEGIN
 FOREACH name IN ARRAY ARRAY['hyt_collection_definitions','hyt_collection_grants','hyt_collection_audit'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC',name);
  FOREACH role IN ARRAY ARRAY['anon','authenticated','service_role','${httpRole}'] LOOP
   IF EXISTS(SELECT FROM pg_roles WHERE rolname=role) THEN
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I',name,role);
    IF has_table_privilege(role,'public.'||name,'SELECT') THEN RAISE EXCEPTION 'Direct community data access remains'; END IF;
   END IF;
  END LOOP;
 END LOOP;
 FOR helper IN SELECT oid::regprocedure AS signature FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname LIKE 'hyt_collection_%' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',helper.signature);
  FOREACH role IN ARRAY ARRAY['anon','authenticated','service_role','${httpRole}'] LOOP
   IF EXISTS(SELECT FROM pg_roles WHERE rolname=role) THEN
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',helper.signature,role);
    IF has_function_privilege(role,helper.signature::text,'EXECUTE') THEN RAISE EXCEPTION 'Direct community helper access remains'; END IF;
   END IF;
  END LOOP;
 END LOOP;
END $privileges$;
`;
}

const smoke = `
DO $smoke$
DECLARE
 developer_id uuid;
 sample_id uuid;
 developer_session text := md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text);
 sample_session text := md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text);
 result jsonb;
BEGIN
 SELECT id INTO STRICT developer_id FROM public.hyt_members
  WHERE developer_since IS NOT NULL AND role='moderator' AND deleted_at IS NULL AND (banned_until IS NULL OR banned_until<=now());
 SELECT id INTO STRICT sample_id FROM public.hyt_members
  WHERE developer_since IS NULL AND deleted_at IS NULL AND (banned_until IS NULL OR banned_until<=now())
  ORDER BY created_at,id LIMIT 1;
 BEGIN
  -- Synthetic hashes exist only in this rolled-back database subtransaction. No bearer token is issued.
  INSERT INTO public.hyt_sessions(hash,member_id,expires_at)
  VALUES(developer_session,developer_id,now()+interval '1 minute'),(sample_session,sample_id,now()+interval '1 minute');
  result := public.hyt_community('admin.members','{"query":""}',developer_session);
  IF (result->>'status') IS DISTINCT FROM '200'
     OR (result->>'registeredMemberCount')::bigint IS DISTINCT FROM (SELECT count(*) FROM public.hyt_members WHERE deleted_at IS NULL)
     OR jsonb_array_length(result->'registeredMembers')<1
     OR EXISTS(SELECT FROM jsonb_array_elements(result->'registeredMembers') m
       WHERE (m-'id'-'username'-'nickname')<>'{}'::jsonb OR NOT (m ?& ARRAY['id','username','nickname']))
  THEN RAISE EXCEPTION 'Developer directory smoke failed'; END IF;
  IF (public.hyt_community('admin.members','{}',sample_session)->>'status') IS DISTINCT FROM '403'
    OR (public.hyt_community('collection.admin','{}',sample_session)->>'status') IS DISTINCT FROM '403'
  THEN RAISE EXCEPTION 'Community administrator boundary failed'; END IF;
  result := public.hyt_community('collection.admin','{}',developer_session);
  IF (result->>'status') IS DISTINCT FROM '200'
   OR NOT EXISTS(SELECT FROM jsonb_array_elements(result->'honorDefinitions') AS h WHERE h->>'code'='first-hundred')
  THEN RAISE EXCEPTION 'Developer honors smoke failed'; END IF;
  result := public.hyt_community('collection.profile',jsonb_build_object('memberId',developer_id),sample_session);
  IF (result->>'status') IS DISTINCT FROM '200'
   OR (result #>> '{collection,id}') IS DISTINCT FROM developer_id::text
   OR (result #>> '{collection,layoutVersion}') IS DISTINCT FROM '2'
   OR (public.hyt_community('collection.archive','{"section":"legend"}',sample_session)->>'status') IS DISTINCT FROM '200'
  THEN RAISE EXCEPTION 'Honor reads smoke failed'; END IF;
  RAISE SQLSTATE 'ZX018';
 EXCEPTION WHEN SQLSTATE 'ZX018' THEN NULL;
 END;
END $smoke$;
`;

export function honorsMigration({ base, current, httpRole }) {
  const oldDigest = communityRpcDigest(base);
  const newDigest = communityRpcDigest(current);
  const createStart = current.indexOf('CREATE TABLE IF NOT EXISTS public.hyt_collection_definitions');
  const createEnd = current.indexOf('CREATE OR REPLACE FUNCTION public.hyt_badges(', createStart);
  if (createStart < 0 || createEnd < 0) throw Error('Missing additive collection structure');
  return `BEGIN;
${preservationBegin}
DO $guard$ DECLARE digest text; BEGIN
 SELECT md5(prosrc) INTO STRICT digest FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure;
 IF digest NOT IN ('${oldDigest}','${newDigest}') THEN RAISE EXCEPTION 'Unexpected live community RPC'; END IF;
END $guard$;
${current.slice(createStart, createEnd)}
${routine(current, 'hyt_hall').statement}
${routine(current, 'hyt_member_json').statement}
${routine(current, 'hyt_profile_json').statement}
${routine(current, 'hyt_collection_api').statement}
${routine(current, 'hyt_community').statement}
${routine(current, 'hyt_contests').statement}
${routine(current, 'hyt_badges', {last:true}).statement}
${privileges(httpRole)}
${smoke}
${preservationEnd}
COMMIT;`;
}
