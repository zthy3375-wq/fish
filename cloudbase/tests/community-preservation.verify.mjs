import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {preservationBegin,preservationEnd} from '../../scripts/cloudbase/community-preservation.mjs';
let pg;const schema=await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
before(async()=>{pg=new PGlite();await pg.exec(schema);await pg.exec("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash) VALUES('00000000-0000-4000-8000-000000000001','preserved_account','原有昵称','synthetic','synthetic'); INSERT INTO hyt_posts(id,author_id,body,anonymous,request_id) VALUES('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','原有匿名内容',true,'00000000-0000-4000-8000-000000000003'); INSERT INTO hyt_responses(post_id,member_id,kind) VALUES('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','same'); DROP TABLE hyt_dm_reads,hyt_dm_messages,hyt_dm_threads CASCADE;");});
after(async()=>pg.close());
test('guarded additive upgrade preserves every prior row and creates private-message tables',async()=>{
 await pg.exec('BEGIN;'+preservationBegin+schema+preservationEnd+'COMMIT;');
 assert.equal((await pg.query('SELECT body FROM hyt_posts')).rows[0].body,'原有匿名内容');assert.equal((await pg.query('SELECT kind FROM hyt_responses')).rows[0].kind,'same');assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_dm_messages')).rows[0].n,0);
});
test('preservation guard aborts any row rewrite and transaction rollback restores original data',async()=>{
 await assert.rejects(pg.exec('BEGIN;'+preservationBegin+"UPDATE hyt_posts SET body='不得改写原内容';"+preservationEnd+'COMMIT;'),/Existing community rows changed/);
 await pg.exec('ROLLBACK;');assert.equal((await pg.query('SELECT body FROM hyt_posts')).rows[0].body,'原有匿名内容');
});
