import path from 'node:path';

/** Full local edit flow with the synthetic school bridge; no real school writes. */
export async function checkCourseAdjustment(page, assert, {width, output}) {
 const title='人工 UI 链路课程';
 const nav=name=>page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name,exact:true});
 const card=()=>page.locator('.positioned-course').filter({hasText:title}).first();
 await page.getByLabel('跳转教学周',{exact:true}).selectOption('10');
 await card().click();
 await page.getByRole('button',{name:'调整时间/地点',exact:true}).click();
 const editor=page.locator('.school-adjustment');
 assert(await editor.getByLabel('生效周',{exact:true}).inputValue()==='10',`${width}: adjustment opens for the selected timetable week`);
 await editor.getByLabel('星期',{exact:true}).selectOption('4');
 await editor.getByLabel('开始节次',{exact:true}).selectOption('6');
 await editor.getByLabel('结束节次',{exact:true}).selectOption('7');
 await editor.getByLabel('上课教室',{exact:true}).fill('调课测试教室');
 await page.screenshot({path:path.join(output,`course-adjustment-editor-${width}.png`),animations:'disabled'});
 assert(await editor.evaluate(el=>el.scrollWidth<=innerWidth),`${width}: adjustment editor fits mobile width`);
 await editor.getByRole('button',{name:'保存',exact:true}).click();
 await editor.waitFor({state:'hidden'});
 await page.waitForFunction(()=>window.__widgetSnapshots?.at(-1)?.courses.some(c=>c.room==='调课测试教室'&&c.day===4&&c.start==='14:30'&&c.weeks.length===1&&c.weeks[0]===10));
 assert(await card().innerText().then(t=>t.includes('调课测试教室')),`${width}: selected week shows the moved lesson`);
 const cached=await page.evaluate(()=>JSON.parse(localStorage.getItem('handan.academic.cache.v050')));
 assert(cached.courseAdjustments.length===1&&cached.courseAdjustments[0].week===10,`${width}: one-week change is persisted separately from school source`);
 assert(cached.terms[cached.selectedTerm].data.courses.find(c=>c.name==='人工 UI 链路课程').arrangements[0].day===1,`${width}: original school arrangement stays intact`);
 await page.getByLabel('跳转教学周',{exact:true}).selectOption('9');
 assert(!(await card().innerText()).includes('调课测试教室'),`${width}: other weeks keep the original room`);
 await page.reload(); await page.getByLabel('跳转教学周',{exact:true}).waitFor();
 await page.getByLabel('跳转教学周',{exact:true}).selectOption('10');
 await page.waitForFunction(()=>window.__academicCalls.includes('getTimetable'));
 assert((await card().innerText()).includes('调课测试教室'),`${width}: relaunch and automatic school refresh preserve the adjustment`);
 await card().click(); await page.getByRole('button',{name:'调整时间/地点',exact:true}).click();
 await editor.getByLabel('上课教室',{exact:true}).fill('未保存的修改');
 await page.goBack();
 await editor.getByRole('button',{name:'放弃修改',exact:true}).waitFor();
 assert(await editor.isVisible(),`${width}: back protects an unsaved adjustment`);
 await editor.getByRole('button',{name:'放弃修改',exact:true}).click();
 await editor.waitFor({state:'hidden'});
 // Check a conflicting all-term move and explicit confirmation.
 await card().click(); await page.getByRole('button',{name:'调整时间/地点',exact:true}).click();
 await editor.getByLabel('调整范围',{exact:true}).selectOption('future');
 await editor.getByLabel('起始周',{exact:true}).selectOption('10');
 await editor.getByLabel('星期',{exact:true}).selectOption('2');
 await editor.getByLabel('开始节次',{exact:true}).selectOption('3');
 await editor.getByLabel('结束节次',{exact:true}).selectOption('4');
 await editor.getByRole('button',{name:'保存',exact:true}).click();
 await editor.getByRole('alert').filter({hasText:'重叠'}).waitFor();
 assert(await editor.isVisible(),`${width}: conflicting move requires explicit confirmation`);
 await editor.getByRole('checkbox',{name:'已核对时间冲突，仍然保存'}).check();
 await editor.getByRole('button',{name:'保存',exact:true}).click();
 await editor.waitFor({state:'hidden'});
 const future=await page.evaluate(()=>JSON.parse(localStorage.getItem('handan.academic.cache.v050')).courseAdjustments.map(a=>a.week));
 assert(JSON.stringify(future)===JSON.stringify([10,11,12,13,14,15,16,17,18]),`${width}: future move changes only existing weeks from the selected week`);
 // Overlapping cards open the existing collision list first.
 const overlap=page.getByRole('button',{name:/门重叠课程：.*人工 UI 链路课程/}).first();
 if(await overlap.count()) {
  await overlap.click(); await page.locator('[data-overlay] .service-row').filter({hasText:title}).click();
 } else { await card().click(); }
 await page.getByRole('button',{name:'恢复学校安排',exact:true}).click();
 await page.getByRole('button',{name:'确认恢复',exact:true}).click();
 await page.locator('[data-overlay]').waitFor({state:'hidden'});
 assert((await page.evaluate(()=>JSON.parse(localStorage.getItem('handan.academic.cache.v050')).courseAdjustments)).length===0,`${width}: restore removes this lesson's local changes`);
 await page.getByLabel('跳转教学周',{exact:true}).selectOption('9');
 assert(!(await card().innerText()).includes('调课测试教室'),`${width}: restored original is shown again`);
 await page.screenshot({path:path.join(output,`course-adjustment-restored-${width}.png`),animations:'disabled'});
 await nav('课表').click();
}
