import {createHash} from 'node:crypto';

// Replace just two existing functions in one transaction. CREATE OR REPLACE retains ownership and grants.
export function timeAwardMigration(oldSchema,newSchema) {
 const targets=[['hyt_hall','u public.hyt_members,viewer uuid','public.hyt_hall(public.hyt_members,uuid)','$'+'$'],
                ['hyt_community','a text,b jsonb,th text','public.hyt_community(text,jsonb,text)','$fn$']];
 const commands=targets.map(([name,args,signature,delimiter])=>{
  const parts=[oldSchema,newSchema].map(source=>{
   const start=source.indexOf('CREATE OR REPLACE FUNCTION public.'+name+'('+args+')');
   if(start<0)throw Error('missing function '+name);
   const first=source.indexOf(delimiter,start),end=source.indexOf(delimiter+';',first+delimiter.length);
   if(first<0||end<0)throw Error('invalid definition '+name);
   const digest=createHash('md5').update(source.slice(first+delimiter.length,end)).digest('hex');
   return {digest,sql:source.slice(start,end+delimiter.length+1)};
  });
  const [before,after]=parts;
  return `SELECT md5(prosrc) INTO STRICT revision FROM pg_proc WHERE oid='${signature}'::regprocedure;
  IF revision='${before.digest}' THEN EXECUTE convert_from(decode('${Buffer.from(after.sql).toString('base64')}','base64'),'UTF8');
  ELSIF revision<>'${after.digest}' THEN RAISE EXCEPTION 'unexpected function revision: ${name}'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='${signature}'::regprocedure)<>'${after.digest}' THEN RAISE EXCEPTION 'verification failed'; END IF;`;
 });
 return `DO $migration$ DECLARE revision text; BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('hyt-honor-schema'));
 ${commands.join('\n')} END $migration$;`;
}
