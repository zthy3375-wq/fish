export const honorCategories = {
  identity: "身份", contribution: "贡献", legend: "传奇", limited: "限定", hidden: "隐藏",
} as const;
export const honorRarities = {
  common: "普通", fine: "精良", rare: "稀有", epic: "史诗", legendary: "传说",
} as const;
export type HonorCategory = keyof typeof honorCategories;
export type HonorRarity = keyof typeof honorRarities;
export interface CollectionBadge {
  id: string;
  code: string;
  name: string;
  rarity: HonorRarity;
  title?: string | null;
}
export interface CollectionItem {
  id: string;
  code: string;
  name: string;
  category: HonorCategory;
  rarity: HonorRarity;
  year?: number | null;
  archived: boolean;
  capacity?: number | null;
  criteria?: string | null;
  awardId?: string | null;
  at?: string | null;
  story?: string | null;
  publicHidden: boolean;
}
export interface CollectionProfile {
  id: string;
  nickname: string;
  items: CollectionItem[];
  badges: import("./communityHonors").Identity;
  identities: import("./communityHonors").BadgeCode[];
  customTitle?: string | null;
  useTitle: boolean;
  total: number;
  rarities: Partial<Record<HonorRarity, number>>;
  unseen: string[];
}
export interface HonorArchiveItem extends CollectionItem {
  memberId: string;
  nickname: string;
}
export interface CollectionDefinition extends CollectionItem {
  mode: "automatic" | "review" | "template";
  defaultStory: string;
  issued: number;
}
export interface CollectionMember {
  id: string;
  nickname: string;
  customTitle?: string | null;
}
export interface CollectionGrant {
  id: string;
  name: string;
  year?: number | null;
  at: string;
  revoked?: string | null;
  evidence?: string | null;
}
export interface CollectionAudit {
  id: string;
  operation: string;
  outcome: string;
  nickname?: string | null;
  at: string;
  reason?: string | null;
  evidence?: string | null;
}
export const archiveSections = {
  legend: "传奇人物", annual: "历届年度", contribution: "历史贡献", retired: "绝版收藏",
} as const;
export function honorName(item: Pick<CollectionItem, "name" | "year">) {
  return item.year ? item.year + " · " + item.name : item.name;
}
