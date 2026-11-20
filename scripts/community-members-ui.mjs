import assert from 'node:assert/strict';
import { registerTestAccount } from './community-test-account.mjs';

export async function checkMemberDirectory({client,db,api}) {
  const owner=await client(390);
  const ordinary=await client(360);
  const button=(page,name)=>page.getByRole('button',{name,exact:true});
  try {
    const registration=ordinary.page;
    await button(registration,'注册账号').click();
    await registration.getByLabel('登录账号',{exact:true}).fill('20260101');
    await registration.getByLabel('密码',{exact:true}).fill('synthetic-long-password');
    const nickname=registration.getByLabel('公开昵称',{exact:true});
    await button(registration,'创建账号').click();
    assert.equal(await nickname.evaluate(el=>el.validity.valueMissing),true);
    assert(!ordinary.state.actions.includes('register'));
    await nickname.fill('校园测试同学');
    await button(registration,'创建账号').click();
    await registration.locator('.th-nav').getByRole('button',{name:'校园测试同学',exact:true}).waitFor();
    const saved=ordinary.state.requests.find(request=>request.action==='register');
    assert.equal(saved.body.nickname,'校园测试同学');

    await registerTestAccount(owner.page,'dev_directory','开发测试账号');
    const developer=await api.execute('me',{},owner.state.token,'directory-ui');
    const moderator=await api.execute('me',{},ordinary.state.token,'directory-ui');
    await db.query("UPDATE hyt_members SET role='moderator',developer_since=now() WHERE id=$1",[developer.user.id]);
    await db.query("UPDATE hyt_members SET role='moderator',mod_caps=ARRAY['users'] WHERE id=$1",[moderator.user.id]);
    await db.exec(`INSERT INTO hyt_members(username,nickname,password_hash,recovery_hash,created_at)
      SELECT 'page_'||n,'分页测试'||n,'test','test',now()-interval '1 day' FROM generate_series(1,31) AS n`);

    await registration.reload();
    await registration.locator('.th-self:not([disabled])').click();
    await registration.getByRole('heading',{name:'管理工具'}).waitFor();
    assert.equal(await button(registration,'注册成员').count(),0);

    const page=owner.page;
    await page.reload();
    await page.locator('.th-self:not([disabled])').click();
    await button(page,'注册成员').click();
    const directory=page.getByRole('region',{name:'注册成员列表'});
    await directory.getByText('33',{exact:true}).waitFor();
    await directory.getByText('20260101',{exact:true}).waitFor();
    assert.equal(await directory.locator('li').count(),30);
    await button(page,'加载更多').click();
    await page.waitForFunction(()=>document.querySelectorAll('.th-directory-members li').length===33);
    assert(await directory.evaluate(el=>el.scrollWidth<=el.clientWidth+1));
    await directory.getByRole('searchbox').fill('202601');
    await button(page,'搜索').click();
    await page.waitForFunction(()=>document.querySelectorAll('.th-directory-members li').length===1);
    await directory.getByText('校园测试同学',{exact:true}).waitFor();
    await button(page,'返回社区').click();
    await page.getByRole('heading',{name:'管理工具'}).waitFor();
    assert.deepEqual([...owner.errors,...ordinary.errors],[]);
    console.log('PASS registration nickname validation and persistence, developer directory count, pagination, search, restricted moderator view and back navigation');
  } finally {
    await owner.context.close();
    await ordinary.context.close();
  }
}
