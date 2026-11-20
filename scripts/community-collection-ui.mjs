import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { registerTestAccount } from './community-test-account.mjs';

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
    await button(source,'荣誉殿堂').click();
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
    await firstUnlock.getByText('新荣誉已获得',{exact:true}).waitFor();
    await shot(source,'unlock-390.png');
    await button(firstUnlock,'完成').click();
    await source.getByRole('button',{name:/邯院之光/}).click();
    await firstUnlock.getByLabel(/使用称号/).check();
    await button(firstUnlock,'佩戴荣誉').click();
    await button(firstUnlock,'更新佩戴').waitFor();
    await button(firstUnlock,'完成').click();
    await source.getByText(/佩戴 校园手记/).waitFor();
    await shot(source,'collection-390.png');
    const {post} = await call(reader.state,'posts.create',{requestId:randomUUID(),body:'荣誉佩戴测试帖子',anonymous:false});
    assert.equal(post.author.badges.official.code,'seed');
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
    await button(owner.page,'发放记录').click();
    await owner.page.getByLabel('只查看异常发放').check();
    await owner.page.getByText(/发放数量已用完/).waitFor();
    await shot(owner.page,'management-390.png');
    assert.deepEqual([...owner.errors,...reader.errors],[]);
    console.log('PASS honor archive and collection at 360/390/430px, unlock, wear and title, edition archive, permissions and anomaly log');
  } finally {
    await owner.context.close();
    await reader.context.close();
  }
}
