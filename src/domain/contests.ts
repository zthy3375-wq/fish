import {
  contestStage,
  type Contest,
  type ContestEntry,
} from "../services/contests";
export const contestDay = 86400000;
/** Campus calendar days in Asia/Shanghai. Never derives deadlines from the current minute. */
export function contestSchedule(days: number, now = Date.now()) {
  if (!Number.isInteger(days) || days < 1 || days > 365 || !Number.isFinite(now)) throw Error("invalid_duration");
  const local = new Date(now + 8 * 3600000);
  let start = Date.UTC(local.getUTCFullYear(),local.getUTCMonth(),local.getUTCDate(),4);
  if (days === 7 || days === 14) {
    start += ((8-local.getUTCDay())%7)*contestDay;
    if (start < now) start += 7*contestDay;
  } else if (start < now) start += contestDay;
  const award = start + (days-1)*contestDay + 8*3600000;
  const submission = days===1 ? start+4*3600000 : start+(days===7||days===14?days-2:Math.max(1,Math.floor(days*.7)))*contestDay;
  return {
    startsAt:new Date(start).toISOString(),
    submissionEnds:new Date(submission).toISOString(),
    votingStarts:new Date(submission).toISOString(),
    votingEnds:new Date(award-2*3600000).toISOString(),
    awardAt:new Date(award).toISOString(),
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
export function contestDate(iso: string, withYear=false) {
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year:withYear?"numeric":undefined,
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
