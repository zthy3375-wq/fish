import assert from 'node:assert/strict';
export async function registerTestAccount(page,username,nickname){
 await page.getByRole('button',{name:'注册账号',exact:true}).click();
 await page.getByLabel('登录账号',{exact:true}).fill(username);
 const handle=page.getByLabel('公开昵称',{exact:true});
 const registerWithNickname=await handle.count()===1;
 assert.equal(await page.locator('.th-auth input').count(),registerWithNickname?3:2);
 if(registerWithNickname)await handle.fill(nickname);
 await page.getByLabel('密码',{exact:true}).fill('synthetic-long-password');
 await page.getByRole('button',{name:'创建账号',exact:true}).click();
 if(registerWithNickname){
  await page.locator('.th-nav').getByRole('button',{name:nickname,exact:true}).waitFor();
  return;
 }
 await page.locator('.th-self:not([disabled])').click();
 await page.getByRole('button',{name:/^(编辑资料|修改昵称)$/}).click();
 await page.getByLabel('公开昵称',{exact:true}).fill(nickname);
 await page.getByRole('button',{name:'保存',exact:true}).click();
 await page.getByText('资料已更新',{exact:true}).waitFor();
 await page.getByRole('button',{name:'返回社区',exact:true}).click();
 await page.getByRole('button',{name:'返回社区',exact:true}).click();
 await page.locator('.th-nav').getByRole('button',{name:nickname,exact:true}).waitFor();
}
