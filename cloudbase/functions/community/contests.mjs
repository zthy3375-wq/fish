// Validation shared by HTTP and native clients. Authorization stays in PostgreSQL.
export const contestActions = [
  "contests.image",
  "contests.list",
  "contests.get",
  "contests.entries",
  "contests.submit",
  "contests.withdraw",
  "contests.vote",
  "contests.profile",
  "contests.wear",
  "contests.year",
  "contests.themes",
  "contests.suggest",
  "contests.themevote",
  "contests.report",
  "contests.admin",
  "contests.save",
  "contests.manage",
  "contests.review",
];
export function sanitizeContest(
  action,
  input,
  { text, id, boolean, time, oneOf, fail },
) {
  const integer = (v, min, max) => {
    if (!Number.isInteger(v) || v < min || v > max) fail();
    return v;
  };
  const page = () => ({ offset: integer(input.offset ?? 0, 0, 100000) });
  if (action === "contests.list")
    return {
      ...page(),
      type: text(input.type ?? "", 0, 40),
      year: integer(input.year ?? 0, 0, 9999),
    };
  if (action === "contests.profile")
    return { memberId: id(input.memberId, true), ...page() };
  if (action === "contests.wear") return { awardId: id(input.awardId, true) };
  if (action === "contests.year")
    return { year: integer(input.year, 2020, 9999), ...page() };
  if (action === "contests.themes") return page();
  if (action === "contests.suggest")
    return { title: text(input.title, 3, 80), requestId: id(input.requestId) };
  if (action === "contests.themevote")
    return { themeId: id(input.themeId), enabled: boolean(input.enabled) };
  if (action === "contests.admin")
    return { contestId: id(input.contestId, true), ...page() };
  const out = {
    contestId: id(
      input.contestId,
      action === "contests.review" && ["theme", "merge"].includes(input.kind),
    ),
  };
  if (action === "contests.get") return out;
  if (action === "contests.image")
    return { ...out, entryId: id(input.entryId), imageId: id(input.imageId) };
  if (action === "contests.entries")
    return {
      ...out,
      ...page(),
      seed: id(input.seed),
      mine: input.mine === true,
      winnersOnly: input.winnersOnly === true,
    };
  if (action === "contests.withdraw")
    return { ...out, entryId: id(input.entryId) };
  if (action === "contests.vote")
    return {
      ...out,
      entryId: id(input.entryId),
      enabled: boolean(input.enabled),
    };
  if (action === "contests.report")
    return {
      ...out,
      entryId: id(input.entryId),
      reason: text(input.reason, 2, 300),
    };
  if (action === "contests.submit") {
    const images = input.images ?? [];
    if (
      !Array.isArray(images) ||
      images.length > 3 ||
      new Set(images).size !== images.length
    )
      fail();
    return {
      ...out,
      requestId: id(input.requestId),
      entryId: id(input.entryId, true),
      title: text(input.title, 1, 80),
      body: text(input.body ?? "", 0, 3000),
      images: images.map((x) => id(x)),
      postId: id(input.postId, true),
      share: input.share === true,
      agreed: input.agreed === true,
    };
  }
  if (action === "contests.save") {
    const formats = input.formats;
    if (!Array.isArray(formats) || !formats.length) fail();
    return {
      ...out,
      title: text(input.title, 2, 80),
      type: text(input.type, 1, 40),
      edition: text(input.edition ?? "", 0, 40),
      description: text(input.description, 1, 2000),
      rules: text(input.rules, 1, 4000),
      coverPostId: id(input.coverPostId, true),
      startsAt: time(input.startsAt),
      submissionEnds: time(input.submissionEnds),
      votingStarts: time(input.votingStarts),
      votingEnds: time(input.votingEnds),
      awardAt: time(input.awardAt),
      formats: [
        ...new Set(formats.map((x) => oneOf(x, ["text", "image", "mixed"]))),
      ],
      maxEntries: integer(input.maxEntries ?? 1, 1, 10),
      votesPerUser: integer(input.votesPerUser ?? 3, 1, 10),
      minEntries: integer(input.minEntries ?? 5, 1, 1000),
      minAccountHours: integer(input.minAccountHours ?? 24, 0, 8760),
      excellence: integer(input.excellence ?? 3, 0, 30),
      autoPublish: input.autoPublish === true,
    };
  }
  if (action === "contests.manage")
    return {
      ...out,
      operation: oneOf(input.operation, [
        "publish",
        "pause",
        "resume",
        "cancel",
        "announce",
        "solicitation",
      ]),
      reason: text(input.reason, 2, 300),
      enabled: input.enabled === true,
    };
  if (action === "contests.review")
    return {
      ...out,
      kind: oneOf(input.kind, ["entry", "vote", "theme", "merge"]),
      targetId: id(input.targetId),
      decision: oneOf(input.decision, [
        "approve",
        "remove",
        "valid",
        "exclude",
      ]),
      reason: text(input.reason, 2, 300),
      mergeId: id(input.mergeId, true),
    };
  fail();
}
