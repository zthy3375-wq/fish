export const treeholeCategories=[{id:'daily',name:'校园日常',description:'记录日常与校园瞬间'},{id:'help',name:'提问求助',description:'遇到问题，一起找答案'},{id:'study',name:'学习交流',description:'课程、考试与学习经验'},{id:'buddies',name:'兴趣搭子',description:'找到一起玩的人'}] as const;
export const treeholeCategoryName=(id:string|undefined)=>treeholeCategories.find(x=>x.id===id)?.name||'校园日常';
