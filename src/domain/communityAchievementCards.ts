import { Award, BookOpenCheck, Camera, Flag, HandHeart, Heart, HelpCircle, MapPin, MessageCircle, Star, Trophy } from 'lucide-vue-next';
import { byCode, type Collectible } from './globalAchievements';
import { collectionKind, displayCollectionName, honorName, isRetiredAchievement, type CollectionItem } from './honorCollection';

export const communityHiddenCount = 5;

export interface AchievementCard extends Collectible {
  cloud?: CollectionItem;
  needsSync?: boolean;
}

const milestones = [
  ['first-hundred','开服第一批',Flag],
  ['campus-observer','今天的邯院',MapPin],
  ['good-company','这一楼热闹了',MessageCircle],
  ['answer-guide','帮上忙了',HandHeart],
  ['campus-photographer','留住邯院的光',Camera],
  ['community-classic','这帖被记住了',Trophy],
  ['landmark-post','这帖火了',Star],
  ['hundred-likes','一百个赞',Heart],
  ['full-page','写满这一页',BookOpenCheck],
] as const;

const tiers = {common:'普通',fine:'普通',rare:'稀有',epic:'史诗',legendary:'传奇'} as const;
const colors = {common:'#705995',fine:'#536ca3',rare:'#7855a5',epic:'#946214',legendary:'#97512e'};

export function communityAchievementCards(items: CollectionItem[] = [], synced = false): AchievementCard[] {
  const records = new Map(items.filter(item =>
    collectionKind(item)==='achievement' && !byCode.has(item.code)
    && (item.awardId || (item.category!=='hidden' && !isRetiredAchievement(item.code)))
  ).map(item=>[item.code,item]));
  const cards: AchievementCard[] = milestones.map(([code,name,icon])=>({
    code,name,icon,source:'community',group:'社区',tier:'普通',color:colors.common,goal:1,
    condition:'同步社区记录后可查看解锁条件。',description:'连接社区后可查看这项成就。',needsSync:true,
  }));
  const index = new Map(cards.map((card,i)=>[card.code,i]));
  let discovered = 0;
  for (const item of records.values()) {
    const position = index.get(item.code);
    const retired = isRetiredAchievement(item.code);
    const hidden = item.category==='hidden';
    if (hidden && !retired) discovered++;
    const card: AchievementCard = {
      code:item.code,name:honorName({...item,name:displayCollectionName(item)}),
      group:retired?'已停发':hidden?'隐藏':'社区',source:'community',
      icon:position===undefined?Award:cards[position].icon,tier:tiers[item.rarity],color:colors[item.rarity],
      goal:1,hidden,condition:item.criteria??'',description:item.story??item.criteria??'已获得的社区成就。',cloud:item,
    };
    if (position===undefined) cards.push(card);
    else cards[position]=card;
  }
  for (let i=discovered;i<communityHiddenCount;i++) {
    cards.push({code:'community-mystery-'+i,name:'隐藏成就',group:'隐藏',source:'community',tier:'稀有',icon:HelpCircle,
      color:colors.rare,condition:'',description:'',goal:1,hidden:true,needsSync:!synced});
  }
  return cards;
}
