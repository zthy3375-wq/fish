import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import jpeg from "../functions/community/node_modules/jpeg-js/index.js";
import { createCommunity } from "../functions/community/core.mjs";
let pg, api, owner, users;
const schema = await readFile(
  new URL("../community-schema.sql", import.meta.url),
  "utf8",
);
const call = (u, a, b = {}) =>
  api.execute(a, b, u.sessionToken, "shared-campus-network");
const iso = (hours) => new Date(Date.now() + hours * 3600000).toISOString();
const config = (id = randomUUID()) => ({
  contestId: id,
  title: "校园里的光",
  type: "摄影赛",
  edition: "第一届",
  description: "分享校园生活",
  rules: "原创作品；同票并列，下一名次连续排列。",
  startsAt: iso(-1),
  submissionEnds: iso(5),
  votingStarts: iso(5),
  votingEnds: iso(6),
  awardAt: iso(7),
  formats: ["text", "image", "mixed"],
  maxEntries: 1,
  votesPerUser: 3,
  minEntries: 5,
  minAccountHours: 0,
  excellence: 3,
  autoPublish: true,
});
const event = async (extra = {}) => {
  const data = { ...config(), ...extra };
  await call(owner, "contests.save", data);
  await call(owner, "contests.manage", {
    contestId: data.contestId,
    operation: "publish",
    reason: "发布已核对的测试规则",
  });
  return data.contestId;
};
const submit = (who, id, extra = {}) =>
  call(who, "contests.submit", {
    contestId: id,
    entryId: null,
    requestId: randomUUID(),
    title: "校园一角",
    body: "记录一束校园里的光",
    images: [],
    agreed: true,
    ...extra,
  }).then((r) => r.entry);
const voting = (id) =>
  pg.query(
    "UPDATE hyt_contests SET starts_at=now()-interval '3 hours',submission_ends=now()-interval '2 hours',voting_starts=now()-interval '1 hour',voting_ends=now()+interval '1 hour',award_at=now()+interval '2 hours' WHERE id=$1",
    [id],
  );
const ending = (id) =>
  pg.query(
    "UPDATE hyt_contests SET starts_at=now()-interval '5 hours',submission_ends=now()-interval '4 hours',voting_starts=now()-interval '3 hours',voting_ends=now()-interval '2 hours',award_at=now()-interval '1 hour' WHERE id=$1",
    [id],
  );
const vote = (u, c, e, enabled = true) =>
  call(u, "contests.vote", { contestId: c, entryId: e.id, enabled });
before(async () => {
  pg = new PGlite();
  await pg.exec(schema);
  api = createCommunity({
    contestsEnabled: true,
    registrationEnabled: true,
    db: async (a, b, t) =>
      (
        await pg.query("SELECT hyt_community($1,$2::jsonb,$3) AS result", [
          a,
          JSON.stringify(b),
          t,
        ])
      ).rows[0].result,
    storage: {
      put: async () => {},
      url: async (k) => "https://fixture.invalid/" + k,
      remove: async () => {},
    },
  });
  const reg = (username) =>
    api.execute(
      "register",
      { username, password: "synthetic-contest-password", agreed: true },
      "",
      username,
    );
  owner = await reg("owner");
  users = [];
  for (let i = 0; i < 9; i++) users.push(await reg("member" + i));
  await pg.query("UPDATE hyt_members SET developer_since=now() WHERE id=$1", [
    owner.user.id,
  ]);
  await pg.exec("UPDATE hyt_members SET created_at=now()-interval '30 days'");
});
beforeEach(async () => {
  await pg.exec(
    "TRUNCATE hyt_contests CASCADE; DELETE FROM hyt_community_rate; TRUNCATE hyt_contest_themes CASCADE;",
  );
});
after(() => pg.close());
test("developer authorizes real schedule, supports arbitrary type and preserves old account data on migration", async () => {
  await assert.rejects(call(users[0], "contests.save", config()), {
    code: "forbidden",
  });
  const c = await event({ type: "未来可扩展的比赛" });
  const r = await call(users[0], "contests.get", { contestId: c });
  assert.equal(r.contest.state, "submitting");
  assert.equal(r.contest.type, "未来可扩展的比赛");
  assert(r.serverTime);
  await pg.exec(schema);
  assert.equal((await call(users[0], "me")).user.id, users[0].user.id);
  assert.equal((await call(users[0], "contests.list")).contests.length, 1);
});
test("submission quotas, retry, foreign posts, edit and withdrawal obey server stage", async () => {
  const c = await event();
  const requestId = randomUUID();
  const e = await submit(users[0], c, { requestId });
  assert.equal((await submit(users[0], c, { requestId })).id, e.id);
  await assert.rejects(submit(users[0], c), { code: "contest_entry_limit" });
  await assert.rejects(submit(users[1], c, { postId: randomUUID() }), {
    code: "forbidden",
  });
  const revised = await submit(users[0], c, { entryId: e.id, title: "修订" });
  assert.equal(revised.title, "修订");
  await call(users[0], "contests.withdraw", { contestId: c, entryId: e.id });
  assert.equal(
    (
      await call(users[1], "contests.entries", {
        contestId: c,
        seed: randomUUID(),
      })
    ).entries.length,
    0,
  );
  const reentered=await submit(users[0],c,{title:'撤回后的新作品'});assert.notEqual(reentered.id,e.id);assert.equal(reentered.status,'approved');
  await voting(c);
  await assert.rejects(submit(users[1], c), { code: "contest_closed" });
  await assert.rejects(
    call(users[0], "contests.withdraw", { contestId: c, entryId: e.id }),
    { code: "contest_closed" },
  );
});
test("image submissions project signed images and orphan cleanup preserves attached uploads", async () => {
  const c = await event();
  const data = jpeg
    .encode({ width: 4, height: 4, data: Buffer.alloc(64, 180) }, 80)
    .data.toString("base64");
  const image = (
    await call(users[0], "media.upload", { data, requestId: randomUUID() })
  ).image;
  const e = await submit(users[0], c, { images: [image.id], body: "" });
  assert(e.images[0].url);
  assert.equal(e.body, "");
  await pg.exec("UPDATE hyt_media SET created_at=now()-interval '8 days'");
  await pg.query("SELECT hyt_community('media.cleanup','{}','')");
  const wall = await call(users[1], "contests.entries", {
    contestId: c,
    seed: randomUUID(),
  });
  assert.equal(wall.entries[0].images[0].id, image.id);
});
test("concurrent retries consume one vote, quota is enforced and own works are rejected", async () => {
  const c = await event();
  const entries = [];
  for (let i = 0; i < 5; i++) entries.push(await submit(users[i], c));
  await voting(c);
  await assert.rejects(vote(users[0], c, entries[0]), {
    code: "contest_self_vote",
  });
  await Promise.all(
    Array.from({ length: 8 }, () => vote(users[8], c, entries[0])),
  );
  assert.equal(
    (await call(users[8], "contests.get", { contestId: c })).votesUsed,
    1,
  );
  await vote(users[8], c, entries[1]);
  await vote(users[8], c, entries[2]);
  await assert.rejects(vote(users[8], c, entries[3]), {
    code: "contest_vote_limit",
  });
  await vote(users[8], c, entries[0], false);
  await vote(users[8], c, entries[3]);
  await call(owner, "contests.review", {
    contestId: c,
    kind: "entry",
    targetId: entries[3].id,
    decision: "remove",
    reason: "投票中下架违规作品",
  });
  await vote(users[8], c, entries[4]);
  assert.equal(
    (await call(users[8], "contests.get", { contestId: c })).votesUsed,
    3,
  );
  const wall = await call(users[7], "contests.entries", {
    contestId: c,
    seed: randomUUID(),
  });
  assert(wall.entries.every((e) => e.votes === null));
});
test("fixed registration qualification, deadline equality, pause and cancellation are server enforced", async () => {
  const c = await event({ minAccountHours: 72 });
  const e = await submit(users[0], c);
  await voting(c);
  await pg.query("UPDATE hyt_members SET created_at=now() WHERE id=$1", [
    users[8].user.id,
  ]);
  await assert.rejects(vote(users[8], c, e), { code: "contest_ineligible" });
  await pg.query(
    "UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",
    [users[8].user.id],
  );
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "pause",
    reason: "暂停核查作品",
  });
  await assert.rejects(vote(users[8], c, e), { code: "contest_closed" });
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "resume",
    reason: "核查完成恢复",
  });
  for(let i=0;i<13;i++){await vote(users[8],c,e);if(i<12)await vote(users[8],c,e,false);}
  await ending(c);
  await assert.rejects(vote(users[8], c, e, false), { code: "contest_closed" });
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "cancel",
    reason: "活动取消保留记录",
  });
  assert.equal(
    (await call(users[0], "contests.get", { contestId: c })).contest.state,
    "cancelled",
  );
  assert.equal((await call(users[0], "contests.profile")).stats.champions, 0);
});
test("risk votes stop automatic publication, review exclusions update tally and all operations are audited", async () => {
  const c = await event({ minEntries: 1 });
  const e = await submit(users[0], c);
  await voting(c);
  await pg.query(
    "UPDATE hyt_members SET created_at=now()-interval '2 days' WHERE id=$1",
    [users[8].user.id],
  );
  for(let i=0;i<13;i++){await vote(users[8],c,e);if(i<12)await vote(users[8],c,e,false);}
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  assert.equal(
    (await call(users[0], "contests.get", { contestId: c })).contest.state,
    "reviewing",
  );
  const v = (await call(owner, "contests.admin", { contestId: c })).votes[0];
  assert.equal(v.risk, "vote_burst");
  await call(owner, "contests.review", {
    contestId: c,
    kind: "vote",
    targetId: v.id,
    decision: "exclude",
    reason: "核验为无效测试票",
  });
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "announce",
    reason: "复核完成公布结果",
  });
  assert.equal((await call(users[0], "contests.profile")).stats.champions, 0);
  assert(
    (await call(owner, "contests.admin", { contestId: c })).audit.some(
      (x) => x.reason === "核验为无效测试票",
    ),
  );
  await pg.query(
    "UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",
    [users[8].user.id],
  );
});
test("dense ties, repeat settlement and award revocation synchronize profile and worn honor", async () => {
  const c = await event({ minEntries: 2 });
  const e = await submit(users[0], c),
    other = await submit(users[1], c);
  await voting(c);
  await vote(users[7], c, e);
  await vote(users[8], c, other);
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  await pg.query("SELECT hyt_contest_tick()");
  let profile = await call(users[0], "contests.profile");
  assert.equal(profile.stats.champions, 1);
  assert.equal(profile.stats.participations, 1);
  const badge = profile.awards.find((x) => x.kind === "champion");
  await call(users[0], "contests.wear", { awardId: badge.id });
  assert.equal(
    (await call(users[1], "contests.profile", { memberId: users[0].user.id }))
      .worn,
    badge.id,
  );
  assert.equal((await call(users[1], "contests.profile")).stats.champions, 1);
  await call(owner, "contests.review", {
    contestId: c,
    kind: "entry",
    targetId: e.id,
    decision: "remove",
    reason: "确认作品违规撤奖",
  });
  profile = await call(users[0], "contests.profile");
  assert.equal(profile.stats.champions, 0);
  assert.equal(profile.worn, null);
  assert(
    (
      await pg.query("SELECT revoked_at FROM hyt_contest_awards WHERE id=$1", [
        badge.id,
      ])
    ).rows[0].revoked_at,
  );
});
test("underfilled events issue participation only and theme proposals need developer approval", async () => {
  const c = await event();
  const e = await submit(users[0], c);
  await voting(c);
  for(let i=0;i<13;i++){await vote(users[8],c,e);if(i<12)await vote(users[8],c,e,false);}
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  const profile = await call(users[0], "contests.profile");
  assert.equal(profile.stats.champions, 0);
  assert.equal(profile.stats.participations, 1);
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "solicitation",
    enabled: true,
    reason: "征集下一期主题",
  });
  const r = await call(users[0], "contests.suggest", {
    title: "食堂美食摄影",
    requestId: randomUUID(),
  });
  const theme = r.themes[0];
  assert.equal((await call(users[1], "contests.themes")).themes.length, 0);
  await call(owner, "contests.review", {
    contestId: c,
    kind: "theme",
    targetId: theme.id,
    decision: "approve",
    reason: "适合校园摄影比赛",
  });
  await call(users[1], "contests.themevote", {
    themeId: theme.id,
    enabled: true,
  });
  assert.equal((await call(users[1], "contests.themes")).themes[0].votes, 1);
});
test("replayed request conflicts on changed content and edit retries preserve the same revision", async () => {
  const c = await event(),
    requestId = randomUUID();
  const e = await submit(users[0], c, { requestId });
  await assert.rejects(
    submit(users[0], c, { requestId, title: "改变重试内容" }),
    { code: "request_conflict" },
  );
  const editRequest = randomUUID(),
    first = await submit(users[0], c, {
      entryId: e.id,
      requestId: editRequest,
      title: "正式修订",
    }),
    second = await submit(users[0], c, {
      entryId: e.id,
      requestId: editRequest,
      title: "正式修订",
    });
  assert.equal(first.version, second.version);
});
test("exact voting deadline rejects withdrawal and a not-yet-started vote cannot be cast", async () => {
  const c = await event(),
    e = await submit(users[0], c);
  await assert.rejects(vote(users[8], c, e), { code: "contest_closed" });
  await voting(c);
  await vote(users[8], c, e);
  await pg.query(
    "UPDATE hyt_contests SET voting_ends=clock_timestamp() WHERE id=$1",
    [c],
  );
  await assert.rejects(vote(users[8], c, e, false), { code: "contest_closed" });
});
test("annual ranking is archived once, revisions revoke stale annual honors and achievements retain original dates", async () => {
  const c = await event({ minEntries: 1 }),
    e = await submit(users[0], c);
  await voting(c);
  for(let i=0;i<13;i++){await vote(users[8],c,e);if(i<12)await vote(users[8],c,e,false);}
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  const profile = await call(users[0], "contests.profile");
  assert(profile.achievements.some((a) => a.code === "first_champion"));
  const before = (
    await pg.query(
      "SELECT unlocked_at FROM hyt_contest_achievements WHERE member_id=$1",
      [users[0].user.id],
    )
  ).rows[0].unlocked_at;
  await pg.query(
    "UPDATE hyt_contest_awards SET awarded_at=now()-interval '1 year' WHERE contest_id=$1",
    [c],
  );
  await pg.query("SELECT hyt_contest_achievements_refresh($1)", [c]);
  await pg.query("SELECT hyt_contest_tick()");
  assert.equal((await call(users[0], "contests.profile")).annual.length, 1);
  assert.equal(
    (
      await pg.query(
        "SELECT unlocked_at FROM hyt_contest_achievements WHERE member_id=$1",
        [users[0].user.id],
      )
    ).rows[0].unlocked_at.getTime(),
    before.getTime(),
  );
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "cancel",
    reason: "确认年度作品违规",
  });
  await pg.query("SELECT hyt_contest_tick()");
  const after = await call(users[0], "contests.profile");
  assert.deepEqual(after.annual, []);
  assert.deepEqual(after.achievements, []);
});
test("duplicate theme merge deduplicates supporters and preserves a moderation snapshot", async () => {
  const c = await event();
  await call(owner, "contests.manage", {
    contestId: c,
    operation: "solicitation",
    enabled: true,
    reason: "征集主题",
  });
  const first = (
    await call(users[0], "contests.suggest", {
      title: "校园日出摄影",
      requestId: randomUUID(),
    })
  ).themes[0];
  const second = (
    await call(users[1], "contests.suggest", {
      title: "拍校园的日出",
      requestId: randomUUID(),
    })
  ).themes[0];
  for (const theme of [first, second]) {
    await call(owner, "contests.review", {
      contestId: c,
      kind: "theme",
      targetId: theme.id,
      decision: "approve",
      reason: "主题符合活动要求",
    });
    await call(users[8], "contests.themevote", {
      themeId: theme.id,
      enabled: true,
    });
  }
  await call(owner, "contests.review", {
    contestId: c,
    kind: "merge",
    targetId: second.id,
    mergeId: first.id,
    decision: "approve",
    reason: "合并相同摄影主题",
  });
  assert.equal((await call(users[8], "contests.themes")).themes[0].votes, 1);
  const log = (
    await pg.query(
      "SELECT snapshot FROM hyt_contest_audit WHERE action='merge:approve'",
    )
  ).rows[0];
  assert.equal(log.snapshot.title, "拍校园的日出");
});
test("community account deletion removes competition content and retracts confirmed votes", async () => {
  const temp = await api.execute(
    "register",
    {
      username: "temporary_contest_user",
      password: "synthetic-contest-password",
      agreed: true,
    },
    "",
    "temporary",
  );
  await pg.query(
    "UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",
    [temp.user.id],
  );
  const c = await event({ minEntries: 1 }),
    e = await submit(users[0], c);
  await submit(temp, c);
  await voting(c);
  await vote(temp, c, e);
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  await call(temp, "account.delete", {
    password: "synthetic-contest-password",
  });
  assert.equal((await call(users[0], "contests.profile")).stats.champions, 0);
  const wall = await call(users[1], "contests.entries", {
    contestId: c,
    seed: randomUUID(),
  });
  assert.equal(wall.entries.length, 1);
  assert.equal(wall.entries[0].votes, 0);
});
test("shared submission creates one community post and later competition edits preserve its own content", async () => {
  const c = await event();
  const requestId = randomUUID();
  const e = await submit(users[0], c, { requestId, share: true });
  assert(e.postId);
  assert.equal(e.linked, false);
  await submit(users[0], c, { requestId, share: true });
  assert.equal(
    (
      await pg.query(
        "SELECT count(*)::int AS n FROM hyt_posts WHERE request_id=$1",
        [requestId],
      )
    ).rows[0].n,
    1,
  );
  const edit = await submit(users[0], c, {
    entryId: e.id,
    postId: e.postId,
    title: "修订后的作品",
    body: "重新编辑的正文",
  });
  assert.equal(edit.body, "重新编辑的正文");
  assert.equal(edit.postId, e.postId);
  const relink = await submit(users[0], c, {
    entryId: e.id,
    postId: e.postId,
    linkPost: true,
    body: "客户端提供的正文不覆盖原帖",
  });
  assert.equal(relink.linked, true);
  const original = (
    await pg.query("SELECT body FROM hyt_posts WHERE id=$1", [e.postId])
  ).rows[0];
  assert.equal(relink.body, original.body);
  const detached = await submit(users[0], c, {
    entryId: e.id,
    body: "改回直接投稿",
  });
  assert.equal(detached.linked, false);
  assert.equal(detached.postId, null);
  assert.equal(detached.body, "改回直接投稿");
});
test("randomized cursor pagination remains disjoint when submissions arrive between pages", async () => {
  const c = await event({ maxEntries: 4 }),
    seed = randomUUID();
  for (let i = 0; i < 9; i++)
    for (let j = 0; j < 3; j++) await submit(users[i], c);
  const first = (
    await call(users[8], "contests.entries", { contestId: c, seed })
  ).entries.slice(0, 20);
  await submit(users[0], c, { title: "分页期间的新作品" });
  const second = (
    await call(users[8], "contests.entries", {
      contestId: c,
      seed,
      afterId: first.at(-1).id,
    })
  ).entries;
  assert(second.length >= 7);
  assert(
    second.every(
      (entry) => !first.some((previous) => previous.id === entry.id),
    ),
  );
});
test("developer report context and award ledger use competition-specific response fields", async () => {
  const c = await event({ minEntries: 1 }),
    e = await submit(users[0], c);
  await call(users[1], "contests.report", {
    contestId: c,
    entryId: e.id,
    reason: "请核实作品授权",
  });
  const review = await call(owner, "contests.admin", { contestId: c });
  assert.equal(review.contestReports[0].entry.title, e.title);
  assert(!("reports" in review));
  await call(owner, "contests.review", {
    contestId: c,
    kind: "entry",
    targetId: e.id,
    decision: "approve",
    reason: "已核实作者授权",
  });
  assert.deepEqual(
    (await call(owner, "contests.admin", { contestId: c })).contestReports,
    [],
  );
  await voting(c);
  for(let i=0;i<13;i++){await vote(users[8],c,e);if(i<12)await vote(users[8],c,e,false);}
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  assert(
    (await call(owner, "contests.admin", { contestId: c })).awards.some(
      (a) => a.kind === "champion",
    ),
  );
});
test("historical podium corrections keep the original award year and refresh annual honors immediately", async () => {
  const c = await event({ minEntries: 1 }),
    champ = await submit(users[0], c),
    silver = await submit(users[1], c);
  await voting(c);
  await vote(users[8], c, champ);
  await vote(users[7], c, champ);
  await vote(users[6], c, silver);
  await ending(c);
  await pg.query("SELECT hyt_contest_tick()");
  await pg.query(
    "UPDATE hyt_contests SET announced_at=now()-interval '1 year' WHERE id=$1",
    [c],
  );
  await pg.query(
    "UPDATE hyt_contest_awards SET awarded_at=now()-interval '1 year' WHERE contest_id=$1",
    [c],
  );
  await pg.query("SELECT hyt_contest_achievements_refresh($1)", [c]);
  await call(owner, "contests.review", {
    contestId: c,
    kind: "entry",
    targetId: champ.id,
    decision: "remove",
    reason: "确认往届冠军作品违规",
  });
  const corrected = await call(users[1], "contests.profile");
  assert.equal(corrected.stats.champions, 1);
  assert.equal(corrected.annual.length, 1);
  assert.equal((await call(users[0], "contests.profile")).annual.length, 0);
  const award = corrected.awards.find((a) => a.kind === "champion");
  assert.equal(
    new Date(award.awarded_at).getFullYear(),
    new Date().getFullYear() - 1,
  );
});

test('v2: ordinary young voters and three quick distinct choices do not hold awards; vote responds with committed state',async()=>{
 const c=await event({minEntries:1});const e=await submit(users[0],c),e2=await submit(users[2],c),e3=await submit(users[3],c);await voting(c);
 await pg.query("UPDATE hyt_members SET created_at=now()-interval '36 hours' WHERE id=$1",[users[1].user.id]);
 try{
  const r=await vote(users[1],c,e);
  assert.equal(r.entry?.voted,true);assert.equal(r.votesUsed,1);await vote(users[1],c,e2);const third=await vote(users[1],c,e3);assert.equal(third.votesUsed,3);assert.equal((await vote(users[1],c,e3)).votesUsed,3);
  assert.equal((await pg.query('SELECT risk FROM hyt_contest_votes WHERE contest_id=$1',[c])).rows[0].risk,null);
  await ending(c);assert.equal((await pg.query('SELECT hyt_contest_tick() AS result')).rows[0].result.announced,1);
 }finally{await pg.query("UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",[users[1].user.id]);}
});
test('v2: theme moderation ignores legacy accidental contestId and never resettles or attributes the global audit to that event',async()=>{
 const c=await event({minEntries:1});await submit(users[0],c);await ending(c);await pg.query('SELECT hyt_contest_tick()');
 await call(owner,'contests.manage',{contestId:c,operation:'solicitation',enabled:true,reason:'开启主题征集'});
 const r=await call(users[1],'contests.suggest',{title:'春天的校园摄影',requestId:randomUUID()});const t=r.themes[0];
 await pg.query("UPDATE hyt_contests SET settled_at='2020-01-01T00:00:00Z' WHERE id=$1",[c]);
 await call(owner,'contests.review',{contestId:c,kind:'theme',targetId:t.id,decision:'approve',reason:'符合校园主题'});
 const result=(await pg.query('SELECT settled_at::text AS at FROM hyt_contests WHERE id=$1',[c])).rows[0];assert.match(result.at,/2020-01-01/);
 assert.equal((await pg.query("SELECT contest_id FROM hyt_contest_audit WHERE target_id=$1 ORDER BY created_at DESC LIMIT 1",[t.id])).rows[0].contest_id,null);
});
test('v2: retried admin save is idempotent and stale edits conflict',async()=>{
 const b={...config(),requestId:randomUUID()};await call(owner,'contests.save',b);await call(owner,'contests.save',b);
 const version=(await pg.query('SELECT version FROM hyt_contests WHERE id=$1',[b.contestId])).rows[0].version;assert.equal(version,1);
 await call(owner,'contests.save',{...b,requestId:randomUUID(),expectedVersion:1,title:'更新过的主题'});
 await assert.rejects(call(owner,'contests.save',{...b,requestId:randomUUID(),expectedVersion:1,title:'过期的另一端编辑'}),{code:'contest_conflict'});
});

test('v2: concurrent revision edits reject stale data and withdrawal retries preserve one audit',async()=>{
 const c=await event();const e=await submit(users[0],c);const revised=await submit(users[0],c,{entryId:e.id,expectedVersion:e.version,title:'已保存的新版本'});assert.equal(revised.version,e.version+1);
 await assert.rejects(submit(users[0],c,{entryId:e.id,expectedVersion:e.version,title:'另一端的旧编辑'}),{code:'contest_conflict'});
 await call(users[0],'contests.withdraw',{contestId:c,entryId:e.id});await call(users[0],'contests.withdraw',{contestId:c,entryId:e.id});
 assert.equal((await pg.query("SELECT count(*)::int AS n FROM hyt_contest_audit WHERE target_id=$1 AND action='withdraw'",[e.id])).rows[0].n,1);
});
test('v2: pre-upgrade submission receipts remain retryable after adding optional version metadata',async()=>{
 const c=await event();const requestId=randomUUID();const e=await submit(users[0],c,{requestId});
 await pg.query("UPDATE hyt_contest_requests SET payload=payload-'expectedVersion' WHERE member_id=$1 AND request_id=$2",[users[0].user.id,requestId]);
 const retried=await submit(users[0],c,{requestId,expectedVersion:9});assert.equal(retried.id,e.id);assert.equal(retried.version,1);
});
test('v2: zero-hour eligibility explicitly allows accounts registered during voting',async()=>{
 const c=await event();const e=await submit(users[0],c);await voting(c);
 await pg.query('UPDATE hyt_members SET created_at=now() WHERE id=$1',[users[4].user.id]);
 try{assert.equal((await vote(users[4],c,e)).entry.voted,true);}finally{await pg.query("UPDATE hyt_members SET created_at=now()-interval '30 days' WHERE id=$1",[users[4].user.id]);}
});
test('v2: atomic draft publication reserves its settlement task first; global themes never schedule an event',async()=>{
 const calls=[],scheduled=[];const scheduledApi=createCommunity({contestsEnabled:true,db:async(a,b,t)=>{calls.push(a);return (await pg.query('SELECT hyt_community($1,$2::jsonb,$3) AS result',[a,JSON.stringify(b),t])).rows[0].result;},scheduler:{ensure:async c=>scheduled.push(c)}});
 const b=config();await call(owner,'contests.save',b);
 const r=await scheduledApi.execute('contests.save',{...b,publish:true,requestId:randomUUID()},owner.sessionToken,'fixture');assert.equal(r.contest.state,'submitting');assert.equal(scheduled.length,1);
 await scheduledApi.execute('contests.manage',{contestId:null,operation:'solicitation',enabled:true,reason:'开启全局主题征集'},owner.sessionToken,'fixture');
 const proposal=await call(users[1],'contests.suggest',{title:'春季校园故事征集',requestId:randomUUID()});calls.length=0;
 await scheduledApi.execute('contests.review',{contestId:b.contestId,kind:'theme',targetId:proposal.themes[0].id,decision:'approve',reason:'采纳校园主题'},owner.sessionToken,'fixture');assert(!calls.includes('contests.schedule'));assert.equal(scheduled.length,1);
});
test('v2: legacy clients omitting new risk metadata preserve the published event setting',async()=>{
 const b={...config(),reviewRisk:false,publish:true};await call(owner,'contests.save',b);
 const legacy={...b,publish:false,submissionEnds:iso(5.5),votingStarts:iso(5.5),votingEnds:iso(6.5),awardAt:iso(7.5)};delete legacy.reviewRisk;
 const r=await call(owner,'contests.save',legacy);assert.equal(r.contest.reviewRisk,false);
});
test('v2: moderation replies carry the committed entry and refreshed metrics for proactive review',async()=>{
 const c=await event();const e=await submit(users[0],c);
 const removed=await call(owner,'contests.review',{contestId:c,kind:'entry',targetId:e.id,decision:'remove',reason:'主动核对作品授权',requestId:randomUUID()});assert.equal(removed.entry.status,'removed');assert.equal((await call(owner,'contests.admin',{contestId:c})).metrics.validEntries,0);
 const restored=await call(owner,'contests.review',{contestId:c,kind:'entry',targetId:e.id,decision:'approve',reason:'已核实作品为原创',requestId:randomUUID()});assert.equal(restored.entry.status,'approved');assert.equal((await call(owner,'contests.admin',{contestId:c})).metrics.validEntries,1);
});

test('v3 recycle bin is developer-only, idempotent and reversible without orphaning history',async()=>{
 const c=await event();
 await call(owner,'contests.manage',{contestId:c,operation:'cancel',reason:'清理测试比赛'});
 await assert.rejects(call(users[0],'contests.manage',{contestId:c,operation:'remove',reason:'越权删除'}),{code:'forbidden'});
 const req={contestId:c,operation:'remove',reason:'移除空测试赛事',requestId:randomUUID()};
 const r=await call(owner,'contests.manage',req);
 assert.equal(r.contest.visibility,'deleted');
 assert.equal((await call(users[0],'contests.list')).contests.length,0);
 await assert.rejects(call(users[0],'contests.get',{contestId:c}),{code:'not_found'});
 assert.equal((await call(owner,'contests.list',{scope:'trash'})).contests[0].id,c);
 await call(owner,'contests.manage',req);
 await call(owner,'contests.manage',{...req,requestId:randomUUID()});
 assert.equal((await pg.query("SELECT count(*)::int AS n FROM hyt_contest_audit WHERE action='remove'")).rows[0].n,1);
 assert.deepEqual((await pg.query("SELECT snapshot->'associations' AS counts FROM hyt_contest_audit WHERE action='remove'")).rows[0].counts,{entries:0,votes:0,awards:0});
 await call(owner,'contests.manage',{contestId:c,operation:'restore',reason:'恢复误删赛事',requestId:randomUUID()});
 assert.equal((await call(users[0],'contests.get',{contestId:c})).contest.visibility,'visible');
 assert.equal((await call(owner,'contests.list',{scope:'trash'})).contests.length,0);
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_contests')).rows[0].n,1);
});

test('v3 events with entries, votes or awards are hidden and restored with the same award identities',async()=>{
 const c=await event({minEntries:1}); const e=await submit(users[0],c);
 await voting(c);await vote(users[1],c,e);await ending(c);
 await call(owner,'contests.manage',{contestId:c,operation:'announce',reason:'公布真实结果'});
 const before=(await call(users[0],'contests.profile')).awards;
 assert(before.some(a=>a.kind==='champion'));
 const champ=before.find(a=>a.kind==='champion');
 await call(users[0],'contests.wear',{awardId:champ.id});
 const r=await call(owner,'contests.manage',{contestId:c,operation:'remove',reason:'下架测试活动',requestId:randomUUID()});
 assert.equal(r.contest.visibility,'hidden');
 assert.equal((await call(users[0],'contests.profile')).stats.champions,0);
 assert.equal((await call(users[0],'contests.profile')).worn,null);
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_contest_awards WHERE revoked_at IS NULL')).rows[0].n,before.length);
 await call(owner,'contests.manage',{contestId:c,operation:'restore',reason:'恢复活动展示',requestId:randomUUID()});
 const after=await call(users[0],'contests.profile');
 assert.deepEqual(after.awards.map(a=>a.id).sort(),before.map(a=>a.id).sort());
 assert.equal(after.stats.champions,1);assert.equal(after.worn,champ.id);
});

test('v3 preview is read-only and cannot expose drafts or moderation data to ordinary accounts',async()=>{
 const cfg=config();await call(owner,'contests.save',cfg);
 await assert.rejects(call(users[0],'contests.get',{contestId:cfg.contestId,preview:true}),{code:'forbidden'});
 assert.equal((await call(owner,'contests.get',{contestId:cfg.contestId,preview:true})).contest.state,'draft');
 await assert.rejects(call(owner,'contests.submit',{contestId:cfg.contestId,title:'预览作品',body:'预览不写入',images:[],agreed:true,preview:true,requestId:randomUUID()}),{code:'contest_preview_readonly'});
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_contest_entries')).rows[0].n,0);
 assert.equal((await call(owner,'contests.list',{scope:'public'})).contests.length,0);
 assert.equal((await call(owner,'contests.list',{scope:'manage'})).contests.length,1);
});

test('v3 deletion confirmation rejects raced association counts and hidden events never auto-settle',async()=>{
 const c=await event({minEntries:1});
 await submit(users[0],c);
 await assert.rejects(call(owner,'contests.manage',{contestId:c,operation:'remove',reason:'过期清理确认',expectedCounts:{entries:0,votes:0,awards:0},requestId:randomUUID()}),{code:'contest_changed'});
 assert.equal((await call(users[0],'contests.get',{contestId:c})).contest.visibility,'visible');
 await call(owner,'contests.manage',{contestId:c,operation:'remove',reason:'核对后下架',expectedCounts:{entries:1,votes:0,awards:0},requestId:randomUUID()});
 await ending(c);await pg.query('SELECT hyt_contest_tick()');
 assert.equal((await pg.query('SELECT announced_at FROM hyt_contests WHERE id=$1',[c])).rows[0].announced_at,null);
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_contest_awards')).rows[0].n,0);
 await call(owner,'contests.manage',{contestId:c,operation:'restore',reason:'重新公开比赛',requestId:randomUUID()});
 await pg.query('SELECT hyt_contest_tick()');await pg.query('SELECT hyt_contest_tick()');
 assert.equal((await pg.query('SELECT count(*)::int AS n FROM hyt_contest_awards')).rows[0].n,1);
});

test('v3 independent covers enforce ownership, survive cleanup and support authorized renewal',async()=>{
 const rgba={width:4,height:4,data:Buffer.alloc(4*4*4,210)},data=Buffer.from(jpeg.encode(rgba,80).data).toString('base64');
 const image=(await call(owner,'media.upload',{data,requestId:randomUUID()})).image;
 const c=await event({coverImageId:image.id,coverPosition:72,startsAt:iso(1),submissionEnds:iso(2),votingStarts:iso(2),votingEnds:iso(3),awardAt:iso(4)});
 const got=(await call(users[0],'contests.get',{contestId:c})).contest;
 assert.equal(got.cover.id,image.id);assert.equal(got.coverPosition,72);
 assert.equal((await call(users[0],'contests.image',{contestId:c,cover:true,imageId:image.id})).image.id,image.id);
 await call(owner,'media.discard',{imageId:image.id});
 await pg.query("UPDATE hyt_media SET created_at=now()-interval '8 days' WHERE id=$1",[image.id]);
 assert(!(await pg.query("SELECT hyt_community('media.cleanup','{}','') AS r")).rows[0].r.images.some(i=>i.id===image.id));
 await assert.rejects(call(users[0],'contests.image',{contestId:c,cover:true,imageId:randomUUID()}),{code:'not_found'});
 const foreign=(await call(users[0],'media.upload',{data,requestId:randomUUID()})).image;
 await assert.rejects(call(owner,'contests.save',{...config(c),coverImageId:foreign.id}),{code:'image_unavailable'});
 await call(owner,'contests.save',config(c));
 assert.equal((await call(users[0],'contests.get',{contestId:c})).contest.cover.id,image.id);
});

test('v3 developer participates normally, preview masks moderation state and medals use the existing worn slot',async()=>{
 const c=await event({minEntries:1});const own=await submit(owner,c),other=await submit(users[0],c);
 await voting(c);await assert.rejects(vote(owner,c,own),{code:'contest_self_vote'});
 await vote(owner,c,other);await vote(users[0],c,own);
 const rows=(await call(owner,'contests.entries',{contestId:c,seed:randomUUID(),preview:true})).entries;
 assert(rows.every(e=>e.votes===null));
 await ending(c);await call(owner,'contests.manage',{contestId:c,operation:'announce',reason:'公布同票获奖'});
 const collection=await call(owner,'contests.profile',{kind:'champion'});
 assert.equal(collection.stats.medalCounts.champion,1);assert.equal(collection.awards.length,1);
 await call(owner,'contests.wear',{awardId:collection.awards[0].id});
 const identity=(await call(owner,'me')).user.badges;
 assert.equal(identity.official.code,'developer');assert.equal(identity.worn.code,'contest_champion');
 await call(owner,'honors.wear',{honor:null,showcase:['arrival']});
 assert.equal((await call(owner,'me')).user.badges.worn.code,'contest_champion');
 await call(owner,'contests.wear',{awardId:null});
 assert.equal((await call(owner,'me')).user.badges.worn,null);
});
