/** Synthetic bridge checks only. Does not verify installed provider apps or live identity codes. */
import path from 'node:path';

export async function checkParcelShortcuts(page, assert, {width, output}) {
  const nav = label => page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: label, exact: true});
  const shortcuts = page.getByRole('region', {name: '菜鸟驿站出库码'});
  await shortcuts.waitFor();
  const historyLength = await page.evaluate(() => history.length);
  const storageBefore = await page.evaluate(() => ({school: localStorage.getItem('handan.academic.cache.v050'), personal: localStorage.getItem('handan.personal.tasks.v2')}));
  assert(await shortcuts.getByRole('button', {name: '淘宝出库码', exact: true}).count() === 1, `${width}: parcel entry labels Taobao explicitly`);
  assert(await shortcuts.getByRole('button', {name: '拼多多出库码', exact: true}).count() === 1, `${width}: parcel entry labels Pinduoduo explicitly`);
  assert(await page.evaluate(() => window.__parcelCalls.length) === 0, `${width}: parcel entry never auto-launches a provider`);
  await shortcuts.getByRole('button', {name: '淘宝出库码', exact: true}).click();
  await shortcuts.getByRole('status').filter({hasText: '已请求打开淘宝'}).waitFor();
  assert(await shortcuts.getByRole('status').innerText() === '已请求打开淘宝，请在官方 App 内查看身份码。返回本应用不代表已出库。', `${width}: parcel launch does not claim verification or pickup success`);
  assert(await page.evaluate(() => JSON.stringify(window.__parcelCalls[0]) === JSON.stringify({method: 'open', args: {provider: 'taobao'}})), `${width}: parcel native call contains provider only`);
  const storageAfter = await page.evaluate(() => ({school: localStorage.getItem('handan.academic.cache.v050'), personal: localStorage.getItem('handan.personal.tasks.v2')}));
  assert(JSON.stringify(storageAfter) === JSON.stringify(storageBefore), `${width}: parcel shortcut does not mutate school or personal caches`);
  for (const [status, text] of [['not_installed', '未检测到拼多多 App'], ['unavailable', '暂时无法打开拼多多出库码'], ['cancelled', '已取消打开拼多多']]) {
    await page.evaluate(value => { window.__parcelStatus = value }, status);
    await shortcuts.getByRole('button', {name: '拼多多出库码', exact: true}).click();
    await shortcuts.getByRole('status').filter({hasText: text}).waitFor();
    assert(await shortcuts.getByRole('button', {name: '拼多多出库码', exact: true}).isEnabled(), `${width}: parcel ${status} leaves deliberate retry available`);
  }
  const calls = await page.evaluate(() => window.__parcelCalls.length);
  await page.evaluate(() => { window.__parcelDelayed = true });
  await shortcuts.getByRole('button', {name: '淘宝出库码', exact: true}).evaluate(button => { button.click(); button.click() });
  await shortcuts.getByRole('button', {name: '拼多多出库码', exact: true}).waitFor({state: 'visible'});
  assert(await shortcuts.getByRole('button', {name: '拼多多出库码', exact: true}).isDisabled(), `${width}: parcel pending dispatch disables both provider buttons`);
  assert(await page.evaluate(() => window.__parcelCalls.length) === calls + 1, `${width}: repeated parcel taps dispatch only once`);
  await nav('我的').click();
  await shortcuts.waitFor();
  await page.evaluate(() => { window.__parcelFinish(); window.__parcelDelayed = false; window.__parcelStatus = 'opened' });
  await page.waitForTimeout(30);
  assert(await shortcuts.getByRole('status').count() === 0, `${width}: old parcel launch reply does not appear after navigation`);
  await shortcuts.getByRole('button', {name: '拼多多出库码', exact: true}).click();
  await shortcuts.getByRole('status').filter({hasText: '已请求打开拼多多'}).waitFor();
  assert(await page.locator('.floating-nav button').count() === 5, `${width}: parcel feature preserves the five navigation tabs`);
  assert(await page.evaluate(() => history.length) === historyLength, `${width}: parcel launch adds no browser-history entry`);
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${width}: parcel card has no horizontal overflow`);
  await shortcuts.scrollIntoViewIfNeeded();
  await page.screenshot({path: path.join(output, `parcel-shortcuts-${width}.png`), animations: 'disabled'});
  await nav('今天').click();
}
