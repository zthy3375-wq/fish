// Existing schema-8+ tables are held briefly while additive DDL runs. No content is logged.
export const preservationBegin=`
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='90s';
CREATE TEMP TABLE hyt_deploy_previous_rows(object_name text,row_hash text) ON COMMIT DROP;
DO $$ DECLARE obj record; BEGIN
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hyt\\_%' ESCAPE '\\' ORDER BY tablename LOOP
  EXECUTE format('LOCK TABLE public.%I IN SHARE MODE',obj.tablename);
 END LOOP;
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hyt\\_%' ESCAPE '\\' ORDER BY tablename LOOP
  EXECUTE format('INSERT INTO hyt_deploy_previous_rows SELECT %L,md5(row_to_json(existing_row)::text) FROM public.%I existing_row',obj.tablename,obj.tablename);
 END LOOP;
END $$;
`;
export const preservationEnd=`
DO $$ DECLARE obj record; changed boolean; BEGIN
 FOR obj IN SELECT DISTINCT object_name FROM hyt_deploy_previous_rows LOOP
  EXECUTE format('SELECT EXISTS(SELECT row_hash FROM hyt_deploy_previous_rows WHERE object_name=%L EXCEPT ALL SELECT md5(row_to_json(existing_row)::text) FROM public.%I existing_row)',obj.object_name,obj.object_name) INTO changed;
  IF changed THEN RAISE EXCEPTION 'Existing community rows changed during migration in %',obj.object_name; END IF;
 END LOOP;
END $$;
`;
