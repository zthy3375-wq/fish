import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { createCommunity } from '../functions/community/core.mjs';

let pg, app, owner, moderator, member;
const schema = await readFile(new URL('../community-schema.sql', import.meta.url), 'utf8');
const register = (input, peer) => app.execute('register', { agreed:true, password:'synthetic-long-password', ...input }, '', peer);
const call = (who, action, body = {}) => app.execute(action, body, who?.sessionToken ?? '', 'test-directory');
const list = (who, body) => call(who, 'admin.members', body);

before(async () => {
  pg = new PGlite();
  await pg.exec(schema);
  const db = async (a,b,t) => (await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t])).rows[0].result;
  app = createCommunity({ db, registrationEnabled:true });
  owner = await register({username:'dev_fixture',nickname:'开发测试'}, 'owner');
  moderator = await register({username:'moderator_fixture',nickname:'普通管理'}, 'moderator');
  member = await register({username:'20260115',nickname:'  校园小鱼  '}, 'member');
  await pg.query("UPDATE hyt_members SET role='moderator',developer_since=now() WHERE id=$1",[owner.user.id]);
  await pg.query("UPDATE hyt_members SET role='moderator',mod_caps=ARRAY['users','recommend','content','reports'] WHERE id=$1",[moderator.user.id]);
  await pg.exec(`INSERT INTO hyt_members(username,nickname,password_hash,recovery_hash,created_at)
    SELECT 'fixture_'||n,'校园同学'||n,'test','test','2026-11-16T01:03:00.123456Z'::timestamptz
    FROM generate_series(1,32) AS n;
    UPDATE hyt_members SET deleted_at=now() WHERE username='fixture_32';`);
});

after(async () => { await pg?.close(); });

test('registration saves the chosen nickname, enforces its range, and preserves old clients', async () => {
  assert.equal(member.user.nickname, '校园小鱼');
  assert.equal((await call(member,'me')).user.nickname, '校园小鱼');
  assert.equal((await call(owner,'profile.get',{memberId:member.user.id})).profile.nickname,'校园小鱼');
  for (const nickname of ['  ', '水', '字'.repeat(21)]) {
    await assert.rejects(register({username:'invalid_nickname_fixture',nickname}, 'invalid'), {code:'invalid_request'});
  }
  const previous = await register({username:'legacy_register_fixture'},'legacy');
  assert.match(previous.user.nickname, /^同学[0-9a-f]{6}$/);
  await call(previous,'account.delete',{password:'synthetic-long-password'});
});

test('the directory requires a live developer session, regardless of moderator capabilities', async () => {
  await assert.rejects(list(null), {code:'session_expired'});
  await assert.rejects(list(member,{role:'moderator',developerSince:'2000-01-01'}), {code:'forbidden'});
  await assert.rejects(list(moderator), {code:'forbidden'});
  await pg.query("UPDATE hyt_members SET banned_until=now()+interval '1 hour' WHERE id=$1",[owner.user.id]);
  try { await assert.rejects(list(owner), {code:'forbidden'}); }
  finally { await pg.query("UPDATE hyt_members SET banned_until=NULL WHERE id=$1",[owner.user.id]); }
});

test('counts live registrations, hides credentials, and paginates timestamp ties without loss', async () => {
  const first = await list(owner);
  assert.equal(first.registeredMemberCount,34);
  assert.equal(first.registeredMembers.length,30);
  assert(first.next?.beforeTime.endsWith('123456+00:00'));
  const second = await list(owner,first.next);
  assert.equal(second.registeredMemberCount,null);
  assert.equal(second.next,null);
  const all = [...first.registeredMembers,...second.registeredMembers];
  assert.equal(new Set(all.map(x=>x.id)).size,34);
  assert(!all.some(x=>x.username==='fixture_32'));
  for (const row of all) assert.deepEqual(Object.keys(row).sort(),['id','nickname','username']);
  assert.deepEqual((await list(owner,{query:'校园小鱼'})).registeredMembers,[{id:member.user.id,username:'20260115',nickname:'校园小鱼'}]);
  assert.equal((await list(owner,{query:'202601'})).registeredMembers.length,1);
  assert.deepEqual((await list(owner,{query:'%'})).registeredMembers,[]);
  await assert.rejects(list(owner,{beforeTime:'2026-11-16T00:00:00Z'}), {code:'invalid_request'});
});
