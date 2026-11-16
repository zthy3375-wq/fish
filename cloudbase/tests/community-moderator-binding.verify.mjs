import {test,beforeEach,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {moderatorBindingSQL} from '../../scripts/cloudbase/community-moderator-binding.mjs';
let db,owner,other;const digest=s=>createHash('sha256').update(s).digest('hex');
beforeEach(async()=>{db=new PGlite();await db.exec(await readFile('cloudbase/community-schema.sql','utf8'));owner=randomUUID();other=randomUUID();for(const [id,username] of [[owner,'synthetic_owner'],[other,'synthetic_other']])await db.query("INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash,bio) VALUES($1,$2,$2,'unchanged-password-hash','unchanged-recovery-hash','unchanged-bio')",[id,username]);});
afterEach(async()=>{await db.close();});
test('bootstrap grants only the exact account, preserves other fields and records one audit',async()=>{
 const original=(await db.query('SELECT to_jsonb(m) AS row FROM hyt_members m ORDER BY username')).rows;
 await db.exec(moderatorBindingSQL(digest('synthetic_owner'),owner));
 const rows=(await db.query('SELECT to_jsonb(m) AS row FROM hyt_members m ORDER BY username')).rows;
 assert.deepEqual(rows.map(x=>({...x.row,role:'member'})),original.map(x=>x.row));
 assert.equal(rows.find(x=>x.row.id===owner).row.role,'moderator');assert.equal(rows.find(x=>x.row.id===other).row.role,'member');
 assert.deepEqual((await db.query('SELECT moderator_id,action FROM hyt_moderation')).rows,[{moderator_id:owner,action:'grant_moderator'}]);
});
test('bootstrap is idempotent and existing sessions obtain the server-owned administrator role',async()=>{
 await db.query("INSERT INTO hyt_sessions(hash,member_id,expires_at) VALUES('synthetic-session',$1,now()+interval '1 day')",[owner]);
 await db.exec(moderatorBindingSQL(digest('synthetic_owner'),owner));await db.exec(moderatorBindingSQL(digest('synthetic_owner'),owner));
 assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_moderation')).rows[0].n,1);
 const r=await db.query("SELECT hyt_community('me','{}'::jsonb,'synthetic-session') AS result");assert.equal(r.rows[0].result.user.role,'moderator');
 const admin=await db.query("SELECT hyt_community('admin.reports','{}'::jsonb,'synthetic-session') AS result");assert.equal(admin.rows[0].result.status,200);
 const plain=await db.query("SELECT hyt_member_json(m)->>'role' AS role FROM hyt_members m WHERE id=$1",[other]);assert.equal(plain.rows[0].role,'member');
});
test('mismatched digest or stable ID cannot grant a different account',async()=>{
 await assert.rejects(db.exec(moderatorBindingSQL(digest('missing_owner'),owner)));await assert.rejects(db.exec(moderatorBindingSQL(digest('synthetic_owner'),other)));
 assert.equal((await db.query("SELECT count(*)::int AS n FROM hyt_members WHERE role='moderator'")).rows[0].n,0);
 assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_moderation')).rows[0].n,0);
});
test('deleted or currently muted accounts are rejected without changing their status',async()=>{
 await db.query('UPDATE hyt_members SET deleted_at=now() WHERE id=$1',[owner]);await assert.rejects(db.exec(moderatorBindingSQL(digest('synthetic_owner'),owner)));
 await db.query("UPDATE hyt_members SET banned_until=now()+interval '1 day' WHERE id=$1",[other]);await assert.rejects(db.exec(moderatorBindingSQL(digest('synthetic_other'),other)));
 assert.equal((await db.query("SELECT count(*)::int AS n FROM hyt_members WHERE role='moderator'")).rows[0].n,0);
});
test('binding inputs cannot inject SQL',()=>{assert.throws(()=>moderatorBindingSQL("' OR true--",owner));assert.throws(()=>moderatorBindingSQL(digest('synthetic_owner'),"'; SELECT 1--"));});
