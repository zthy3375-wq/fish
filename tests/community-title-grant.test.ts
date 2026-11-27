// @vitest-environment jsdom
import {createApp,nextTick} from 'vue';
import {afterEach, expect, it, vi} from 'vitest';
import CollectionAdmin from '../src/components/honors/CollectionAdmin.vue';
import type {TreeholeResult} from '../src/services/treehole';

const person = {id:'5fd4ac4d-43df-42ef-9764-7d8d77b8cfd2',nickname:'测试同学',username:'student'};
const cleanup: (()=>void)[] = [];
afterEach(()=>{cleanup.splice(0).forEach(f=>f()); vi.unstubAllGlobals(); document.body.replaceChildren();});

async function open(query:string) {
  const writes:Record<string,unknown>[]=[];
  const request = async (action:string, body:Record<string,unknown>={}):Promise<TreeholeResult> => {
    if(action==='collection.change'){ writes.push(body); return {}; }
    if(action==='admin.members')return {registeredMembers:[person]};
    return {honorDefinitions:[],honorAudit:[],managedLegacyHonors:[],
      honorMembers:[person.nickname,person.id].includes(String(body.query))?[person]:[]};
  };
  const root=document.createElement('div'); document.body.appendChild(root);
  const app=createApp(CollectionAdmin,{request}); app.mount(root);cleanup.push(()=>app.unmount());
  async function click(label:string) {
    const btn=[...root.querySelectorAll('button')].find(x=>x.textContent?.includes(label));
    expect(btn, label).toBeDefined();await vi.waitFor(()=>expect(btn!.disabled).toBe(false));btn!.click(); await nextTick(); await nextTick();
  }
  await nextTick();await nextTick();
  await click('授予与称号');
  const input=root.querySelector('form input') as HTMLInputElement;
  input.value=query;input.dispatchEvent(new Event('input')); await click('搜索');
  await vi.waitFor(()=>expect(root.textContent).toContain(person.nickname));
  await click(person.nickname);
  return {root,click,writes};
}

it('resolves a login account to the member selected for a grant',async()=>{
  const {root}=await open(person.username);
  expect(root.textContent).toContain('测试同学的授予记录');
});
it('sends a title change on WebViews that only expose getRandomValues',async()=>{
  vi.stubGlobal('crypto',{getRandomValues:crypto.getRandomValues.bind(crypto)});
  const {root,click,writes}=await open(person.nickname);
  const title=root.querySelector('input[maxlength="16"]') as HTMLInputElement;
  title.value='校园手记'; title.dispatchEvent(new Event('input'));
  await click('保存称号');await click('确认执行');
  await vi.waitFor(()=>expect(writes).toHaveLength(1));
  expect(writes[0]).toMatchObject({memberId:person.id,operation:'title',title:'校园手记',
    requestId:expect.stringMatching(/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/)});
});
