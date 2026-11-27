/** Checks the Vue-to-Android navigation contract. Device controls are exercised in Android UI tests. */
export async function checkParcelShortcuts(page, assert, {width}) {
  const nav = label => page.getByRole('navigation', {name: '主导航'}).getByRole('button', {name: label, exact: true});
  await nav('首页').click();
  const entry = page.getByRole('button', {name: /取快递/});
  const historyLength = await page.evaluate(() => history.length);
  await page.evaluate(() => { window.__parcelCenterDelayed = true; });
  await entry.evaluate(button => { button.click(); button.click(); });
  assert(await page.evaluate(() => window.__parcelCenterCalls) === 1, `${width}: parcel entry opens the native center directly once`);
  assert(await page.getByRole('region', {name: '菜鸟驿站出库码'}).count() === 0, `${width}: Android parcel entry does not open an intermediate sheet`);
  await page.evaluate(() => {
    window.__parcelCenterDelayed = false;
    window.__parcelCenterFinish();
    window.__parcelCenterFailed = true;
  });
  await entry.click();
  await page.getByText('暂时无法打开校园取件，请重试', {exact: true}).waitFor();
  await page.evaluate(() => { window.__parcelCenterFailed = false; });
  await entry.click();
  assert(await page.evaluate(() => window.__parcelCenterCalls) === 3, `${width}: parcel launch can be retried after a native error`);
  assert(await page.locator('.floating-nav button').count() === 5, `${width}: parcel entry preserves the five tabs`);
  assert(await page.evaluate(() => history.length) === historyLength, `${width}: parcel entry leaves the home route in place for Android back`);
}
