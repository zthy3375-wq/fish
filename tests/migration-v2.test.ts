import "fake-indexeddb/auto";
import { describe, it, expect } from "vitest";
import {
  defaultState,
  newArrangement,
  validateState,
  restoreBackup,
  type ManagedCourse,
} from "../src/domain/schedule";
import {
  database,
  readSchedule,
  readMigrationBackup,
} from "../src/services/schedule-storage";
function legacy() {
  const next = defaultState();
  const c: ManagedCourse = {
    id: "existing",
    semesterId: next.activeSemesterId,
    name: "已保存课程",
    teacher: "原教师",
    notes: "原备注",
    color: "purple",
    arrangements: [{ ...newArrangement(18), start: "08:10", end: "09:40" }],
  };
  const raw: any = JSON.parse(
    JSON.stringify({ ...next, version: 1, courses: [c] }),
  );
  delete raw.timeTables;
  delete raw.semesters[0].timeTableId;
  delete raw.courses[0].arrangements[0].timeMode;
  return raw;
}
describe("v0.3 → v0.3.1 migration", () => {
  it("preserves course IDs, arrangements, explicit times, semester and reminder settings", () => {
    const raw = legacy(),
      before = JSON.stringify(raw);
    raw.reminders = { enabled: true, minutes: 15 };
    const migrated = validateState(raw);
    expect(migrated.version).toBe(2);
    expect(migrated.courses[0].arrangements[0]).toMatchObject({
      start: "08:10",
      end: "09:40",
      timeMode: "custom",
    });
    expect(migrated.courses[0].id).toBe("existing");
    expect(migrated.reminders).toEqual(raw.reminders);
    expect(migrated.semesters[0].weekStartDate).toBe(
      raw.semesters[0].weekStartDate,
    );
    expect(migrated.timeTables).toHaveLength(1);
    expect(before).not.toContain("timeTableId");
    expect(raw.courses[0].arrangements[0].timeMode).toBeUndefined();
  });
  it("restores old backups and produces idempotent v2 snapshots with independent per-semester time references", () => {
    const raw = legacy();
    raw.semesters.push({ ...raw.semesters[0], id: "another" });
    const migrated = restoreBackup(
      JSON.stringify({ format: "handan-campus-schedule", data: raw }),
    );
    expect(migrated.timeTables).toHaveLength(2);
    expect(migrated.semesters[0].timeTableId).not.toBe(
      migrated.semesters[1].timeTableId,
    );
    expect(validateState(migrated)).toEqual(migrated);
  });
  it("persists migrated state and an untouched rollback snapshot in IndexedDB", async () => {
    const raw = legacy(),
      db = await database();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction("schedule", "readwrite");
      tx.objectStore("schedule").put(raw, "handan-campus.schedule.v1");
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    db.close();
    const migrated = await readSchedule();
    expect(migrated?.version).toBe(2);
    expect(await readMigrationBackup()).toEqual(raw);
    const reopened = await readSchedule();
    expect(reopened).toEqual(migrated);
  });
});

it("never lets a delayed v1 migration overwrite a newer v2 edit", async () => {
  const { writeSchedule } = await import("../src/services/schedule-storage");
  const old = legacy(),
    current = validateState(old);
  current.courses[0].name = "升级后的编辑";
  await writeSchedule(current);
  await writeSchedule(validateState(old), old);
  expect((await readSchedule())?.courses[0].name).toBe("升级后的编辑");
});
