export const honorCategories = {
  identity: "身份", contribution: "贡献", legend: "传奇", limited: "限定", hidden: "隐藏",
} as const;
export const honorRarities = {
  common: "普通", fine: "精良", rare: "稀有", epic: "史诗", legendary: "传说",
} as const;
export type HonorCategory = keyof typeof honorCategories;
export type HonorRarity = keyof typeof honorRarities;
export type CollectionKind = "honor" | "achievement" | "history";
export interface CollectionBadge {
  id: string;
  code: string;
  name: string;
  rarity: HonorRarity;
  title?: string | null;
  year?: number | null;
}
export interface CollectionItem {
  id: string;
  code: string;
  name: string;
  category: HonorCategory;
  displayKind?: CollectionKind;
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
  layoutVersion?: number;
  legacyHonors?: import("./communityHonors").Badge[];
  baseAwards?: Record<string, string>;
  showcase?: string[];
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

// The test.35 service does not send a layout kind. Keep old definitions readable during rollout.
const achievementNames: Record<string, string> = {
  "first-hundred":"开服第一批", "bug-hunter":"这个 Bug 修好了", "campus-observer":"今天的邯院",
  "good-company":"这一楼热闹了", "answer-guide":"帮上忙了", architect:"这功能有你一份",
  "landmark-post":"这帖火了", "campus-photographer":"留住邯院的光", "gold-creator":"三次上墙",
  "community-classic":"这帖被记住了", archivist:"翻到很久以前", "welcome-guide":"带新同学认路",
  "graduation-keepsake":"毕业季青春纪念章", "first-feature":"第一次上墙",
  "hundred-likes":"一百个赞", "full-page":"写满这一页",
};
const hiddenCodes = new Set(["before-dawn","developer-noticed","world-lines","archivist","crossed-paths","no-island"]);
const historicalCodes = new Set(["that-person", "campus-legend"]);
export function definitionCode(code: string) { return code.replace(/-[0-9]{4}$/, ""); }
export function collectionKind(item: Pick<CollectionItem, "code" | "category" | "displayKind">): CollectionKind {
  if (item.displayKind) return item.displayKind;
  if (historicalCodes.has(item.code)) return "history";
  return item.category === "hidden" || hiddenCodes.has(item.code) || Object.prototype.hasOwnProperty.call(achievementNames, definitionCode(item.code)) ? "achievement" : "honor";
}
export function displayCollectionName(item: Pick<CollectionItem, "code" | "name">) {
  return achievementNames[definitionCode(item.code)] ?? item.name;
}
