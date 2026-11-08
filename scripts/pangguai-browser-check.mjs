/** Synthetic page-launch contract only; never evidence of a real account balance or credited payment. */
import path from 'node:path';

export async function checkPangguaiOfficial(page, assert, {width, output}) {
  const nav = label => page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: label, exact: true});
  const card = page.getByRole('region', {name: '胖乖官方钱包与充值页面'});
  await card.waitFor();
  assert(await page.evaluate(() => (window.__pangguaiCalls ?? []).length) === 0, `${width}: Pangguai never opens a page automatically`);
  await card.getByRole('button', {name: '官方钱包', exact: true}).click();
  await card.getByRole('status').filter({hasText: '已请求打开胖乖官方页面'}).waitFor();
  assert(await card.getByRole('status').innerText() === '已请求打开胖乖官方页面。余额、登录与充值结果请在官方页面核对，返回不代表充值成功。', `${width}: Pangguai launch is not claimed as login or payment success`);
  assert(await page.evaluate(() => JSON.stringify(window.__pangguaiCalls[0]) === JSON.stringify({method: 'open', args: {page: 'wallet'}})), `${width}: Pangguai native call contains a fixed page only`);
  assert(await card.locator('input,canvas,img,iframe').count() === 0, `${width}: Pangguai entry has no credential fields or invented balance widget`);
  await card.getByRole('button', {name: '官方充值页面', exact: true}).click();
  await card.getByRole('status').filter({hasText: '已请求打开胖乖官方页面'}).waitFor();
  assert(await page.evaluate(() => window.__pangguaiCalls.at(-1).args.page) === 'operators', `${width}: Pangguai recharge opens official operator selection, not a guessed school merchant`);
  for (const [status, text] of [['cancelled', '已取消打开胖乖官方页面'], ['unavailable', '暂时无法打开胖乖官方页面']]) {
    await page.evaluate(value => { window.__pangguaiStatus = value }, status);
    await card.getByRole('button', {name: '官方钱包', exact: true}).click();
    await card.getByRole('status').filter({hasText: text}).waitFor();
    assert(await card.getByRole('button', {name: '官方钱包', exact: true}).isEnabled(), `${width}: Pangguai ${status} permits a deliberate retry`);
  }
  await nav('生活').click();
  await card.waitFor();
  assert(await card.getByRole('status').count() === 0, `${width}: Pangguai profile entry does not reuse a prior page launch result`);
  await page.evaluate(() => { window.__pangguaiStatus = 'opened' });
  await card.getByRole('button', {name: '官方钱包', exact: true}).click();
  await card.getByRole('status').filter({hasText: '已请求打开胖乖官方页面'}).waitFor();
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${width}: Pangguai card has no horizontal overflow`);
  await card.scrollIntoViewIfNeeded();
  await page.screenshot({path: path.join(output, `pangguai-official-${width}.png`), animations: 'disabled'});
  await nav('今天').click();
}
