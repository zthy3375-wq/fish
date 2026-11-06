<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from "vue";
import {
  ShieldCheck,
  ExternalLink,
  RefreshCw,
  LogIn,
  LogOut,
} from "lucide-vue-next";
import {
  getAuthorizedAcademicConnector,
  getAcademicConnectionController,
} from "../services/authorized-connector-registry";
const emit = defineEmits<{ synced: []; disconnected: [] }>();
const provider = getAuthorizedAcademicConnector(),
  controller = getAcademicConnectionController();
const phase = ref(controller?.state.phase ?? "disconnected"),
  error = ref(""),
  syncedAt = ref<string | null>(null),
  hasSnapshot = ref(false),
  disconnecting = ref(false);
const busy = computed(
  () =>
    phase.value === "authorizing" ||
    phase.value === "syncing" ||
    disconnecting.value,
);
const status = computed(() =>
  !provider
    ? "未接入学校授权接口"
    : (
        {
          disconnected: "尚未绑定",
          authorizing: "正在等待学校认证",
          ready: "已获得学校授权",
          syncing: "正在同步本人教务数据",
          expired: "学校登录状态已失效",
          error: "连接发生错误",
        } as Record<string, string>
      )[phase.value],
);
let alive = true;
const unsubscribe = controller?.subscribe((snapshot, state) => {
  phase.value = state.phase;
  error.value = state.error ?? "";
  syncedAt.value = state.syncedAt;
  hasSnapshot.value = !!snapshot;
});
async function refresh() {
  if (!controller || busy.value) return;
  const snapshot = await controller.refresh();
  if (alive && snapshot) emit("synced");
}
async function connect() {
  if (!controller || busy.value) return;
  if (await controller.connect()) await refresh();
}
async function disconnect() {
  if (!controller || disconnecting.value) return;
  disconnecting.value = true;
  try {
    await controller.disconnect();
    if (alive) emit("disconnected");
  } finally {
    disconnecting.value = false;
  }
}
function resume() {
  if (
    controller &&
    !busy.value &&
    document.visibilityState === "visible" &&
    phase.value === "ready"
  )
    void controller.refresh();
}
onMounted(() => document.addEventListener("visibilitychange", resume));
onUnmounted(() => {
  alive = false;
  unsubscribe?.();
  document.removeEventListener("visibilitychange", resume);
});
</script>
<template>
  <section class="academic-connection">
    <span class="icon-tile"><ShieldCheck :size="26" /></span>
    <h2>教务账号连接</h2>
    <p class="muted">
      仅通过学校允许的方式读取学生本人数据，不在 fish 输入学校密码。
    </p>
    <div class="connection-status" role="status">
      <strong>{{ status }}</strong
      ><small v-if="syncedAt"
        >上次同步：{{
          new Date(syncedAt).toLocaleString("zh-CN", {
            timeZone: "Asia/Shanghai",
          })
        }}（北京时间）</small
      ><small v-else>个人课表与演示数据仍可独立使用</small>
    </div>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <template v-if="provider"
      ><p class="muted">
        授权服务：{{ provider.displayName }}。认证由学校自己的页面处理。
      </p>
      <div class="connection-actions">
        <button
          v-if="['disconnected', 'expired', 'error'].includes(phase)"
          class="primary"
          :disabled="busy"
          @click="connect"
        >
          <LogIn :size="17" />使用学校官方认证</button
        ><button
          v-if="phase === 'ready' || phase === 'syncing'"
          class="secondary"
          :disabled="busy"
          @click="refresh"
        >
          <RefreshCw :size="17" />同步我的教务数据</button
        ><button
          v-if="hasSnapshot"
          class="secondary"
          :disabled="busy"
          @click="emit('synced')"
        >
          查看本次授权数据</button
        ><button
          v-if="phase !== 'disconnected'"
          class="text-button"
          :disabled="disconnecting"
          @click="disconnect"
        >
          <LogOut :size="17" />{{
            phase === "authorizing" ? "取消连接" : "断开本机连接并撤销授权"
          }}
        </button>
      </div></template
    >
    <p v-else class="inline-note">
      当前没有注册真实学校连接器，不能登录或自动同步邯郸学院数据。下方仅是学校官方网页入口，不代表已完成账号绑定。
    </p>
    <a
      class="official-link"
      href="https://jwgl.hdc.edu.cn/xtgl/login_slogin.html"
      target="_blank"
      rel="noopener noreferrer"
      ><span
        ><strong>打开邯郸学院教务平台</strong
        ><small>账号、密码和验证码均由学校网页处理</small></span
      ><ExternalLink :size="19"
    /></a>
    <p class="footnote">
      框架不读取学校
      Cookie、不代填密码、不绕过认证。授权数据仅在本次运行内存中显示，尚不支持离线缓存。
    </p>
  </section>
</template>
<style scoped>
.academic-connection {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.academic-connection h2 {
  margin: 0;
  font-size: 20px;
}
.academic-connection p {
  line-height: 1.65;
  margin: 0;
}
.connection-status {
  border: 1px solid var(--color-border);
  background: var(--color-surface);
  border-radius: 14px;
  padding: 15px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.connection-status small {
  color: var(--color-muted);
}
.connection-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}
.connection-actions button {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 11px;
  min-height: 44px;
}
</style>
