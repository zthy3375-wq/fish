/** Synthetic bridge only; real login/parcel/scan verification requires a device account. */
export async function checkParcelShortcuts(page, assert, {width}) {
  const entry = page.getByRole('button', {name:/取快递/});
  const before = await page.evaluate(() => ({calls:window.__parcelCalls.length, history:history.length, school:localStorage.getItem('handan.academic.cache.v050'), personal:localStorage.getItem('handan.personal.tasks.v2')}));
  await entry.click();
  await page.waitForFunction(n => window.__parcelCalls.length > n, before.calls);
  assert(await page.evaluate(() => JSON.stringify(window.__parcelCalls.at(-1)) === JSON.stringify({method:'openEmbedded', args:{provider:'taobao'}})), `${width}: homepage opens the native unified centre directly`);
  assert(await page.getByRole('region',{name:'菜鸟驿站出库码'}).count()===0, `${width}: no intermediate platform selection sheet`);
  await page.evaluate(() => {window.__parcelDelayed=true});
  const count=await page.evaluate(()=>window.__parcelCalls.length);
  await entry.evaluate(b=>{b.click();b.click()});
  assert(await page.evaluate(n=>window.__parcelCalls.length===n+1,count),`${width}: repeated taps coalesce`);
  await page.evaluate(()=>{window.__parcelFinish();window.__parcelDelayed=false});
  await page.waitForTimeout(30);
  const after=await page.evaluate(()=>({history:history.length,school:localStorage.getItem('handan.academic.cache.v050'),personal:localStorage.getItem('handan.personal.tasks.v2')}));
  assert(after.history===before.history && after.school===before.school && after.personal===before.personal,`${width}: native centre preserves navigation and academic caches`);
  assert(await page.locator('.floating-nav button').count()===4,`${width}: four tabs preserved`);
}
