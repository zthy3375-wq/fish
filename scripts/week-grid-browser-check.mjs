import path from 'node:path';

/** Check rendered geometry, including legacy WebViews without dynamic viewport units. */
export async function checkWeekGrid(page, assert, {width, output}) {
 const grid=page.locator('.period-grid');
 const geometry=()=>grid.evaluate(el=>{
  const body=el.querySelector('.period-grid-body').getBoundingClientRect();
  const labels=[...el.querySelectorAll('.period-label')].map(n=>n.getBoundingClientRect());
  const cards=[...el.querySelectorAll('.positioned-course')].map(n=>n.getBoundingClientRect());
  const practice=document.querySelector('.schedule-page>.panel')?.getBoundingClientRect();
  const shell=document.querySelector('.app-shell').getBoundingClientRect();
  return {
   height:body.height,
   rowsDistinct:labels.every((r,i)=>r.height>0&&(!i||r.top>=labels[i-1].bottom-.5)),
   cardsContained:cards.every(r=>r.height>0&&r.top>=body.top&&r.bottom<=body.bottom+.5),
   practiceBelow:!practice||practice.top>=body.bottom-.5,
   shellFits:Math.abs(shell.height-innerHeight)<2,
  };
 });
 for(const comfortable of [false,true]) {
  if(comfortable)await page.getByRole('button',{name:'整周总览',exact:true}).click();
  for(const bottom of [false,true]) {
   await page.locator('main').evaluate((el,bottom)=>el.scrollTop=bottom?el.scrollHeight:0,bottom);
   const g=await geometry();
   const label=`${width}: ${comfortable?'comfortable':'overview'} ${bottom?'bottom':'top'}`;
   assert(g.height>400,`${label} timetable reserves its height`);
   assert(g.rowsDistinct,`${label} period labels never stack`);
   assert(g.cardsContained,`${label} course cards stay inside time axis`);
   assert(g.practiceBelow,`${label} practice panel stays below timetable`);
   assert(g.shellFits,`${label} app viewport retains scroll height`);
  }
  await page.screenshot({path:path.join(output,`week-grid-${comfortable?'comfortable':'overview'}-${width}.png`)});
 }
 await page.getByRole('button',{name:'舒适阅读',exact:true}).click();
 await page.locator('main').evaluate(el=>el.scrollTop=0);
}
