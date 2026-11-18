const mainNames={all:'全部',daily:'校园',help:'校园',study:'学习',entertainment:'兴趣',buddies:'搭子',treehole:'树洞'};
const topicNames={graduate:'考研',reading:'读书',fitness:'健身',games:'游戏',anime:'动漫',film:'影视',music:'音乐',photo:'摄影',sports:'运动'};
const composeNames={daily:'校园日常',help:'校园互助',study:'学习交流',entertainment:'兴趣闲聊',buddies:'找搭子',treehole:'匿名树洞'};
export const feedNavigation=page=>page.getByRole('navigation',{name:'帖子分区',exact:true});
export const composeDestination=page=>page.locator('.th-board-trigger strong');
const button=(root,name)=>root.getByRole('button',{name,exact:true});
const activate=async(control,input)=>{if(await control.getAttribute('aria-pressed')!=='true')await control[input]();};

export async function browseBoard(page,selection,input='click'){
 const [board,topic]=selection.split('/');
 const nav=feedNavigation(page);
 const primary=button(nav,mainNames[board]);
 await activate(primary,input);
 if(board==='daily'||board==='help')await activate(button(page.getByRole('group',{name:'校园分区'}),board==='daily'?'日常':'校园互助'),input);
 if(board==='study'&&topic)await activate(button(page.getByRole('group',{name:'学习分区'}),topicNames[topic]),input);
 if(board==='entertainment'){
  const sub=page.getByRole('group',{name:'兴趣分区'});
  if(!topic||topic==='reading'||topic==='fitness')await activate(button(sub,topic?topicNames[topic]:'全部兴趣'),input);
  else{
   await sub.getByRole('button',{name:/^更多兴趣/})[input]();
   await button(page.getByRole('dialog',{name:'更多兴趣'}),topicNames[topic])[input]();
  }
 }
 await nav.locator('button:not(:disabled)').first().waitFor();
}

export async function choosePostBoard(page,selection,input='click'){
 const trigger=page.getByLabel('选择分区',{exact:true});
 await trigger.waitFor();
 if(await trigger.evaluate(el=>el.tagName==='SELECT')){await trigger.selectOption(selection);return;}
 const [board,topic]=selection.split('/');
 await trigger[input]();
 const sheet=page.getByRole('dialog',{name:'选择分区',exact:true});
 if(topic&&!['graduate','reading','fitness'].includes(topic)){
  const more=button(sheet,'更多兴趣');
  if(await more.getAttribute('aria-expanded')==='false')await more[input]();
 }
 await button(sheet,topic?topicNames[topic]:composeNames[board])[input]();
 await sheet.waitFor({state:'hidden'});
}
