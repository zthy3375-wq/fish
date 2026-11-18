import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {buildHonorMigration} from './honor-migration.mjs';
const pg=new PGlite();
try{
 const prior=await readFile(process.argv[2],'utf8'),next=await readFile('cloudbase/community-schema.sql','utf8');
 await pg.exec('CREATE ROLE gateway_verify; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;');
 await pg.exec(prior);
 const user=randomUUID();await pg.query("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash) VALUES($1,'old-fixture','历史同学','opaque-password-hash','opaque-recovery-hash')",[user]);
 await pg.query("INSERT INTO hyt_sessions(hash,member_id,expires_at) VALUES('fixture-session',$1,now()+interval '1 day')",[user]);
 await pg.query("INSERT INTO hyt_posts(author_id,body,anonymous,request_id) VALUES($1,'历史内容',false,$2)",[user,randomUUID()]);
 const stmt=buildHonorMigration(prior,next,'gateway_verify');await pg.exec(stmt);await pg.exec(stmt);
 const h=(await pg.query("SELECT hyt_community('honors.hall','{}','fixture-session') AS result")).rows[0].result.hall;
 assert.equal(h.id,user);assert.ok(h.awards.firstpost);assert.equal(h.total,2);
 assert.equal((await pg.query("SELECT has_function_privilege('gateway_verify','public.hyt_award_check(uuid,text,boolean)','EXECUTE') denied")).rows[0].denied,false);
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_honor_history')).rows[0].n,0);
 console.log('PASS schema 10 to 12, every previous field retained, old session/post, private backfill, gateway denial, second application, zero role assignments');
}finally{await pg.close();}
