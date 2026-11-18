import {createHash} from 'node:crypto';
import {preservationBegin,preservationEnd} from './community-preservation.mjs';

const tables=['hyt_honors','hyt_awards','hyt_honor_history','hyt_recommendations'];
const functions=['hyt_credit','hyt_badges','hyt_progress','hyt_award_check','hyt_award_pending','hyt_hall'];
const quoted=items=>items.map(i=>"'"+i+"'").join(',');
function section(source,start,end){const i=source.indexOf(start),j=source.indexOf(end,i+start.length);if(i<0||j<0)throw Error('schema_marker_missing');return source.slice(i,j);}
function rpc(source){return section(source,'CREATE OR REPLACE FUNCTION public.hyt_community(','END $fn$;')+'END $fn$;';}
const digest=ddl=>createHash('md5').update(ddl.split('$fn$')[1]).digest('hex');
export function buildHonorMigration(previous,current,gatewayRole){
 if(!/^[a-zA-Z0-9_-]{1,100}$/.test(gatewayRole)||['public','postgres'].includes(gatewayRole.toLowerCase()))throw Error('unverified_gateway_role');
 const previousHash=digest(rpc(previous)),newRpc=rpc(current),newHash=digest(newRpc);
 const checkedTables=['hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_reactions','hyt_comment_likes','hyt_moderation'];
 const guard=preservationBegin.replaceAll("tablename LIKE 'hyt\\_%' ESCAPE '\\'",'tablename IN ('+quoted(checkedTables)+')');
 if(guard===preservationBegin)throw Error('preservation_guard_scope');
 const objects=section(current,'-- Identity and honor records','CREATE OR REPLACE FUNCTION public.hyt_post_json');
 const profile=section(current,'CREATE OR REPLACE FUNCTION public.hyt_profile_json','CREATE OR REPLACE FUNCTION public.hyt_dm_visible');
 const adminColumns=section(current,'ALTER TABLE public.hyt_moderation ADD COLUMN','CREATE TABLE IF NOT EXISTS public.hyt_community_rate');
 const acl=`DO $acl$ DECLARE obj record; role_name text; BEGIN
  FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN (${quoted(tables)}) LOOP
   EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
   EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC',obj.tablename);
   FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','${gatewayRole}'] LOOP
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,role_name);
     IF has_table_privilege(role_name,format('public.%I',obj.tablename),'SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'direct_table_privilege'; END IF;
    END IF;
   END LOOP;
  END LOOP;
  FOR obj IN SELECT oid,oid::regprocedure AS sig FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN (${quoted(functions)}) LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',obj.sig);
   FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','${gatewayRole}'] LOOP
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.sig,role_name);
     IF has_function_privilege(role_name,obj.oid,'EXECUTE') THEN RAISE EXCEPTION 'direct_function_privilege'; END IF;
    END IF;
   END LOOP;
  END LOOP;
 END $acl$;`;
 const statement=[guard,adminColumns,objects,profile,newRpc,acl,preservationEnd].join('\n');
 // One server-side transaction. The provider's SQL parameter adapter never sees nested
 // function parameters. A retry accepts only the old or the exact new RPC revision.
 return `DO $migration$ DECLARE current_hash text; BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('hyt-honor-schema'));
  SELECT md5(prosrc) INTO STRICT current_hash FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure;
  IF current_hash='${newHash}' THEN RETURN; END IF;
  IF current_hash<>'${previousHash}' THEN RAISE EXCEPTION 'unexpected_live_revision'; END IF;
  EXECUTE convert_from(decode('${Buffer.from(statement).toString('base64')}','base64'),'UTF8');
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure)<>'${newHash}' THEN RAISE EXCEPTION 'revision_verification'; END IF;
 END $migration$;`;
}
