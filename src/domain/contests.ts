import {
  contestStage,
  type Contest,
  type ContestEntry,
} from "../services/contests";
export const contestDay = 86400000;
export function contestSchedule(days: number, start = Date.now()) {
  if (!Number.isFinite(days) || days < 1 || days > 365)
    throw Error("invalid_duration");
  const end = start + days * contestDay;
  return {
    startsAt: new Date(start).toISOString(),
    submissionEnds: new Date(start + (days * contestDay * 5) / 7).toISOString(),
    votingStarts: new Date(start + (days * contestDay * 5) / 7).toISOString(),
    votingEnds: new Date(start + (days * contestDay * 6) / 7).toISOString(),
    awardAt: new Date(end).toISOString(),
  };
}
export function beijingInput(iso: string) {
  const d = new Date(Date.parse(iso) + 8 * 3600000);
  return Number.isNaN(d.getTime()) ? "" : d.toISOString().slice(0, 16);
}
export function beijingISO(input: string) {
  const d = new Date(input + ":00+08:00");
  if (Number.isNaN(d.getTime())) throw Error("invalid_date");
  return d.toISOString();
}
export function contestDate(iso: string) {
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(iso));
}
export function primaryContestAction(
  c: Contest,
  mine: ContestEntry[],
  now = Date.now(),
) {
  const phase = contestStage(c, now);
  if (c.paused) return "比赛已暂停";
  if (phase === "submitting")
    return mine.some((e) => e.status === "approved")
      ? "查看我的作品"
      : "我要参赛";
  return (
    (
      {
        upcoming: "查看预告",
        waiting: "查看作品",
        voting: "参与投票",
        reviewing: "等待结果",
        ended: "查看结果",
        cancelled: "查看作品",
        draft: "查看草稿",
      } as Record<string, string>
    )[phase] || "查看比赛"
  );
}
export function confirmedVote(
  entry: ContestEntry,
  enabled: boolean,
  used: number,
  result: { entry?: ContestEntry; votesUsed?: number },
) {
  return {
    entry: result.entry || { ...entry, voted: enabled },
    votesUsed:
      result.votesUsed ??
      Math.max(0, used + (entry.voted === enabled ? 0 : enabled ? 1 : -1)),
  };
}
