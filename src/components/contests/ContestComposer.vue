<script setup lang="ts">
import { ref, computed, watch, onMounted, onBeforeUnmount } from "vue";
import {
  contestRequest,
  type Contest,
  type ContestEntry,
} from "../../services/contests";
import {
  treeholeRequest,
  treeholeError,
  type TreeholeImage,
  type TreeholePost,
} from "../../services/treehole";
import {
  readDraftRecord,
  writeDraftRecord,
  deleteDraftRecord,
  prepareTreeholeImage,
  type DraftImage,
} from "../../services/treeholeDrafts";
import ContestPostPicker from "./ContestPostPicker.vue";
import ContestDialog from "./ContestDialog.vue";
const props = defineProps<{
  owner: string;
  contest: Contest;
  entry?: ContestEntry;
}>();
const emit = defineEmits<{ submitted: [entry: ContestEntry]; close: [] }>();
interface Draft {
  title: string;
  body: string;
  postId: string | null;
  linked: boolean;
  kept: TreeholeImage[];
  photos: DraftImage[];
  share: boolean;
  agreed: boolean;
  requestId: string;
  baseVersion?: number;
  lastSent?: Record<string, unknown>;
  savedAt: number;
}
const fresh = (): Draft => ({
  title: props.entry?.title || "",
  body: props.entry?.body || "",
  postId: props.entry?.postId || null,
  linked: !!props.entry?.linked,
  kept: props.entry?.images || [],
  photos: [],
  share: false,
  agreed: false,
  requestId: crypto.randomUUID(),
  baseVersion: props.entry?.version,
  savedAt: Date.now(),
});
const draft = ref<Draft>(fresh()),
  candidate = ref<Draft>(),
  ready = ref(false),
  busy = ref(false),
  error = ref(""),
  draftStatus = ref(""),
  preview = ref(false),
  leave = ref(false);
const statuses = ref<Record<string, string>>({});
const key = `contest-v2:${props.owner}:${props.contest.id}:${props.entry?.id || "new"}`;
let alive = true,
  active = true,
  timer: ReturnType<typeof setTimeout>,
  queue = Promise.resolve(true);
const composition = ref(false);
const dirty = computed(
  () =>
    !!(
      draft.value.title ||
      draft.value.body ||
      draft.value.kept.length ||
      draft.value.photos.length
    ),
);
const uncertain = computed(() => !!draft.value.lastSent);
const canText = computed(() =>
  props.contest.formats.some((x) => ["text", "mixed"].includes(x)),
);
const canImage = computed(() =>
  props.contest.formats.some((x) => ["image", "mixed"].includes(x)),
);
const completed = computed(
  () => draft.value.photos.filter((p) => p.remote).length,
);
async function persist() {
  if (!alive || !ready.value || !active) return false;
  const snapshot = JSON.parse(
    JSON.stringify({ ...draft.value, savedAt: Date.now() }),
  );
  draftStatus.value = "正在保存草稿…";
  queue = queue.then(async () => {
    try {
      if (dirty.value) await writeDraftRecord(key, snapshot);
      else await deleteDraftRecord(key);
      if (alive) draftStatus.value = "草稿已保存在本机";
      return true;
    } catch {
      if (alive) draftStatus.value = "草稿保存失败，请保留当前页面后重试";
      return false;
    }
  });
  return queue;
}
watch(
  draft,
  () => {
    if (!ready.value || !active || candidate.value || composition.value) return;
    clearTimeout(timer);
    timer = setTimeout(() => void persist(), 220);
  },
  { deep: true },
);
function onVisibility() {
  clearTimeout(timer);
  void persist();
}
onMounted(async () => {
  document.addEventListener("visibilitychange", onVisibility);
  window.addEventListener("pagehide", onVisibility);
  try {
    const saved = await readDraftRecord<Draft>(key);
    if (alive && saved && Date.now() - saved.savedAt < 30 * 86400000)
      candidate.value = saved;
  } catch {
    draftStatus.value = "草稿读取失败，可以继续编辑或稍后重试";
  } finally {
    ready.value = true;
  }
});
onBeforeUnmount(() => {
  clearTimeout(timer);
  void persist();
  alive = false;
  document.removeEventListener("visibilitychange", onVisibility);
  window.removeEventListener("pagehide", onVisibility);
});
function restore() {
  if (!candidate.value) return;
  draft.value = {
    ...candidate.value,
    baseVersion: props.entry?.version,
    lastSent:
      candidate.value.baseVersion === props.entry?.version
        ? candidate.value.lastSent
        : undefined,
  };
  candidate.value = undefined;
}
async function discardSaved() {
  candidate.value = undefined;
  await deleteDraftRecord(key).catch(() => {
    draftStatus.value = "旧草稿清理失败，请重试";
  });
}
async function pick(event: Event) {
  const input = event.target as HTMLInputElement;
  if (busy.value || uncertain.value) return;
  busy.value = true;
  error.value = "";
  try {
    for (const f of Array.from(input.files || []).slice(
      0,
      3 - draft.value.kept.length - draft.value.photos.length,
    ))
      draft.value.photos.push(await prepareTreeholeImage(f));
    await persist();
  } catch (e) {
    error.value = treeholeError(e);
  } finally {
    input.value = "";
    busy.value = false;
  }
}
async function upload(photo: DraftImage) {
  if (photo.remote) return;
  statuses.value[photo.id] = "上传中…";
  try {
    photo.remote = (
      await treeholeRequest("media.upload", {
        data: photo.data,
        requestId: photo.id,
      })
    ).image;
    if (!photo.remote) throw Error("image_unavailable");
    statuses.value[photo.id] = "已上传";
    await persist();
  } catch (e) {
    statuses.value[photo.id] = "上传失败，可重试";
    throw e;
  }
}
async function retryPhoto(photo: DraftImage) {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    await upload(photo);
  } catch (e) {
    error.value = treeholeError(e);
  } finally {
    busy.value = false;
  }
}
function removePhoto(photo: DraftImage) {
  draft.value.photos = draft.value.photos.filter((p) => p.id !== photo.id);
  if (photo.remote)
    void treeholeRequest("media.discard", { imageId: photo.remote.id }).catch(
      () => {},
    );
}
function choose(post: TreeholePost) {
  if (busy.value || uncertain.value) return;
  draft.value = {
    ...draft.value,
    postId: post.id,
    linked: true,
    title:
      draft.value.title ||
      post.title ||
      Array.from(post.body).slice(0, 40).join("") ||
      "图片作品",
    body: post.body,
    kept: post.images || [],
    photos: [],
    share: false,
  };
}
function validation() {
  const d = draft.value;
  if (!d.title.trim()) return "给作品起个名字，方便同学们记住它。";
  const images = d.kept.length + d.photos.length;
  const kind = images ? (d.body.trim() ? "mixed" : "image") : "text";
  if (!props.contest.formats.includes(kind))
    return "作品内容与本场投稿类型不符，请调整图片或文字。";
  if (!images && !d.body.trim()) return "请写下作品内容。";
  if (!d.agreed) return "请先阅读并同意参赛规则。";
  return "";
}
function showPreview() {
  error.value = validation();
  if (!error.value) preview.value = true;
}
async function submit() {
  if (busy.value) return;
  error.value = validation();
  if (error.value) return;
  busy.value = true;
  try {
    for (const photo of draft.value.photos) await upload(photo);
    if (!alive) return;
    const payload = draft.value.lastSent || {
      contestId: props.contest.id,
      entryId: props.entry?.id || null,
      requestId: draft.value.requestId,
      title: draft.value.title,
      body: draft.value.body,
      postId: draft.value.postId,
      linkPost: draft.value.linked,
      share: draft.value.share,
      images: [
        ...draft.value.kept.map((i) => i.id),
        ...draft.value.photos.map((p) => p.remote!.id),
      ],
      agreed: draft.value.agreed,
      expectedVersion: draft.value.baseVersion,
    };
    draft.value.lastSent = payload;
    await persist();
    const result = await contestRequest(
      props.owner,
      "contests.submit",
      payload,
    );
    if (!result.entry) throw Error("invalid_response");
    active = false;
    clearTimeout(timer);
    await queue;
    await deleteDraftRecord(key, draft.value.requestId).catch(() => {});
    if (alive) emit("submitted", result.entry);
  } catch (e) {
    if (alive) {
      error.value = treeholeError(e);
      if (
        /contest_conflict|invalid_request|contest_format|contest_closed|image_unavailable|contest_entry_limit/.test(
          (e as Error).message,
        )
      )
        draft.value.lastSent = undefined;
      if (draft.value.lastSent)
        error.value += " 如遇超时，重试会确认同一次投稿，不会重复发布。";
      await persist();
    }
  } finally {
    if (alive) busy.value = false;
  }
}
async function checkStatus() {
  if (busy.value) return;
  busy.value = true;
  try {
    const r = await contestRequest(
      props.owner,
      "contests.entries",
      { contestId: props.contest.id, seed: crypto.randomUUID(), mine: true },
      true,
    );
    if (!alive) return;
    const found = r.entries?.find(
      (e) =>
        e.status === "approved" &&
        e.title === draft.value.title &&
        e.body === draft.value.body &&
        (!props.entry || e.id === props.entry.id) &&
        e.postId === (draft.value.lastSent?.postId || null) &&
        JSON.stringify(e.images.map((i) => i.id).sort()) ===
          JSON.stringify(
            ((draft.value.lastSent?.images as string[]) || []).slice().sort(),
          ),
    );
    if (found) {
      active = false;
      await queue;
      await deleteDraftRecord(key, draft.value.requestId);
      emit("submitted", found);
    } else {
      draft.value.lastSent = undefined;
      draft.value.requestId = crypto.randomUUID();
      error.value = "尚未找到已提交作品，可以继续编辑或重试。";
    }
  } catch (e) {
    error.value = treeholeError(e);
  } finally {
    busy.value = false;
  }
}
function requestBack() {
  if (busy.value) return true;
  if (preview.value) {
    preview.value = false;
    return true;
  }
  if (leave.value) {
    leave.value = false;
    return true;
  }
  if (dirty.value) {
    leave.value = true;
    return true;
  }
  emit("close");
  return true;
}
async function saveAndLeave() {
  if (!(await persist())) {
    error.value = "草稿尚未保存，请留在此页重试。";
    return;
  }
  leave.value = false;
  emit("close");
}
defineExpose({ requestBack });
</script>
<template>
  <section>
    <p class="ct-subtitle">
      {{ contest.title }} · {{ entry ? "修改你的作品" : "留下你的校园作品" }}
    </p>
    <p v-if="error" role="alert" class="ct-error">{{ error }}</p>
    <p v-if="!ready" role="status">正在读取草稿…</p>
    <div v-if="candidate" class="ct-schedule">
      <h3>有一份未完成的本机草稿</h3>
      <p v-if="entry && candidate.baseVersion !== entry.version">
        服务器作品已有更新。恢复将用草稿内容编辑当前最新版本，请预览确认后再提交。
      </p>
      <div class="ct-pair">
        <button class="ct-secondary" @click="restore">恢复草稿</button
        ><button class="ct-link" @click="discardSaved">使用当前作品</button>
      </div>
    </div>
    <template v-else
      ><form
        v-if="!preview"
        class="ct-form"
        novalidate
        @submit.prevent="showPreview"
        @compositionstart="composition = true"
        @compositionend="
          composition = false;
          persist();
        "
      >
        <fieldset
          :disabled="busy || !ready || uncertain"
          style="display: grid; gap: 20px"
        >
          <label
            >作品名称<input
              v-model="draft.title"
              maxlength="80"
              placeholder="给这份作品起个名字" /></label
          ><label v-if="canText"
            >作品内容<textarea
              style="resize: none"
              v-model="draft.body"
              :readonly="draft.linked"
              rows="7"
              maxlength="3000"
              placeholder="从一句话开始，写下你的故事。"
            />
          </label>
          <div v-if="canImage">
            <div class="ct-upload-grid">
              <figure v-for="image in draft.kept" :key="image.id">
                <img :src="image.url || undefined" alt="已有作品图片" /><button
                  v-if="!draft.linked"
                  type="button"
                  @click="
                    draft.kept = draft.kept.filter((i) => i.id !== image.id)
                  "
                >
                  移除图片
                </button>
              </figure>
              <figure v-for="photo in draft.photos" :key="photo.id">
                <img
                  :src="'data:image/jpeg;base64,' + photo.data"
                  alt="待投稿图片"
                />
                <figcaption>
                  {{
                    statuses[photo.id] || (photo.remote ? "已上传" : "等待上传")
                  }}
                </figcaption>
                <button type="button" @click="removePhoto(photo)">
                  移除图片</button
                ><button
                  v-if="statuses[photo.id]?.startsWith('上传失败')"
                  type="button"
                  @click="retryPhoto(photo)"
                >
                  重试上传
                </button>
              </figure>
            </div>
            <label
              v-if="
                !draft.linked && draft.kept.length + draft.photos.length < 3
              "
              class="ct-upload"
              >＋ 添加图片（最多3张）<input
                type="file"
                accept="image/*"
                multiple
                @change="pick"
            /></label>
          </div>
          <details>
            <summary>选择已有帖子或同步到社区</summary>
            <ContestPostPicker @choose="choose" />
            <div v-if="draft.linked">
              <p class="ct-subtitle">
                已关联自己的公开帖子。图片与文字将作为本次参赛作品。
              </p>
              <button
                type="button"
                class="ct-link"
                @click="
                  draft.linked = false;
                  if (!canText) draft.body = '';
                  draft.postId = null;
                  draft.kept = [];
                "
              >
                改为直接投稿
              </button>
            </div>
            <label v-else class="ct-check"
              ><input
                type="checkbox"
                v-model="draft.share"
              />同时发布到社区</label
            >
          </details>
          <details>
            <summary>参赛规则</summary>
            <p class="ct-pre ct-subtitle">{{ contest.rules }}</p>
          </details>
          <label class="ct-check"
            ><input
              type="checkbox"
              v-model="draft.agreed"
            />我已阅读规则，作品符合投稿要求</label
          >
        </fieldset>
        <button class="ct-primary" :disabled="busy || !ready || uncertain">
          预览作品
        </button>
      </form>
      <div v-else class="ct-work-detail">
        <div class="ct-upload-grid">
          <img
            v-for="image in draft.kept"
            :key="image.id"
            :src="image.url || undefined"
            alt="作品预览"
          /><img
            v-for="photo in draft.photos"
            :key="photo.id"
            :src="'data:image/jpeg;base64,' + photo.data"
            alt="作品预览"
          />
        </div>
        <h1>{{ draft.title }}</h1>
        <p class="ct-work-body">{{ draft.body }}</p>
        <button class="ct-primary" :disabled="busy" @click="submit">
          {{
            busy
              ? "正在确认…"
              : uncertain
                ? "重试并确认投稿"
                : entry
                  ? "保存作品"
                  : "确认参赛"
          }}</button
        ><button
          class="ct-link"
          :disabled="busy || uncertain"
          @click="preview = false"
        >
          返回编辑
        </button>
      </div>
      <div v-if="uncertain && !preview" class="ct-section">
        <p class="ct-subtitle">上次提交的结果尚未确认，先核对后再修改。</p>
        <div class="ct-pair">
          <button class="ct-primary" :disabled="busy" @click="submit">
            重试并确认投稿</button
          ><button class="ct-secondary" :disabled="busy" @click="checkStatus">
            检查提交状态
          </button>
        </div>
      </div>
      <progress
        v-if="busy && draft.photos.length"
        :value="completed"
        :max="draft.photos.length"
        :aria-label="`已上传${completed}/${draft.photos.length}张`"
      />
      <p class="ct-subtitle" role="status">
        {{ draftStatus
        }}<button
          v-if="draftStatus.includes('失败')"
          class="ct-link"
          @click="persist"
        >
          重试保存
        </button>
      </p></template
    ><ContestDialog
      :open="leave"
      title="保存草稿并离开？"
      confirm="保存并离开"
      @cancel="leave = false"
      @confirm="saveAndLeave"
      ><p>
        这份作品尚未提交。草稿会保存在当前账号的本机空间，下次可以继续编辑。
      </p></ContestDialog
    >
  </section>
</template>
