import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import { createCommunity } from "../functions/community/core.mjs";

const currentYear = Number(new Intl.DateTimeFormat("en", {year:"numeric",timeZone:"Asia/Shanghai"}).format(new Date()));
const schema = await readFile(new URL("../community-schema.sql", import.meta.url), "utf8");
let pg, server, owner, member, other;
const sql = (text, args) => pg.query(text, args);
const call = (user, action, body = {}) => server.execute(action, body, user.sessionToken, "isolated-collection-test");
const change = (body, requestId = randomUUID()) => call(owner, "collection.change", { reason:"核对社区资料", ...body, requestId });
const open = (user, memberId) => call(user, "collection.profile", { memberId }).then(r => r.collection);
before(async () => {
  pg = new PGlite();
  await pg.exec("CREATE ROLE anon; CREATE ROLE authenticated");
  await pg.exec(schema);
  const db = async (action, body, token) => (await sql("SELECT hyt_community($1,$2::jsonb,$3) AS result",[action, JSON.stringify(body), token])).rows[0].result;
  server = createCommunity({ db, registrationEnabled:true });
  const register = name => server.execute("register",{username:name,password:"collection-fixture-password",agreed:true},"",name);
  owner = await register("developer"); member = await register("early"); other = await register("later");
  await sql("UPDATE hyt_members SET developer_since=now(),role='moderator',created_at=now()-interval '2 years' WHERE id=$1",[owner.user.id]);
  await sql("UPDATE hyt_members SET created_at=now()-interval '2 years'+interval '10 days' WHERE id=$1",[member.user.id]);
  await pg.exec("INSERT INTO hyt_members(username,nickname,password_hash,recovery_hash,created_at) SELECT 'fixture'||n,'fixture'||n,'test','test',now()-interval '1 year'+n*interval '1 day' FROM generate_series(1,100) n");
  await sql("INSERT INTO hyt_honors(member_id,kind) VALUES($1,'seed')",[member.user.id]);
});
after(async () => pg?.close());

test("registration order, legacy identity reuse, hidden privacy, idempotent migration and RLS", async () => {
  assert.equal(server.config().honorCollectionEnabled,true);
  const data = await open(member);
  assert(data.items.some(i=>i.code==="first-hundred"&&i.awardId));
  assert(data.items.some(i=>i.code==="early-resident"&&i.awardId));
  assert.deepEqual(data.identities,["seed"]);
  const secret = data.items.find(i=>i.code==="world-lines");
  assert(secret?.awardId);
  assert.equal(secret.criteria,null);
  assert.equal(data.items.some(i=>i.code==="before-dawn"),false);
  const theirs = await open(other, member.user.id);
  assert(theirs.items.every(i=>i.category!=="hidden"));
  assert.equal((await open(other)).items.find(i=>i.code==="first-hundred").awardId,null);
  assert.equal((await sql("SELECT has_table_privilege('anon','hyt_collection_grants','SELECT') ok")).rows[0].ok,false);
  assert.equal((await sql("SELECT has_function_privilege('authenticated','hyt_collection_api(text,jsonb,hyt_members)','EXECUTE') ok")).rows[0].ok,false);
  await pg.exec(schema);
  assert.deepEqual((await open(member)).items.map(i=>i.awardId),data.items.map(i=>i.awardId));
  assert.equal((await sql("SELECT count(*)::int n FROM hyt_honors WHERE member_id=$1",[member.user.id])).rows[0].n,1);
});

test("one wearer with an explicit title, hidden opt-in and private acknowledgements", async () => {
  const mine = await open(member);
  const secret = mine.items.find(i=>i.code==="world-lines");
  await assert.rejects(call(other,"collection.wear",{awardId:secret.awardId}),{code:"invalid_showcase"});
  await assert.rejects(call(member,"collection.wear",{awardId:secret.awardId}),{code:"honor_visibility_required"});
  await change({operation:"title",memberId:member.user.id,title:"校园守夜人"});
  await call(member,"collection.visibility",{awardId:secret.awardId,public:true});
  const r = await call(member,"collection.wear",{awardId:secret.awardId,useTitle:true});
  assert.equal(r.updatedIdentity.badges.collection.title,"校园守夜人");
  assert.equal(r.updatedIdentity.badges.worn,null);
  assert((await open(other,member.user.id)).items.some(i=>i.awardId===secret.awardId));
  await call(other,"collection.ack",{awardIds:[secret.awardId]});
  assert((await open(member)).unseen.includes(secret.awardId));
  await call(member,"collection.ack",{awardIds:[secret.awardId]});
  assert(!(await open(member)).unseen.includes(secret.awardId));
  await call(member,"collection.visibility",{awardId:secret.awardId,public:false});
  assert.equal((await open(other,member.user.id)).items.some(i=>i.awardId===secret.awardId),false);
});

test("developer-only issuance, evidence, capacity, audit, edition closure and stable history", async () => {
  await assert.rejects(call(member,"collection.admin"),{code:"forbidden"});
  await assert.rejects(call(member,"collection.change",{
    operation:"title",memberId:member.user.id,title:"不应获取",reason:"企图更改",requestId:randomUUID(),
  }),{code:"forbidden"});
  const year = currentYear;
  const config = {operation:"save",code:"welcoming-"+year,year,name:"欢迎你来",category:"limited",rarity:"epic",
    criteria:"参与经过审核的实际迎新",story:"为新同学回答校园问题",capacity:1};
  await assert.rejects(change({...config,code:"missing-year-suffix"}),{code:"invalid_request"});
  await change(config);
  const admin = await call(owner,"collection.admin",{query:member.user.nickname});
  const definition = admin.honorDefinitions.find(i=>i.code===config.code);
  const grant = {operation:"grant",definitionId:definition.id,memberId:member.user.id,evidence:"审核记录编号 ABC",story:"帮同学找到了校园车站"};
  const nonce = randomUUID();
  await change(grant,nonce); await change(grant,nonce);
  await assert.rejects(change({...grant,story:"改变旧回执"},nonce),{code:"request_conflict"});
  await assert.rejects(change({...grant,memberId:other.user.id}),{code:"honor_capacity"});
  const archive = await call(other,"collection.archive",{section:"annual",year});
  const record = archive.honorArchive.find(i=>i.code===config.code);
  assert.equal(record.story,grant.story);
  assert.equal(record.memberId,member.user.id);
  assert.equal(Object.hasOwn(record,"evidence"),false);
  assert((await call(owner,"collection.admin",{exceptions:true})).honorAudit.some(a=>a.outcome==="honor_capacity"));
  await change({operation:"archive",definitionId:definition.id});
  await assert.rejects(change({...grant,memberId:other.user.id}),{code:"honor_locked"});
  assert((await call(other,"collection.archive",{section:"retired"})).honorArchive.some(i=>i.awardId===record.awardId));
  await change({operation:"revoke",awardId:record.awardId});
  assert(!(await call(other,"collection.archive",{section:"annual",year})).honorArchive.some(i=>i.awardId===record.awardId));
  const history = await call(owner,"collection.admin",{memberId:member.user.id});
  assert(history.honorGrants.some(g=>g.id===record.awardId&&g.revoked));
});

test("upgrade keeps the original community rows, sessions and worn identities", {
  skip: !process.env.HYT_COLLECTION_PREVIOUS_SCHEMA,
}, async () => {
  const legacy = new PGlite();
  const { preservationBegin, preservationEnd } = await import("../../scripts/cloudbase/community-preservation.mjs");
  try {
    await legacy.exec(await readFile(process.env.HYT_COLLECTION_PREVIOUS_SCHEMA,"utf8"));
    const db = async (action, body, token) => (await legacy.query(
      "SELECT hyt_community($1,$2::jsonb,$3) AS result",[action, JSON.stringify(body), token])).rows[0].result;
    const app = createCommunity({db,registrationEnabled:true});
    const user = await app.execute("register",{username:"legacycollector",password:"legacy-fixture-password",agreed:true},"","legacy");
    const doAs = (action, body = {}) => app.execute(action,body,user.sessionToken,"legacy");
    const {post} = await doAs("posts.create",{requestId:randomUUID(),body:"原有公开帖子",anonymous:false});
    await doAs("comments.create",{postId:post.id,requestId:randomUUID(),body:"沿用的回复",anonymous:false});
    await legacy.query("INSERT INTO hyt_honors(member_id,kind) VALUES($1,'seed')",[user.user.id]);
    await doAs("honors.wear",{honor:"seed",showcase:[]});
    const before = await doAs("me");
    await legacy.exec("BEGIN;"+preservationBegin+schema+preservationEnd+"COMMIT;");
    const after = await doAs("me");
    assert.equal(after.user.id,before.user.id);
    assert.equal(after.user.badges.worn.code,"seed");
    assert.equal((await doAs("posts.get",{postId:post.id})).post.body,"原有公开帖子");
    assert.equal((await doAs("collection.profile")).collection.identities[0],"seed");
    assert.equal((await legacy.query("SELECT body FROM hyt_comments")).rows[0].body,"沿用的回复");
  } finally { await legacy.close(); }
});

test("an edition from an earlier year is retired automatically", async () => {
  const year = currentYear - 1;
  await change({operation:"save",code:"historical-edition-"+year,year,name:"往届收藏",category:"limited",rarity:"epic",
    criteria:"核实该年度活动参与",story:"历年校园记录"});
  const definition = (await call(owner,"collection.admin")).honorDefinitions.find(i=>i.code==="historical-edition-"+year);
  assert.equal(definition.archived,true);
  await assert.rejects(change({operation:"grant",definitionId:definition.id,memberId:member.user.id,
    evidence:"年度历史资料",story:"参与了该年度校园活动"}),{code:"honor_locked"});
});

test("popular creations require distinct established supporters on eligible public posts", async () => {
  await sql("UPDATE hyt_members SET created_at=now()-interval '45 days',collection_checked_at=NULL WHERE id=$1",[other.user.id]);
  const {post} = await call(other,"posts.create",{requestId:randomUUID(),body:"校园图书馆观察",anonymous:false});
  await sql("INSERT INTO hyt_reactions(post_id,member_id,kind) SELECT $1,id,'like' FROM hyt_members WHERE username LIKE 'fixture%' ORDER BY created_at LIMIT 9",[post.id]);
  assert.equal((await open(other)).items.find(x=>x.code==="landmark-post").awardId,null);
  await sql("INSERT INTO hyt_reactions(post_id,member_id,kind) VALUES($1,$2,'like')",[post.id,member.user.id]);
  await sql("UPDATE hyt_members SET collection_checked_at=NULL WHERE id=$1",[other.user.id]);
  assert((await open(other)).items.find(x=>x.code==="landmark-post").awardId);
  assert((await call(owner,"collection.admin")).honorAudit.some(row=>row.operation==="auto_grant"));
});
