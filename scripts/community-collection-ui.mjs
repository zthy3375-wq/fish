import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { registerTestAccount } from './community-test-account.mjs';

export async function checkTitleGrant({client, db, api}) {
  const owner = await client(360);
  const recipient = await client(390);
  try {
    await registerTestAccount(owner.page, 'titleowner', '称号测试开发者');
    await registerTestAccount(recipient.page, 'titlereader', '收取称号的同学');
    const ownerId = (await api.execute('me', {}, owner.state.token)).user.id;
    const memberId = (await api.execute('me', {}, recipient.state.token)).user.id;
    await db.query("UPDATE hyt_members SET role='moderator',developer_since=now() WHERE id=$1", [ownerId]);
    const page = owner.page;
    await page.addInitScript(() => Object.defineProperty(crypto, 'randomUUID', {value:undefined, configurable:true}));
    await page.reload();
    await page.locator('.th-nav .th-self:not([disabled])').click();
    const button = name => page.getByRole('button', {name, exact:true});
    await button('身份与荣誉管理').click();
    await button('授予与称号').click();
    const search = async value => {
      await page.getByLabel('查找成员').fill(value);
      await button('搜索').click();
      await page.getByRole('button', {name:/^收取称号的同学 · /}).click();
      await page.locator('input[maxlength="16"]:enabled').waitFor();
    };
    await search('收取称号的同学');
    const input = page.getByLabel(/专属称号/);
    const readTitle = async () => (await api.execute('collection.profile', {}, recipient.state.token)).collection.customTitle;
    async function save(title) {
      await input.fill(title);
      await button('保存称号').click();
      const confirm = button('确认执行');
      await confirm.waitFor();
      await page.waitForFunction(() => {
        const region=document.querySelector('[aria-label="确认管理操作"]');
        const box=region?.getBoundingClientRect();
        return box && box.top>=0 && box.bottom<=window.innerHeight;
      }, undefined, {timeout:3500});
      await confirm.click();
      await confirm.waitFor({state:'detached'});
      assert.equal(await readTitle(), title || null);
    }
    await save('校园手记');
    await recipient.page.reload();
    await recipient.page.locator('.th-nav .th-self:not([disabled])').click();
    await recipient.page.getByRole('button',{name:'查看全部荣誉殿堂藏品',exact:true}).click();
    await recipient.page.getByText('我的专属称号 · 校园手记', {exact:true}).waitFor();
    await search('titlereader');
    assert.equal(await input.inputValue(),'校园手记');
    await save('新称号');
    await search(memberId);
    assert.equal(await input.inputValue(),'新称号');
    await save('');
    await assert.rejects(api.execute('collection.change', {operation:'title', memberId, title:'越权测试',
      reason:'本地回归',requestId:randomUUID()}, recipient.state.token), {code:'forbidden'});
    console.log('PASS Android title assignment, edit and clear via nickname, login and member ID on a WebView without randomUUID');
  } finally {
    await owner.context.close();
    await recipient.context.close();
  }
}

export async function checkCollection({client,db,api,output}) {
  await mkdir(output,{recursive:true});
  const year = Number(new Intl.DateTimeFormat("en", {year:"numeric",timeZone:"Asia/Shanghai"}).format(new Date()));
  const annualCode = "warmth-of-year-" + year;
  const owner = await client(390);
  const reader = await client(390);
  const button = (page, name) => page.getByRole('button',{name,exact:true});
  const back = page => button(page,'返回社区').click();
  const shot = (page, filename) => page.screenshot({path:path.join(output,filename),animations:'disabled'});
  const call = (state, action, data = {}) => api.execute(action,data,state.token,'collection-ui');
  const change = (data) => call(owner.state,'collection.change',{requestId:randomUUID(),reason:'本地验证',...data});

  try {
    await registerTestAccount(owner.page,'honorowner','荣誉测试管理员');
    await registerTestAccount(reader.page,'honorreader','校园档案测试同学');
    const dev = (await call(owner.state,'me')).user.id;
    const collector = (await call(reader.state,'me')).user.id;
    await db.query("UPDATE hyt_members SET role='moderator',developer_since=now(),created_at=now()-interval '2 years' WHERE id=$1",[dev]);
    await db.query("UPDATE hyt_members SET created_at=now()-interval '2 years'+interval '3 days' WHERE id=$1",[collector]);
    await change({operation:'save',code:annualCode,name:'年度最温暖的人',category:'limited',rarity:'epic',
      year,capacity:1,criteria:'依据真实校园互助记录审核',story:'记录一整年的校园互助'});
    const {honorDefinitions} = await call(owner.state,'collection.admin');
    for (const [code,story] of [
      ['handan-light','把新同学常问的问题整理成校园地图。每次有人补充信息，都会核对后更新。'],
      [annualCode,'陪新同学熟悉图书馆、公交站和教学楼，把整理出的路线留给了下一届。'],
    ]) {
      const definition = honorDefinitions.find(h=>h.code===code);
      assert(definition,code);
      await change({operation:'grant',definitionId:definition.id,memberId:collector,evidence:'本地验证用审核记录',story});
      if (code===annualCode) {
        await assert.rejects(change({operation:'grant',definitionId:definition.id,memberId:dev,evidence:'第二次申请验证',story}),{code:'honor_capacity'});
        await change({operation:'archive',definitionId:definition.id});
      }
    }
    await change({operation:'title',memberId:collector,title:'校园手记'});
    await db.query("INSERT INTO hyt_honors(member_id,kind) VALUES($1,'seed')",[collector]);
    await reader.page.reload();
    const source = reader.page;
    await source.locator('.th-nav .th-self:not([disabled])').waitFor();
    await source.waitForFunction(() => !document.querySelector('.unlock-toast'), undefined, {timeout:15000});
    assert.equal(await button(source,'荣誉殿堂').count(),0);
    await source.locator('.th-nav .th-self:not([disabled])').click();
    await button(source,'荣誉档案').click();
    await source.locator('.hc-archive').getByText('邯院之光',{exact:true}).waitFor();
    for (const width of [360,390,430]) {
      await source.setViewportSize({width,height:844});
      assert(await source.locator('.hc').evaluate(el=>el.scrollWidth<=el.clientWidth+1));
      await shot(source,`archive-${width}.png`);
    }
    await source.setViewportSize({width:390,height:844});
    await source.getByRole('button',{name:/校园档案测试同学.*邯院之光/}).click();
    await source.getByRole('dialog').getByText(/每次有人补充信息/).waitFor();
    await button(source,'打开荣誉档案').click();
    await source.getByRole('heading',{name:'我的荣誉收藏'}).waitFor();
    const firstUnlock=source.getByRole('dialog');
    await firstUnlock.getByText(/新荣誉已获得|新成就已解锁/).waitFor();
    await shot(source,'unlock-390.png');
    await button(firstUnlock,'完成').click();
    await source.getByRole('button',{name:/邯院之光/}).click();
    await firstUnlock.getByLabel(/使用称号/).check();
    await button(firstUnlock,'佩戴荣誉').click();
    await button(firstUnlock,'更新佩戴').waitFor();
    await button(firstUnlock,'完成').click();
    await source.getByText(/佩戴 校园手记/).waitFor();
    await source.getByRole('heading',{name:'身份标识'}).waitFor();
    await source.getByText('种子用户',{exact:true}).waitFor();
    const distribution = source.getByText('稀有度分布',{exact:true});
    await distribution.click();
    assert.equal(await source.locator('.hc-rarity b').count(),5);
    assert.equal(Number(await source.locator('.hc-rarity b').nth(2).textContent()),2);
    await distribution.click();
    await shot(source,'collection-390.png');
    await button(source,'社区成就').click();
    const cards = source.locator('.hc-gallery');
    const ordinaryEarned = cards.getByRole('button',{name:/破壳而出/});
    const ordinaryLocked = cards.getByRole('button',{name:/开始发芽/});
    await ordinaryEarned.getByText('已解锁',{exact:true}).waitFor();
    await ordinaryLocked.getByText('未解锁',{exact:true}).waitFor();
    assert.equal(await ordinaryEarned.getAttribute('data-state'),'earned');
    assert.equal(await ordinaryLocked.getAttribute('data-state'),'locked');
    for (const theme of ['light','dark']) {
      await source.evaluate(value=>{document.documentElement.dataset.theme=value;},theme);
      const background = item => item.evaluate(el=>getComputedStyle(el).backgroundColor);
      assert.notEqual(await background(ordinaryEarned),await background(ordinaryLocked));
      assert.equal(await ordinaryEarned.evaluate(el=>getComputedStyle(el).borderTopStyle),'solid');
      assert.equal(await ordinaryLocked.evaluate(el=>getComputedStyle(el).borderTopStyle),'dashed');
    }
    await source.evaluate(()=>{document.documentElement.dataset.theme='light';});
    for (const width of [320,360,390,430]) {
      await source.setViewportSize({width,height:844});
      assert(await cards.evaluate(el=>el.scrollWidth<=el.clientWidth+1));
    }
    await source.setViewportSize({width:390,height:844});
    await shot(source,'achievement-states-390.png');
    const statePicker=source.getByRole('group',{name:'成就解锁状态'});
    await button(statePicker,'已解锁').click();
    assert.equal(await cards.locator('.hc-card:not([data-state="earned"])').count(),0);
    await button(statePicker,'未解锁').click();
    await ordinaryLocked.waitFor();
    assert.equal(await cards.locator('.hc-card:not([data-state="locked"])').count(),0);
    await button(source,'日常').click();
    assert.equal(await cards.locator('.hc-mystery').count(),0);
    await ordinaryLocked.click();
    await source.getByRole('dialog').getByText('未解锁',{exact:true}).waitFor();
    await button(source.getByRole('dialog'),'完成').click();
    await button(source,'全部').click();
    await button(statePicker,'全部状态').click();
    const achievement = source.getByRole('button',{name:/开服第一批/});
    await achievement.click();
    const medal = source.getByRole('dialog');
    assert.equal(await button(medal,'佩戴荣誉').count(),0);
    await button(medal,'展示到个人主页').click();
    await button(medal,'从主页取下').waitFor();
    await button(medal,'完成').click();
    await button(source,'隐藏').click();
    await source.locator('.hc-mystery').first().waitFor();
    assert.equal(await source.getByText('凌晨四点的邯院',{exact:true}).count(),0);
    await shot(source,'achievements-390.png');
    const {post} = await call(reader.state,'posts.create',{requestId:randomUUID(),body:'荣誉佩戴测试帖子',anonymous:false});
    assert.equal(post.author.badges.official,null);
    assert.equal(post.author.badges.collection.title,'校园手记');
    const anonymous = await call(reader.state,'posts.create',{requestId:randomUUID(),body:'匿名发言权限测试',anonymous:true});
    assert(!anonymous.post.author.badges);
    await back(source);
    await source.getByRole('button',{name:/年度/}).first().click();
    await source.getByLabel('年份').selectOption({label:String(year)});
    await source.locator('.hc-archive').getByText(/年度最温暖的人/).waitFor();
    await shot(source,'annual-390.png');
    for (const row of (await call(reader.state,'collection.archive',{section:'annual'})).honorArchive) {
      assert(!Object.hasOwn(row,'evidence'));
    }
    await assert.rejects(call(reader.state,'collection.admin'),{code:'forbidden'});
    await owner.page.reload();
    await owner.page.locator('.th-nav .th-self:not([disabled])').waitFor();
    await owner.page.waitForFunction(() => !document.querySelector('.unlock-toast'), undefined, {timeout:15000});
    await owner.page.locator('.th-nav .th-self:not([disabled])').click();
    await button(owner.page,'身份与荣誉管理').click();
    const admin = owner.page;
    await admin.getByText('系统自动发放',{exact:false}).first().waitFor();
    for (const name of ['捉虫大师','这个 Bug 修好了','校园观察家','今天的邯院','开服第一批','校园传奇','迎新季引路人']) {
      assert.equal(await admin.getByText(name,{exact:true}).count(),0);
    }
    await admin.getByRole('heading',{name:'常设荣誉'}).waitFor();
    await admin.getByRole('heading',{name:'年度荣誉'}).waitFor();
    assert.equal(await admin.getByText('年度最温暖的人',{exact:true}).count(),0);
    await shot(admin,'honor-management-390.png');
    await button(admin,'授予与称号').click();
    await admin.getByLabel('查找成员').fill('校园档案测试同学');
    await button(admin,'搜索').click();
    await admin.getByRole('button',{name:/^校园档案测试同学 · /}).click();
    await admin.getByLabel('待授荣誉').selectOption('creator');
    assert.equal(await admin.getByRole('option',{name:'这个 Bug 修好了'}).count(),0);
    assert.equal(await admin.getByRole('option',{name:'初代居民'}).count(),0);
    await admin.getByLabel('管理原因').fill('核实过多次发布的原创作品');
    await button(admin,'核对并授予').click();
    await button(admin,'确认执行').click();
    await admin.getByText('授予 优质创作者已完成',{exact:true}).waitFor();
    assert((await call(owner.state,'collection.admin',{memberId:collector})).managedLegacyHonors.some(g=>g.code==='creator'));
    await button(admin,'审核社区成就').click();
    await admin.getByLabel('待审核成就').waitFor();
    assert.equal(await admin.getByRole('option',{name:'这个 Bug 修好了'}).count(),0);
    assert.equal(await admin.getByRole('option',{name:'邯院之光'}).count(),0);
    await button(owner.page,'发放记录').click();
    await owner.page.getByLabel('只查看异常发放').check();
    await owner.page.getByText(/发放数量已用完/).waitFor();
    await shot(owner.page,'management-390.png');
    const question=(await call(owner.state,'posts.create',{requestId:randomUUID(),body:'图书馆从哪里进去',anonymous:false,category:'help'})).post;
    const answer=(await call(reader.state,'comments.create',{postId:question.id,requestId:randomUUID(),body:'从校园东门直走',anonymous:false})).comment;
    await admin.reload();
    await admin.locator('.th-post').filter({hasText:'图书馆从哪里进去'}).locator('.th-post-body').click();
    await button(admin,'采纳').click();
    await admin.getByText('已采纳',{exact:true}).waitFor();
    assert.equal((await call(reader.state,'posts.get',{postId:question.id})).post.acceptedAnswerId,answer.id);
    await button(admin,'撤销采纳').click();
    await button(admin,'采纳').waitFor();
    assert.equal((await call(reader.state,'posts.get',{postId:question.id})).post.acceptedAnswerId,null);
    await back(source);
    await back(source);
    await source.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'我的',exact:true}).click();
    await source.locator('.collection-entry .case-all').click();
    await source.getByRole('heading',{name:'成就收藏馆'}).waitFor();
    const total=source.getByRole('progressbar',{name:'成就收藏进度'});
    await source.locator('.cabinet-grid [data-code="first-hundred"].unlocked').waitFor();
    assert.equal(await total.getAttribute('max'),'46');
    assert.equal(await source.locator('.cabinet-grid [data-code="arrival"]').count(),1);
    const groups=source.getByRole('navigation',{name:'成就分类'});
    await button(groups,'社区').click();
    await source.locator('.cabinet-grid [data-code="hundred-likes"]').waitFor();
    await button(groups,'隐藏').click();
    assert.equal(await source.locator('.cabinet-grid button').count(),13);
    await source.locator('.cabinet-grid [data-code="world-lines"].unlocked').waitFor();
    assert.equal(await source.locator('.cabinet-grid').getByText('凌晨四点的邯院',{exact:true}).count(),0);
    await source.locator('.cabinet-grid [data-code^="community-mystery-"]').first().click();
    const hidden=source.getByRole('dialog');
    await hidden.getByRole('heading',{name:'隐藏成就',exact:true}).waitFor();
    assert.equal(await hidden.getByText('获取条件',{exact:true}).count(),0);
    await source.keyboard.press('Escape');
    await shot(source,'global-hidden-achievements-390.png');
    assert(reader.state.collection?.items.some(item=>item.code==='world-lines'&&item.awardId));
    await reader.context.setOffline(true);
    await button(source,'返回上一页').click();
    await source.locator('.collection-entry .case-all').click();
    await source.locator('.cabinet-grid [data-code="world-lines"].unlocked').waitFor();
    assert.deepEqual([...owner.errors,...reader.errors],[]);
    console.log('PASS honor archive and collection at 360/390/430px, unlock, wear and title, edition archive, permissions and anomaly log');
  } finally {
    await owner.context.close();
    await reader.context.close();
  }
}
