import { describe, it, expect } from "vitest";
import {
  AcademicConnectionController,
  normalizeAuthorizedAcademicData,
  selectAcademicData,
  type AuthorizedAcademicConnector,
} from "../src/services/academic-connection";
function payload() {
  return {
    semester: {
      id: "2026-fall",
      academicYear: "2026–2027",
      season: "秋季",
      startDate: "2026-09-07",
      weekStartDate: "2026-09-07",
      weekCount: 18,
    },
    courses: [
      {
        id: "mine",
        name: "数学",
        teacher: "老师",
        room: "A102",
        day: 1,
        start: "08:00",
        end: "09:35",
        period: "1-2节",
        weeks: [1, 2],
        color: "blue",
      },
    ],
    grades: [
      {
        name: "数学",
        score: 92,
        credit: 3,
        term: "2026–2027 秋季",
        kind: "必修",
      },
    ],
    exams: [
      {
        name: "数学",
        date: "2027-01-11",
        time: "09:00–11:00",
        room: "A102",
        seat: "12",
      },
    ],
  };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}
const connectorFor = (
  fetch = async (): Promise<unknown> => payload(),
): AuthorizedAcademicConnector => ({
  id: "review-school",
  displayName: "Review School",
  beginOfficialAuthorization: async () => {},
  getSessionStatus: async () => "connected",
  fetchMyAcademicData: fetch,
  disconnect: async () => {},
});
describe("review: academic record validation", () => {
  it.each(["", "   "])("rejects empty identifiers and names: %j", (value) => {
    const p = payload();
    p.courses[0].id = value;
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow();
    p.courses[0].id = "valid";
    p.courses[0].name = value;
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow();
  });
  it("rejects duplicate IDs and weeks outside the semester, including empty weeks", () => {
    const p = payload();
    p.courses.push({ ...p.courses[0] });
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow(
      "编号重复",
    );
    p.courses.pop();
    p.courses[0].weeks = [19];
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow(
      "教学周",
    );
    p.courses[0].weeks = [];
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow(
      "教学周",
    );
  });
  it("rejects calendar-overflow dates and non-finite grades", () => {
    const p = payload();
    p.exams[0].date = "2027-02-30";
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow(
      "日期不存在",
    );
    p.exams[0].date = "2027-02-28";
    p.grades[0].score = NaN;
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow();
  });
  it("does not convert an arbitrary color string into arbitrary CSS classes", () => {
    const p = payload();
    p.courses[0].color = "hidden absolute";
    expect(normalizeAuthorizedAcademicData(p, "school").courses[0].color).toBe(
      "blue",
    );
  });
  it("bounds response sizes and rejects unsafe provider IDs", () => {
    const p = payload();
    p.courses = Array.from({ length: 2001 }, () => p.courses[0]);
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow("数量");
    expect(() =>
      normalizeAuthorizedAcademicData(payload(), "https://secret.example"),
    ).toThrow("连接器");
  });
  it("validates optional school time slots and discards unknown secret fields", () => {
    const p = {
      ...payload(),
      timeTable: {
        id: "school-times",
        name: "学校作息",
        token: "never-keep",
        slots: [
          { number: 1, start: "09:00", end: "09:45", cookie: "never-keep" },
        ],
      },
    };
    const result = normalizeAuthorizedAcademicData(p, "school");
    expect(result.timeTable?.slots[0]).toEqual({
      number: 1,
      start: "09:00",
      end: "09:45",
    });
    expect(JSON.stringify(result)).not.toContain("never-keep");
    p.timeTable.slots[0].end = "08:00";
    expect(() => normalizeAuthorizedAcademicData(p, "school")).toThrow();
  });
});
describe("review: asynchronous session lifecycle", () => {
  it("never resurrects private records when a refresh finishes after disconnect", async () => {
    const fetched = deferred<unknown>(),
      started = deferred<void>();
    const session = new AcademicConnectionController(
      connectorFor(() => {
        started.resolve();
        return fetched.promise;
      }),
    );
    await session.connect();
    const events: (string | null)[] = [];
    session.subscribe((s) => events.push(s?.courses[0].name ?? null));
    const refresh = session.refresh();
    await started.promise;
    await session.disconnect();
    fetched.resolve(payload());
    expect(await refresh).toBeNull();
    expect(session.snapshot).toBeNull();
    expect(session.state.phase).toBe("disconnected");
    expect(events.every((x) => x === null)).toBe(true);
  });
  it("ignores authorization results after cancellation", async () => {
    const auth = deferred<void>(),
      c = connectorFor();
    c.beginOfficialAuthorization = () => auth.promise;
    const session = new AcademicConnectionController(c);
    const pending = session.connect();
    await session.disconnect();
    auth.resolve();
    expect(await pending).toBe(false);
    expect(session.state.phase).toBe("disconnected");
  });
  it("clears local records immediately even when remote revocation fails without leaking raw errors", async () => {
    const c = connectorFor();
    c.disconnect = async () => {
      throw Error("access_token=SECRET cookie=PRIVATE");
    };
    const session = new AcademicConnectionController(c);
    await session.connect();
    await session.refresh();
    const result = session.disconnect();
    expect(session.snapshot).toBeNull();
    expect(await result).toBe(false);
    expect(session.state.error).not.toContain("SECRET");
    expect(session.state.error).toContain("本机教务数据已清除");
  });
  it("rejects fetched records if the session expires during the fetch", async () => {
    const data = deferred<unknown>(),
      started = deferred<void>();
    let connected = true;
    const c = connectorFor(() => {
      started.resolve();
      return data.promise;
    });
    c.getSessionStatus = async () => (connected ? "connected" : "expired");
    const session = new AcademicConnectionController(c);
    await session.connect();
    const pending = session.refresh();
    await started.promise;
    connected = false;
    data.resolve(payload());
    expect(await pending).toBeNull();
    expect(session.state.phase).toBe("expired");
  });
  it("deduplicates foreground and connection-page refreshes", async () => {
    const data = deferred<unknown>(),
      started = deferred<void>();
    let calls = 0;
    const session = new AcademicConnectionController(
      connectorFor(() => {
        calls++;
        started.resolve();
        return data.promise;
      }),
    );
    await session.connect();
    const first = session.refresh(),
      second = session.refresh();
    expect(first).toBe(second);
    await started.promise;
    data.resolve(payload());
    expect((await first)?.courses).toHaveLength(1);
    expect(await second).toEqual(await first);
    expect(calls).toBe(1);
  });
  it("notifies all subscribers on expiry independently of the initiating page", async () => {
    let status: "connected" | "expired" = "connected";
    const c = connectorFor();
    c.getSessionStatus = async () => status;
    const session = new AcademicConnectionController(c);
    let current: ReturnType<typeof normalizeAuthorizedAcademicData> | null =
      null;
    const stop = session.subscribe((snapshot) => (current = snapshot));
    await session.connect();
    await session.refresh();
    expect(current).not.toBeNull();
    status = "expired";
    await session.refresh();
    expect(current).toBeNull();
    expect(session.state.syncedAt).toBeNull();
    stop();
  });
  it("returns isolated state and snapshot objects and hides provider error details", async () => {
    const c = connectorFor();
    const session = new AcademicConnectionController(c);
    await session.connect();
    await session.refresh();
    session.snapshot!.courses[0].name = "tampered";
    const state = session.state as { phase: string };
    state.phase = "error";
    expect(session.snapshot!.courses[0].name).toBe("数学");
    expect(session.state.phase).toBe("ready");
    c.fetchMyAcademicData = async () => {
      throw Error("Authorization: SECRET");
    };
    await session.refresh();
    expect(session.state.error).not.toContain("SECRET");
    expect(session.snapshot).toBeNull();
  });
  it("waits for revocation before beginning a new authorization", async () => {
    let authorizations = 0;
    const revoked = deferred<void>(),
      c = connectorFor();
    c.beginOfficialAuthorization = async () => {
      authorizations++;
    };
    c.disconnect = () => revoked.promise;
    const session = new AcademicConnectionController(c);
    await session.connect();
    const logout = session.disconnect(),
      login = session.connect();
    expect(authorizations).toBe(1);
    revoked.resolve();
    await logout;
    expect(await login).toBe(true);
    expect(authorizations).toBe(2);
  });
  it("requires an explicit official view and restores the unchanged local source on expiry", () => {
    const local = {
      courses: [],
      grades: [],
      exams: [],
      source: "personal" as const,
    };
    const snapshot = normalizeAuthorizedAcademicData(payload(), "school");
    expect(selectAcademicData(local, snapshot, false)).toBe(local);
    expect(selectAcademicData(local, snapshot, true).source).toBe("official");
    expect(selectAcademicData(local, null, true)).toBe(local);
    expect(local.courses).toEqual([]);
  });
});
