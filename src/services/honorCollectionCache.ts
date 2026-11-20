import type { CollectionProfile } from "../domain/honorCollection";
import type { TreeholeResult } from "./treehole";

const profiles = new Map<string, { at: number; data: CollectionProfile }>();
const pending = new Map<string, Promise<CollectionProfile>>();
let generation = 0;

export function clearHonorCollectionCache() {
  generation++;
  profiles.clear();
  pending.clear();
}

export function getHonorCollection(
  viewer: string,
  member: string,
  request: (action: string, body?: Record<string, unknown>) => Promise<TreeholeResult>,
  fresh = false,
) {
  const key = viewer + ":" + member;
  const saved = profiles.get(key);
  if (!fresh && saved && Date.now() - saved.at < 120000) return Promise.resolve(saved.data);
  const running = pending.get(key);
  if (running && !fresh) return running;
  const issued = generation;
  const operation = request("collection.profile", { memberId: member }).then((r) => {
    if (generation !== issued) throw Error("session_expired");
    if (!r.collection || r.collection.id !== member) throw Error("invalid_response");
    if (pending.get(key) === operation) {
      if (profiles.size >= 16) profiles.delete(profiles.keys().next().value!);
      profiles.set(key, { at: Date.now(), data: r.collection });
    }
    return r.collection;
  }).finally(() => {
    if (pending.get(key) === operation) pending.delete(key);
  });
  pending.set(key, operation);
  return operation;
}
