// Lock and compare every original column/value; additive columns are allowed.
export const preservationBegin=`
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='90s';
CREATE TEMP TABLE hyt_deploy_previous_rows(object_name text,row_hash text) ON COMMIT DROP;
CREATE TEMP TABLE hyt_deploy_previous_columns(object_name text,column_names text[]) ON COMMIT DROP;
DO $$ DECLARE obj record; BEGIN
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hyt\\_%' ESCAPE '\\' ORDER BY tablename LOOP
  EXECUTE format('LOCK TABLE public.%I IN SHARE MODE',obj.tablename);
 END LOOP;
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hyt\\_%' ESCAPE '\\' ORDER BY tablename LOOP
  INSERT INTO hyt_deploy_previous_columns SELECT obj.tablename,array_agg(column_name::text ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name=obj.tablename;
  EXECUTE format('INSERT INTO hyt_deploy_previous_rows SELECT %L,md5(to_jsonb(existing_row)::text) FROM public.%I existing_row',obj.tablename,obj.tablename);
 END LOOP;
END $$;
`;
export const preservationEnd=`
DO $$ DECLARE obj record; changed boolean; BEGIN
 FOR obj IN SELECT object_name,column_names FROM hyt_deploy_previous_columns LOOP
  EXECUTE format('SELECT EXISTS(SELECT row_hash FROM hyt_deploy_previous_rows WHERE object_name=%L EXCEPT ALL SELECT md5((SELECT jsonb_object_agg(k,v) FROM jsonb_each(to_jsonb(existing_row)) e(k,v) WHERE k=ANY($1))::text) FROM public.%I existing_row)',obj.object_name,obj.object_name) INTO changed USING obj.column_names;
  IF changed THEN RAISE EXCEPTION 'Existing community rows changed during migration in %',obj.object_name; END IF;
 END LOOP;
END $$;
`;
