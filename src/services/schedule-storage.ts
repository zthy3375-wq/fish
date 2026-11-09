import {correctLegacyCalendar} from "../domain/week-calibration";
import { Capacitor } from "@capacitor/core";
import { Preferences } from "@capacitor/preferences";
import { validateState, type ScheduleState } from "../domain/schedule";
// Keep the original address so v0.3 users are discovered; payload schema is versioned separately.
const KEY = "handan-campus.schedule.v1",
  BACKUP = KEY + ".before-v2";
export async function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const r = indexedDB.open("handan-campus", 1);
    r.onupgradeneeded = () => r.result.createObjectStore("schedule");
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
    r.onblocked = () => reject(Error("请关闭其他校园 App 页面后重试"));
  });
}
async function readRaw(key: string): Promise<unknown> {
  if (Capacitor.isNativePlatform()) {
    const { value } = await Preferences.get({ key });
    return value ? JSON.parse(value) : null;
  }
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const r = db.transaction("schedule").objectStore("schedule").get(key);
      r.onsuccess = () => resolve(r.result ?? null);
      r.onerror = () => reject(r.error);
    });
  } finally {
    db.close();
  }
}
export async function readSchedule(): Promise<ScheduleState | null> {
  const raw = await readRaw(KEY);
  if (!raw) return null;
  const state = validateState(raw);
  state.semesters=state.semesters.map(correctLegacyCalendar);
  if ((raw as { version: number }).version === 1) {
    await writeSchedule(state, raw);
    return validateState(await readRaw(KEY));
  }
  return state;
}
export async function readMigrationBackup() {
  return readRaw(BACKUP);
}
export async function writeSchedule(state: ScheduleState, legacy?: unknown) {
  const clean = validateState(state);
  if (Capacitor.isNativePlatform()) {
    if (legacy) {
      const current = await Preferences.get({ key: KEY });
      if (current.value && JSON.parse(current.value).version === 2) return;
    }
    if (legacy && !(await Preferences.get({ key: BACKUP })).value)
      await Preferences.set({ key: BACKUP, value: JSON.stringify(legacy) });
    await Preferences.set({ key: KEY, value: JSON.stringify(clean) });
    return;
  }
  const db = await database();
  try {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction("schedule", "readwrite"),
        store = tx.objectStore("schedule");
      if (legacy) {
        const current = store.get(KEY);
        current.onsuccess = () => {
          if (current.result?.version === 2) return;
          const previous = store.get(BACKUP);
          previous.onsuccess = () => {
            if (!previous.result) store.put(legacy, BACKUP);
            store.put(clean, KEY);
          };
        };
      } else store.put(clean, KEY);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? Error("保存被中止"));
    });
  } finally {
    db.close();
  }
}
