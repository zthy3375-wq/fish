import { treeholeRequest, type TreeholeImage } from "./treehole";
export interface Contest {
  id: string;
  title: string;
  type: string;
  edition: string;
  description: string;
  rules: string;
  state: string;
  paused: boolean;
  startsAt: string;
  submissionEnds: string;
  votingStarts: string;
  votingEnds: string;
  awardAt: string;
  formats: string[];
  maxEntries: number;
  votesPerUser: number;
  minEntries: number;
  minAccountHours: number;
  excellence: number;
  autoPublish: boolean;
  reviewRisk?: boolean;
  version: number;
  entryCount: number;
  participantCount: number;
  coverPostId: string | null;
  cover?: TreeholeImage | null;
}
export interface ContestAward {
  revoked_at?: string | null;
  id: string;
  kind: string;
  rank: number | null;
  at?: string;
  awarded_at?: string;
  title?: string;
  edition?: string;
  contest_id?: string;
  entry_id?: string;
}
export interface ContestEntry {
  linked: boolean;
  id: string;
  contestId: string;
  memberId: string;
  title: string;
  body: string;
  postId: string | null;
  status: string;
  author: string;
  mine: boolean;
  createdAt: string;
  voted: boolean;
  votes: number | null;
  images: TreeholeImage[];
  awards: ContestAward[];
  version: number;
}
export interface ContestTheme {
  id: string;
  title: string;
  status: string;
  votes: number;
  voted: boolean;
  merged_into?: string | null;
}
export interface ContestAudit {
  id: string;
  action: string;
  reason: string;
  target_id: string | null;
  created_at: string;
}
export interface ContestVote {
  id: string;
  entry_id: string;
  member_id: string;
  enabled: boolean;
  excluded: boolean;
  risk: string | null;
}
export interface ContestResult {
  contests?: Contest[];
  contest?: Contest;
  entries?: ContestEntry[];
  entry?: ContestEntry;
  serverTime?: string;
  receivedAt?: number;
  myEntries?: ContestEntry[];
  votesUsed?: number;
  stats?: { participations: number; champions: number; podiums: number };
  awards?: ContestAward[];
  worn?: string | null;
  annual?: number[];
  themes?: ContestTheme[];
  solicitation?: boolean;
  leaders?: { id: string; nickname: string; score: number }[];
  votes?: ContestVote[];
  audit?: ContestAudit[];
  contestReports?: {
    id: string;
    entry_id: string;
    reason: string;
    entry: ContestEntry;
  }[];
  metrics?: Record<string, number>;
}
export const contestLabels: Record<string, string> = {
  draft: "草稿",
  upcoming: "未开始",
  submitting: "投稿中",
  waiting: "等待投票",
  voting: "投票中",
  reviewing: "结果审核中",
  ended: "已结束",
  cancelled: "已取消",
};
export const awardLabels: Record<string, string> = {
  champion: "冠军",
  silver: "亚军",
  bronze: "季军",
  excellent: "优秀作品",
  participation: "参赛纪念",
};
export function contestStage(c: Contest, now = Date.now()): string {
  if (["cancelled", "ended", "draft"].includes(c.state)) return c.state;
  if (now < Date.parse(c.startsAt)) return "upcoming";
  if (now < Date.parse(c.submissionEnds)) return "submitting";
  if (now < Date.parse(c.votingStarts)) return "waiting";
  return now < Date.parse(c.votingEnds) ? "voting" : "reviewing";
}
export function contestRemaining(c: Contest, now = Date.now()): string {
  const phase = contestStage(c, now),
    end = {
      upcoming: c.startsAt,
      submitting: c.submissionEnds,
      waiting: c.votingStarts,
      voting: c.votingEnds,
      reviewing: c.awardAt,
    }[phase];
  if (!end) return "";
  const minutes = Math.ceil((Date.parse(end) - now) / 60000);
  if (minutes <= 0) return "等待公布";
  return minutes >= 1440
    ? `${Math.floor(minutes / 1440)}天 ${Math.floor((minutes % 1440) / 60)}小时`
    : `${Math.floor(minutes / 60)}小时 ${minutes % 60}分`;
}
const reads = new Set([
  "contests.list",
  "contests.get",
  "contests.entries",
  "contests.profile",
  "contests.themes",
  "contests.year",
  "contests.admin",
]);
const cache = new Map<string, { until: number; result: ContestResult }>();
const pending = new Map<string, Promise<ContestResult>>();
let activeOwner = "",
  epoch = 0,
  revision = 0;
export function resetContestCache() {
  epoch++;
  revision++;
  activeOwner = "";
  cache.clear();
  pending.clear();
}
function stable(value: unknown): unknown {
  return Array.isArray(value)
    ? value.map(stable)
    : value && typeof value === "object"
      ? Object.fromEntries(
          Object.entries(value)
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([k, v]) => [k, stable(v)]),
        )
      : value;
}
const copy = (r: ContestResult): ContestResult => JSON.parse(JSON.stringify(r));
export async function contestRequest(
  owner: string,
  action: string,
  body: Record<string, unknown> = {},
  fresh = false,
): Promise<ContestResult> {
  if (activeOwner !== owner) {
    resetContestCache();
    activeOwner = owner;
  }
  const generation = epoch,
    reading = reads.has(action);
  if (!reading) {
    revision++;
    cache.clear();
    pending.clear();
  }
  const version = revision,
    key = JSON.stringify([owner, action, stable(body), version]);
  if (reading) {
    const saved = cache.get(key);
    if (!fresh && saved && saved.until > Date.now()) return copy(saved.result);
    const running = pending.get(key);
    if (running) return copy(await running);
  }
  const operation = (async () => {
    try {
      const result = {
        ...(await treeholeRequest(action, body)),
        receivedAt: Date.now(),
      } as ContestResult;
      if (generation !== epoch || owner !== activeOwner)
        throw Error("contest_account_changed");
      if (reading && version !== revision)
        throw Error("contest_stale_response");
      if (reading) {
        if (cache.size >= 60) cache.delete(cache.keys().next().value!);
        const ttl = [
          "contests.list",
          "contests.profile",
          "contests.year",
        ].includes(action)
          ? 120000
          : 15000;
        cache.set(key, { until: Date.now() + ttl, result: copy(result) });
      } else {
        revision++;
        cache.clear();
        pending.clear();
      }
      return result;
    } finally {
      if (reading) pending.delete(key);
    }
  })();
  if (reading) pending.set(key, operation);
  return copy(await operation);
}
