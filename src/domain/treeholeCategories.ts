export const treeholeCategories=[{id:'daily',name:'校园日常',description:'记录日常与校园瞬间'},{id:'help',name:'提问求助',description:'遇到问题，一起找答案'},{id:'study',name:'学习交流',description:'课程、考试与学习经验'},{id:'buddies',name:'兴趣搭子',description:'找到一起玩的人'}] as const;
export const treeholeSections=[{id:'daily',name:'校园日常',description:'校园瞬间、日常分享，也可以在这里问个问题'},{id:'entertainment',name:'兴趣娱乐',description:'聊聊最近喜欢的游戏、作品和爱好'},{id:'buddies',name:'搭子广场',description:'一起吃饭、运动、开黑，从一条帖子开始'},{id:'treehole',name:'匿名树洞',description:'把想说的话放在这里，本区统一匿名'}] as const;
export const treeholeInterests=[{id:'games',name:'游戏'},{id:'anime',name:'动漫'},{id:'film',name:'影视'},{id:'music',name:'音乐'},{id:'photo',name:'摄影'},{id:'sports',name:'运动'}] as const;
export const treeholeNewTopics=[
 {id:'graduate',name:'考研',category:'study'},
 {id:'reading',name:'读书',category:'entertainment'},
 {id:'fitness',name:'健身',category:'entertainment'},
] as const;
export const treeholeSection=(id:string)=>['help','study'].includes(id)?'daily':id;
export const treeholeCategoryName=(id:string|undefined)=>[...treeholeSections,...treeholeCategories].find(x=>x.id===id)?.name||'校园日常';
export const treeholeInterestName=(id:string|undefined)=>[...treeholeNewTopics,...treeholeInterests].find(x=>x.id===id)?.name||'';
export const treeholeTopicCategory=(id:string)=>treeholeNewTopics.find(topic=>topic.id===id)?.category||'entertainment';
export const treeholeNewTopic=(id:string)=>treeholeNewTopics.some(topic=>topic.id===id);
export const treeholeDestinationName=(category:string,interest:string)=>treeholeInterestName(interest)||({help:'校园互助',entertainment:'兴趣闲聊',buddies:'找搭子'} as Record<string,string>)[category]||treeholeCategoryName(category);
export function treeholeFeedFilters(category:string,interest:string,discovery:boolean){
 return discovery?{section:treeholeSection(category),category:['daily','help','study'].includes(category)?category:'all',interest}:{category};
}
