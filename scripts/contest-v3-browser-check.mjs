import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { chromium } from "playwright";
const { createCommunity } = await import(
  process.env.CONTEST_CORE_MODULE || "../cloudbase/functions/community/core.mjs"
);

const output =
  process.env.CONTEST_QA_DIR || "/tmp/handan-community-contests-v3-qa";
await mkdir(output, { recursive: true });
const db = new PGlite();
await db.exec(
  await readFile(
    process.env.CONTEST_SCHEMA_PATH || "cloudbase/community-schema.sql",
    "utf8",
  ),
);
const media = new Map();
let origin = "",
  sign = 0;
const api = createCommunity({
  storage: {
    put: async (key, bytes) => media.set(key, bytes),
    url: async (key) => origin + "/fixtures/" + key + "?signed=" + ++sign,
    remove: async (key) => media.delete(key),
  },
  contestsEnabled: true,
  registrationEnabled: true,
  db: async (a, b, t) =>
    (
      await db.query("SELECT hyt_community($1,$2::jsonb,$3) AS result", [
        a,
        JSON.stringify(b),
        t,
      ])
    ).rows[0].result,
});
const reg = (name) =>
  api.execute(
    "register",
    { username: name, password: "browser-fixture-password", agreed: true },
    "",
    name,
  );
const owner = await reg("contest-admin"),
  author = await reg("contest-author"),
  voter = await reg("contest-voter");
await db.query("UPDATE hyt_members SET developer_since=now() WHERE id=$1", [
  owner.user.id,
]);
await db.exec("UPDATE hyt_members SET created_at=now()-interval '30 days'");
const call = (u, a, b) =>
  api.execute(a, b, u.sessionToken, "browser-fixture-campus");
const stamp = (h) => new Date(Date.now() + h * 3600000).toISOString();
const id = randomUUID();
await call(owner, "contests.save", {
  contestId: id,
  title: "把校园写成一首诗",
  type: "文字赛",
  edition: "第一届",
  description:
    "从早八路上的一束光，到晚自习窗外的风。用一段文字，收藏你的邯院日常。",
  rules: "原创文字投稿，尊重他人隐私。同票并列，下一名次连续排列。",
  startsAt: stamp(-1),
  submissionEnds: stamp(5),
  votingStarts: stamp(5),
  votingEnds: stamp(6),
  awardAt: stamp(7),
  formats: ["text"],
  maxEntries: 1,
  votesPerUser: 3,
  minEntries: 1,
  minAccountHours: 0,
  excellence: 3,
  autoPublish: true,
});
await call(owner, "contests.manage", {
  contestId: id,
  operation: "publish",
  reason: "发布已核验的测试赛事",
});
await call(author, "contests.submit", {
  contestId: id,
  title: "早八路上的光",
  body: "我把没睡醒的清晨\n交给教学楼的一扇窗。\n阳光落在课本上，\n今天也有了温柔的开场。",
  images: [],
  agreed: true,
  requestId: randomUUID(),
});
await call(author,'posts.create',{title:'教学楼窗外的晚霞',body:'晚课前抬头看了一眼，今天的天空很漂亮。',category:'daily',anonymous:false,images:[],requestId:randomUUID()});
await call(voter,'posts.create',{title:'图书馆的一个下午',body:'找到一个安静的位置，读完了想读的那几页。',category:'daily',anonymous:false,images:[],requestId:randomUUID()});
// Returning fixture accounts have already seen registration/post/time achievements.
// Acknowledge through the real API so consecutive screenshots do not restart a notice queue.
for(const u of [owner,author,voter]){const r=await call(u,'honors.hall',{timeAwards:true});if(r.unlocks?.length)await call(u,'honors.ack',{codes:r.unlocks});}
const root = path.resolve(process.env.CONTEST_DIST || "dist");
const server = createServer(async (req, res) => {
  try {
    const name = new URL(req.url, "http://localhost").pathname;
    if (name.startsWith("/fixtures/")) {
      const bytes = media.get(name.slice("/fixtures/".length));
      if (!bytes) throw Error("missing_fixture");
      res.setHeader("Content-Type", "image/jpeg");
      res.end(bytes);
      return;
    }
    const file = path.resolve(
      root,
      "." + (name === "/" ? "/index.html" : name),
    );
    if (!file.startsWith(root + "/")) throw Error();
    res.setHeader(
      "Content-Type",
      {
        ".js": "text/javascript",
        ".css": "text/css",
        ".html": "text/html",
        ".webp": "image/webp",
        ".png": "image/png",
      }[path.extname(file)] || "application/octet-stream",
    );
    res.end(await readFile(file));
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
origin = `http://127.0.0.1:${server.address().port}`;

const baseline=process.env.CONTEST_BASELINE==='1';
const historical=randomUUID(),draft=randomUUID(),empty=randomUUID();
for(const [cid,title] of [[historical,'邯院的第一缕光'],[draft,'毕业季 · 留给校园的信'],[empty,'信息']]){
 await db.query(`INSERT INTO hyt_contests(id,title,type,edition,description,rules,starts_at,submission_ends,voting_starts,voting_ends,award_at,formats,max_entries,votes_per_user,min_entries,min_account_hours,excellence,auto_publish) SELECT $1,$2,type,edition,description,rules,starts_at,submission_ends,voting_starts,voting_ends,award_at,formats,max_entries,votes_per_user,min_entries,min_account_hours,excellence,false FROM hyt_contests WHERE id=$3`,[cid,title,id]);
}
await call(owner,'contests.manage',{contestId:historical,operation:'publish',reason:'验证历史赛事'});
const champion=(await call(owner,'contests.submit',{contestId:historical,title:'阳光照进教学楼',body:'属于邯院的一个清晨。',images:[],agreed:true,requestId:randomUUID()})).entry;
await db.query("UPDATE hyt_contests SET submission_ends=now()-interval '20 minutes',voting_starts=now()-interval '10 minutes' WHERE id=$1",[historical]);
await call(author,'contests.vote',{contestId:historical,entryId:champion.id,enabled:true});
await db.query("UPDATE hyt_contests SET starts_at=now()-interval '5 hours',submission_ends=now()-interval '4 hours',voting_starts=now()-interval '3 hours',voting_ends=now()-interval '2 hours',award_at=now()-interval '1 hour' WHERE id=$1",[historical]);
await call(owner,'contests.manage',{contestId:historical,operation:'announce',reason:'公布验收结果'});
await call(owner,'contests.manage',{contestId:empty,operation:'publish',reason:'验证测试赛事'});
await call(owner,'contests.manage',{contestId:empty,operation:'cancel',reason:'取消无效赛事'});
let browser;const checks=[];
try{
 browser=await chromium.launch({args:['--no-sandbox'],executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||undefined});
 const context=await browser.newContext({viewport:{width:Number(process.env.CONTEST_QA_WIDTH)||390,height:Number(process.env.CONTEST_QA_HEIGHT)||844},serviceWorkers:'block'});
 let activeMember = owner;
 const actions = [];
 let coverRetry = false, coverReplyDropped = false, dropDeleteReply = false;
 await context.exposeBinding("__contestNative", async (_, request) => {
   const { action, body } = request;
   actions.push({ action, body });
   const result = action === "config" ? api.config() : await call(activeMember, action, body);
   delete result.sessionToken;
   if (coverRetry && action === "media.upload" && !coverReplyDropped) {
     coverReplyDropped = true;
     throw Error("network_unavailable");
   }
   if (dropDeleteReply && action === "contests.manage" && body.operation === "remove") {
     dropDeleteReply = false;
     throw Error("network_unavailable");
   }
   return result;
 });
 await context.addInitScript(()=>{
 const methods={Treehole:['request','cachedHall','journalRead','journalWrite'],Preferences:['get','set','remove'],App:['addListener','removeListener','exitApp'],StatusBar:['setStyle','setBackgroundColor'],LocalNotifications:['getPending','cancel','checkPermissions']};
 window.androidBridge={};window.Capacitor={PluginHeaders:Object.entries(methods).map(([name,ms])=>({name,methods:ms.map(name=>({name,rtype:'promise'}))})),nativePromise:async(plugin,method,args)=>{if(plugin==='Treehole'){if(method==='cachedHall'){const r=await window.__contestNative({action:'honors.hall'});return {signedIn:true,hall:r.hall,cachedAt:Date.now()};}if(method==='journalRead')return {};if(method==='journalWrite')return {};return window.__contestNative(args);}if(plugin==='Preferences'){if(method==='get')return {value:localStorage.getItem(args.key)};if(method==='set')localStorage.setItem(args.key,args.value);if(method==='remove')localStorage.removeItem(args.key)}if(plugin==='LocalNotifications'&&method==='getPending')return {notifications:[]};return {};}};
 });
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));page.setDefaultTimeout(15000);
 const shot=async(name)=>{await page.waitForTimeout(150);await page.screenshot({path:path.join(output,name+'.png'),fullPage:true,animations:'disabled'});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,name+' overflow')};
 const start=async()=>{await page.goto(origin+'/?view='+randomUUID()+'#/community');await page.locator('.contest-entry').waitFor();await page.locator('.unlock-toast').waitFor({state:'hidden',timeout:10000});};
 await start();await shot('01-community-active');const entryBox=await page.locator('.contest-entry').boundingBox();if(!baseline)assert(entryBox.height>=72&&entryBox.height<=88,'activity entry height '+entryBox.height);checks.push('active entry '+entryBox.height+'px');
 await page.locator('.contest-entry').click();await page.getByRole('button',{name:'我要参赛',exact:true}).waitFor();await shot('05-current-wall');
 await page.getByRole('button',{name:/历届赛事/}).click();await page.getByRole('button',{name:/邯院的第一缕光/}).waitFor();await shot('06-archive');
 await start();await page.locator('.th-self').click();await page.locator('[data-screen=account]').waitFor();await shot('08-my-community');
 await page.locator('.self-case').getByRole('button',{name:'查看全部荣誉殿堂藏品'}).click();await page.locator('[data-screen=honors]').waitFor();await shot('09-honor-hall');
 if(baseline){await page.locator('.contest-honors').waitFor();await shot('10-medal-detail');}
 else {await page.getByRole('button',{name:'赛事奖牌',exact:true}).click();await page.getByRole('button',{name:/冠军/}).first().click();await page.getByRole('button',{name:/邯院的第一缕光/}).first().click();await page.locator('dialog[open]').waitFor();await shot('10-medal-detail');await page.getByRole('button',{name:'佩戴为代表荣誉',exact:true}).click();await page.getByRole('button',{name:'取下代表荣誉',exact:true}).waitFor();await page.getByRole('button',{name:'查看比赛与作品',exact:true}).click();await page.getByRole('heading',{name:'阳光照进教学楼',exact:true}).waitFor();checks.push('medal opens original work and wearing uses the existing identity slot');}
 await start();await page.locator('.contest-entry').click();await page.getByRole('button',{name:'赛事管理',exact:true}).click();
 await page.getByRole('button',{name:'创建赛事',exact:true}).click();await shot('04-create');
 if(!baseline){await page.getByLabel('赛事名称',{exact:true}).fill('封面裁切与重试验收');await page.getByLabel('主题与介绍',{exact:true}).fill('独立上传封面，保留裁切位置。');await page.locator('.ct-cover-picker input[type=file]').setInputFiles('public/campus/east-plan.jpg');await page.getByAltText('赛事封面裁切预览').waitFor();await page.getByLabel('封面裁切位置',{exact:true}).fill('25');await shot('04-cover-crop');coverRetry=true;await page.getByRole('button',{name:'先保存草稿',exact:true}).click();await page.locator('.ct-error').waitFor();assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_media')).rows[0].n,1);await page.getByRole('button',{name:'先保存草稿',exact:true}).click();await page.getByRole('button',{name:'预览普通用户视角',exact:true}).waitFor();const coverEvent=(await db.query("SELECT cover_image_id,cover_position,cover_post_id FROM hyt_contests WHERE title='封面裁切与重试验收'")).rows[0];assert(coverEvent.cover_image_id);assert.equal(coverEvent.cover_position,25);assert.equal(coverEvent.cover_post_id,null);assert.equal((await db.query('SELECT count(*)::int AS n FROM hyt_media')).rows[0].n,1);checks.push('cover crop and committed-upload lost reply retry preserve exactly one media object');}

 await start();await page.locator('.contest-entry').click();await page.getByRole('button',{name:'赛事管理',exact:true}).click();
 await page.getByRole('button',{name:/毕业季 · 留给校园的信/}).click();await page.getByRole('button',{name:'发布赛事',exact:true}).waitFor();
 if(!baseline){const mark=actions.length;await page.getByRole('button',{name:'预览普通用户视角',exact:true}).click();await page.getByText('普通用户视角 · 只读预览',{exact:true}).waitFor();await shot('03-developer-preview');assert(!await page.getByRole('button',{name:'赛事管理',exact:true}).count());assert(!actions.slice(mark).some(x=>['contests.submit','contests.vote','contests.manage'].includes(x.action)));await page.getByRole('button',{name:'结束预览',exact:true}).click();await page.getByRole('button',{name:'发布赛事',exact:true}).waitFor();}
 else await shot('03-developer-preview');
 await start();await page.locator('.contest-entry').click();await page.getByRole('button',{name:'赛事管理',exact:true}).click();await page.getByRole('button',{name:/信息/}).click();
 if (!baseline) {
   const deleteButton = page.getByRole("button", { name: "删除赛事", exact: true });
   await deleteButton.waitFor();
   const actionBox = await deleteButton.boundingBox();
   assert(actionBox.y + actionBox.height <= page.viewportSize().height, "Delete is visible without scrolling");
   await deleteButton.click();
   const dialog = page.getByRole("dialog");
   const confirmDelete = dialog.getByRole("button", { name: "移入回收站", exact: true });
   await dialog.waitFor();
   await shot("07-delete-confirm");
   assert.equal(await dialog.getByLabel(/处理原因/).inputValue(), "");
   await db.query("UPDATE hyt_contests SET version=version+1 WHERE id=$1", [empty]);
   await confirmDelete.click();
   await dialog.getByRole("status").filter({ hasText: "赛事有新变化" }).waitFor();
   assert.equal((await db.query("SELECT visibility FROM hyt_contests WHERE id=$1", [empty])).rows[0].visibility, "visible");
   dropDeleteReply = true;
   await confirmDelete.click();
   await dialog.getByRole("alert").filter({ hasText: "连接失败" }).waitFor();
   assert.equal((await db.query("SELECT visibility FROM hyt_contests WHERE id=$1", [empty])).rows[0].visibility, "deleted");
   await confirmDelete.click();
   await page.getByRole("status").filter({ hasText: "赛事已移入回收站。" }).waitFor();
   const removals = actions.filter(({action, body}) => action === "contests.manage" && body.operation === "remove");
   assert.equal(removals.length, 3);
   assert.notEqual(removals[0].body.requestId, removals[1].body.requestId);
   assert.deepEqual(removals[1].body, removals[2].body);
   const audit = await db.query("SELECT count(*)::int AS total FROM hyt_contest_audit WHERE contest_id=$1 AND action='remove'", [empty]);
   assert.equal(audit.rows[0].total, 1);
   await page.getByRole("button", { name: "回收站", exact: true }).click();
   await page.getByRole("button", { name: /信息/ }).waitFor();
   await shot("07-recycle-bin");
   await page.getByRole("button", { name: /信息/ }).click();
   await page.getByRole("button", { name: "恢复赛事", exact: true }).click();
   await page.getByRole("button", { name: "确认恢复", exact: true }).click();
   await page.getByRole("status").filter({ hasText: "赛事已恢复。" }).waitFor();
   await page.getByText("回收站是空的", { exact: true }).waitFor();
   const restored = await db.query("SELECT id,visibility,cancelled FROM hyt_contests WHERE id=$1", [empty]);
   assert.deepEqual(restored.rows[0], { id: empty, visibility: "visible", cancelled: true });
   checks.push("cancelled contest: visible delete, blank reason, refresh stale version, lost-receipt retry, recycle bin and restore");
 } else {
   await page.getByText("更多赛事操作", { exact: true }).click();
   await shot("07-delete-confirm");
   await shot("07-recycle-bin");
 }
 if (!baseline) {
   await db.query("UPDATE hyt_contests SET max_entries=2 WHERE id=$1", [id]);
   activeMember = author;
   await start();
   await page.locator(".contest-entry").click();
   const another = page.getByRole("button", { name: "继续投稿", exact: true });
   const own = page.locator("#contest-own-works");
   const back = page.getByRole("button", { name: "返回上一层", exact: true });
   await another.waitFor();
   await page.getByRole("region", { name: "赛事日程" }).getByText("投稿截止", { exact: true }).waitFor();
   await shot("11-additional-submission");
   await another.click();
   await page.getByLabel("作品名称", { exact: true }).fill("下课后的操场");
   await page.getByLabel("作品内容", { exact: true }).fill("走过操场时，远处还在下着小雨。");
   await page.getByLabel("我已阅读规则，作品符合投稿要求").check();
   await page.getByRole("button", { name: "预览作品", exact: true }).click();
   await page.getByRole("button", { name: "确认参赛", exact: true }).click();
   await page.getByRole("heading", { name: "下课后的操场", exact: true }).waitFor();
   await back.click();
   await own.getByText("2 / 2 件", { exact: true }).waitFor();
   assert.equal(await another.count(), 0, "submission action hidden when slots are full");
   await page.getByRole("button", { name: "查看我的作品", exact: true }).click();
   await own.getByRole("button", { name: "早八路上的光", exact: true }).click();
   await page.getByRole("button", { name: "撤回作品", exact: true }).click();
   await page.getByRole("dialog").getByRole("button", { name: "撤回作品", exact: true }).click();
   await another.waitFor();
   await own.getByText("1 / 2 件", { exact: true }).waitFor();
   const rows = await db.query(
     "SELECT title,status FROM hyt_contest_entries WHERE contest_id=$1 AND member_id=$2 ORDER BY created_at",
     [id, author.user.id],
   );
   assert.deepEqual(rows.rows.map(({ title, status }) => [title, status]), [
     ["早八路上的光", "withdrawn"],
     ["下课后的操场", "approved"],
   ]);
   checks.push("additional entry submission, full quota and withdrawal use real SQL");
 }
 await db.query('UPDATE hyt_contests SET published=false WHERE id=$1',[id]);activeMember=voter;await start();await shot('02-community-empty');if(!baseline){const emptyBox=await page.locator('.contest-entry').boundingBox();assert(emptyBox.height<=56,'empty entry '+emptyBox.height);assert.equal(await page.locator('.th-page-account .contest-honors').count(),0);activeMember=owner;await start();await page.getByRole('button',{name:'我的',exact:true}).click();await page.locator('.collection-entry').getByRole('button',{name:'查看全部荣誉殿堂藏品'}).click();await page.getByRole('button',{name:'赛事奖牌',exact:true}).click();await page.locator('.medal-shelf').waitFor();await shot('09-global-honor-medals');await page.getByRole('button',{name:'成就收藏',exact:true}).click();await page.locator('[data-code=arrival]').click();await page.getByRole('button',{name:/展示到社区主页/}).click();await page.getByRole('button',{name:/取下/}).waitFor();assert.equal((await call(owner,'me')).user.badges.worn.code,'contest_champion');checks.push('global and community Honor Hall share the medal collection; achievement pinning preserves worn contest identity');}

 assert.equal(errors.length,0,JSON.stringify(errors));await writeFile(path.join(output,'checks.json'),JSON.stringify({baseline,checks,errors},null,2));
 console.log((baseline?'Baseline':'V3')+' ten-screen visual and real SQL workflow complete');
 await context.close();
}finally{await browser?.close();await new Promise(r=>server.close(r));await db.close();}
