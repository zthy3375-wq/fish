import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { communityRpcDigest, honorsMigration } from '../../scripts/cloudbase/community-honors-migration.mjs';

const baseline = process.env.HYT_COLLECTION_PREVIOUS_SCHEMA;

test('deploys only reviewed functions and honor tables over the contest-aware production baseline', {skip:!baseline}, async () => {
  const db = new PGlite();
  try {
    const base = await readFile(baseline,'utf8');
    const current = await readFile(new URL('../community-schema.sql',import.meta.url),'utf8');
    await db.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE hyt_http;');
    await db.exec(base);
    await db.exec(`
      INSERT INTO hyt_members(id,username,nickname,password_hash,recovery_hash,developer_since,role)
      VALUES ('00000000-0000-4000-8000-000000000001','owner_fixture','开发测试','fixture','fixture',now(),'moderator'),
             ('00000000-0000-4000-8000-000000000002','member_fixture','旧用户','fixture','fixture',NULL,'member');
      INSERT INTO hyt_sessions(hash,member_id,expires_at) VALUES('existing_member_session','00000000-0000-4000-8000-000000000002',now()+interval '1 day');
      INSERT INTO hyt_honors(member_id,kind) VALUES ('00000000-0000-4000-8000-000000000002','seed');
      UPDATE hyt_members SET worn_honor='seed' WHERE username='member_fixture';
    `);
    const migration = honorsMigration({base,current,httpRole:'hyt_http'});
    await db.exec(migration);
    await db.exec(migration);
    const [state] = (await db.query(`
      SELECT (SELECT count(*)::int FROM hyt_sessions) sessions,
             (SELECT count(*)::int FROM hyt_collection_grants) grants,
             (SELECT count(*)::int FROM hyt_collection_definitions) definitions,
             (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.hyt_community(text,jsonb,text)'::regprocedure) AS revision,
             (hyt_community('me','{}','existing_member_session') #>> '{user,badges,worn,code}') AS badge,
             (hyt_community('admin.members','{}','existing_member_session')->>'status') AS directory_status
    `)).rows;
    assert.deepEqual(state,{sessions:1,grants:0,definitions:29,revision:communityRpcDigest(current),badge:'seed',directory_status:'403'});
    const { rows:[projection] } = await db.query(`
      SELECT hyt_community('collection.profile','{}','existing_member_session') #>> '{collection,layoutVersion}' AS layout,
             hyt_community('profile.get','{"memberId":"00000000-0000-4000-8000-000000000002"}','existing_member_session')
               #> '{profile,collectionShowcase}' AS showcase,
             has_function_privilege('hyt_http','public.hyt_collection_showcase(public.hyt_members)','EXECUTE') AS direct_access
    `);
    assert.deepEqual(projection,{layout:'2',showcase:[],direct_access:false});
  } finally { await db.close(); }
});
