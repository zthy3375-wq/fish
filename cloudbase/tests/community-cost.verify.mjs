import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import jpeg from '../functions/community/node_modules/jpeg-js/index.js';
import { createCommunity } from '../functions/community/core.mjs';
import * as database from '../functions/community/database.mjs';

let pg, api, author, reader;
const actions = [];
let clock = 0;
const call = (user, action, body = {}) => api.execute(action, body, user.sessionToken, 'cost-fixture');
before(async () => {
  pg = new PGlite();
  await pg.exec(await readFile(new URL('../community-schema.sql', import.meta.url), 'utf8'));
  api = createCommunity({ registrationEnabled: true, now: () => clock,
    db: async (action, body, hash) => {
      actions.push(action);
      return (await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result', [action, JSON.stringify(body), hash])).rows[0].result;
    },
    storage: { put: async () => {}, remove: async () => {}, url: async () => 'https://fixture.invalid/photo.jpg' },
  });
  const register = username => api.execute('register', { username, password: 'cost-fixture-password', agreed: true }, '', username);
  author = await register('cost_author'); reader = await register('cost_reader');
});
after(async () => pg.close());

test('combined unread authenticates and charges its persistent rate once, preserving counts', async () => {
  const before = (await pg.query('SELECT count FROM hyt_community_rate WHERE key=$1', ['member:' + reader.user.id])).rows[0]?.count || 0;
  const response = await call(reader, 'notifications.unread', { withMessages: true });
  const after = (await pg.query('SELECT count FROM hyt_community_rate WHERE key=$1', ['member:' + reader.user.id])).rows[0].count;
  assert.equal(after - before, 1);
  assert.equal(response.unreadCount, 0); assert.equal(response.messageUnreadCount, 0);
});

test('read acknowledgement returns global remaining unread without a second client request', async () => {
  const conversation = (await call(author, 'messages.open', { memberId: reader.user.id })).conversation;
  const sent = await call(author, 'messages.send', { conversationId: conversation.id, requestId: randomUUID(), body: '成本回归夹具' });
  assert.equal((await call(reader, 'messages.unread')).messageUnreadCount, 1);
  const acknowledged = await call(reader, 'messages.read', { conversationId: conversation.id, throughSeq: sent.message.seq, withUnread: true });
  assert.equal(acknowledged.messageUnreadCount, 0);
  assert.equal((await call(reader, 'messages.read', { conversationId: conversation.id, throughSeq: sent.message.seq })).messageUnreadCount, undefined);
});

test('uploads reuse opportunistic cleanup while explicit deletion remains immediate', async () => {
  const data = jpeg.encode({ width: 2, height: 2, data: Buffer.alloc(16, 120) }, 75).data.toString('base64');
  actions.length = 0;
  const first = await call(author, 'media.upload', { data, requestId: randomUUID() });
  await call(author, 'media.upload', { data, requestId: randomUUID() });
  assert.equal(actions.filter(a => a === 'media.cleanup').length, 1);
  await call(author, 'media.discard', { imageId: first.image.id });
  assert.equal(actions.filter(a => a === 'media.cleanup').length, 2);
  clock += 600_001;
  await call(author, 'media.upload', { data, requestId: randomUUID() });
  assert.equal(actions.filter(a => a === 'media.cleanup').length, 3);
});

test('parallel SQL calls share one credential exchange, and renew after expiry', async () => {
  assert.equal(typeof database.createSqlClient, 'function');
  let now = 0, exchanges = 0, sqlCalls = 0;
  const query = database.createSqlClient({ now: () => now, settings: () => ({ env: 'fixture-env', key: 'fixture-key' }), fetcher: async url => {
    if (url.includes('/capi/credential')) {
      exchanges++; await new Promise(r => setTimeout(r, 5));
      return { json: async () => ({ code: 0, data: { TmpSecretId: 'fixture-id', TmpSecretKey: 'fixture-secret', Token: 'fixture-token' } }) };
    }
    sqlCalls++; return { ok: true, json: async () => ({ Response: { Columns: ['value'], ColumnTypes: ['text'], Rows: [['ok']] } }) };
  } });
  await Promise.all(Array.from({ length: 8 }, () => query('SELECT 1')));
  assert.equal(exchanges, 1); assert.equal(sqlCalls, 8);
  now = 240_001; await query('SELECT 1'); assert.equal(exchanges, 2);
});

test('a failed credential exchange can retry without holding a rejected shared promise', async () => {
  assert.equal(typeof database.createSqlClient, 'function');
  let exchanges = 0;
  const query = database.createSqlClient({ settings: () => ({ env: 'fixture-env', key: 'fixture-key' }), fetcher: async url => {
    if (url.includes('/capi/credential')) {
      exchanges++; return { json: async () => exchanges === 1 ? { code: -1 } : { code: 0, data: { TmpSecretId: 'fixture-id', TmpSecretKey: 'fixture-secret', Token: 'fixture-token' } } };
    }
    return { ok: true, json: async () => ({ Response: { Columns: [], Rows: [] } }) };
  } });
  await assert.rejects(query('SELECT 1'), /credential_exchange_failed/);
  await query('SELECT 1'); assert.equal(exchanges, 2);
});

test('switching server environments never reuses credentials from the previous environment', async () => {
  let env = 'fixture-a'; const signers = [], exchanges = [];
  const query = database.createSqlClient({ settings: () => ({ env, key: 'fixture-' + env }), fetcher: async (url, options) => {
    if (url.includes('/capi/credential')) {
      const selected = JSON.parse(options.body).env; exchanges.push(selected);
      return { json: async () => ({ code: 0, data: { TmpSecretId: selected, TmpSecretKey: 'fixture-secret', Token: 'fixture-token' } }) };
    }
    signers.push(options.headers.Authorization);
    return { ok: true, json: async () => ({ Response: { Columns: [], Rows: [] } }) };
  } });
  await query('SELECT 1'); env = 'fixture-b'; await query('SELECT 1');
  assert.deepEqual(exchanges, ['fixture-a', 'fixture-b']);
  assert(signers[0].includes('Credential=fixture-a/')); assert(signers[1].includes('Credential=fixture-b/'));
});

test('migration SQL without bound arguments preserves dollar parameters inside function bodies', async () => {
  const source="CREATE FUNCTION fixture(v int) RETURNS int LANGUAGE sql AS $$ SELECT $1 $$;";
  const sent=[];
  const query=database.createSqlClient({settings:()=>({env:'fixture-env',key:'fixture-key'}),fetcher:async(url,options)=>{
    if(url.includes('/capi/credential'))return {json:async()=>({code:0,data:{TmpSecretId:'fixture-id',TmpSecretKey:'fixture-secret',Token:'fixture-token'}})};
    sent.push(JSON.parse(options.body).Sql);return {ok:true,json:async()=>({Response:{Columns:[],Rows:[]}})};
  }});
  await query(source);assert.equal(sent[0],source);
  await query('SELECT $1::text',["literal $2 '"]);assert.equal(sent[1],database.bindSQL('SELECT $1::text',["literal $2 '"]));
});
