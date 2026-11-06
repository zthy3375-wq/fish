<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import {
  ArrowLeft,
  ExternalLink,
  ShieldCheck,
  ScanSearch,
  Copy,
  Download,
  Trash2,
  FlaskConical,
} from "lucide-vue-next";
import {
  diagnosticAvailability,
  openDiagnosticBrowser,
  checkDiagnosticPage,
  reportJSON,
  saveDiagnosticReport,
  loadDiagnosticReport,
  deleteDiagnosticReport,
  exportDiagnosticReport,
  type DiagnosticReport,
  openSchoolWindow,
  createSchoolPageReport,
} from "../services/academic-diagnostics";
import { runDiagnosticSelfTest } from "../services/diagnostic-self-test";
import {
  schedule,
  semester as currentSemester,
  changeSchedule,
} from "../composables/schedule";
import { tableForSemester } from "../domain/schedule";
import {
  previewZhengfangTimetable,
  type ZhengfangPreview,
} from "../services/academic-adapters/zhengfang-timetable";
import { saveSchoolPagePreview } from "../services/school-page-import";
const coursePreview = ref<ZhengfangPreview | null>(null),
  confirmedTimes = ref(false);
const emit = defineEmits<{ back: []; saved: [] }>();
const available = ref(false),
  consent = ref(false),
  reviewed = ref(false),
  opened = ref(false),
  busy = ref(false);
const report = ref<DiagnosticReport | null>(null),
  message = ref(""),
  error = ref("");
let generation = 0;
const json = computed(() => (report.value ? reportJSON(report.value) : ""));
const fixture = computed(
  () => report.value?.source === "synthetic-offline-self-test",
);
onMounted(async () => {
  const token = generation;
  const enabled = await diagnosticAvailability();
  if (token !== generation) return;
  available.value = enabled;
  if (enabled)
    try {
      report.value = loadDiagnosticReport();
    } catch {
      error.value = "本机报告无法安全读取，可点击“删除报告”清理后重试。";
    }
});
onUnmounted(() => {
  generation++;
});
function commit(value: DiagnosticReport) {
  report.value = value;
  reviewed.value = false;
  try {
    saveDiagnosticReport(value);
    message.value = "脱敏报告已保存在本机，尚未导出。";
  } catch {
    error.value = "本机报告保存失败，当前仅在内存预览；可复制或主动导出。";
  }
}
async function action(kind: "browser" | "check") {
  if (!available.value || !consent.value || busy.value) return;
  const token = ++generation;
  busy.value = true;
  error.value = "";
  message.value = "";
  try {
    if (kind === "browser") {
      await openDiagnosticBrowser();
      if (token !== generation) return;
      opened.value = true;
      message.value =
        "已交给系统浏览器。登录状态不可观察；登录失败、超时或网络错误请按学校网页提示处理。返回 fish 不代表授权成功。";
    } else {
      const value = await checkDiagnosticPage();
      if (token !== generation) return;
      commit(value);
    }
  } catch (e) {
    if (token === generation)
      error.value =
        (e as Error).message === "诊断返回结构异常，已停止生成报告"
          ? (e as Error).message
          : "操作未完成，请检查网络、默认浏览器或返回重试。未读取学校页面。";
  } finally {
    if (token === generation) busy.value = false;
  }
}
async function schoolLogin() {
  if (!available.value || !consent.value || busy.value) return;
  const token = ++generation;
  busy.value = true;
  error.value = "";
  coursePreview.value = null;
  confirmedTimes.value = false;
  try {
    const value = await openSchoolWindow();
    if (token !== generation) return;
    if (value.cancelled) {
      message.value = "已取消学校窗口，未导入课程。";
      return;
    }
    commit(createSchoolPageReport(value.observation));
    if (value.kbList) {
      coursePreview.value = previewZhengfangTimetable(
        { kbList: value.kbList },
        {
          semester: currentSemester.value,
          timeTable: tableForSemester(schedule.value),
          existing: [],
        },
      );
      message.value =
        "课程只在本机内存预览。请逐门核对学校网页，并确认学期、教学周和作息后保存。";
    }
  } catch {
    if (token === generation)
      error.value =
        "学校窗口或数据结构处理未完成，未保存课程；可重试或仅导出脱敏结构报告。";
  } finally {
    if (token === generation) busy.value = false;
  }
}
async function saveCourses() {
  if (!coursePreview.value || !confirmedTimes.value || busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const preview = coursePreview.value;
    await changeSchedule((state) =>
      saveSchoolPagePreview(state, preview, confirmedTimes.value),
    );
    coursePreview.value = null;
    message.value = "已保存为独立的学校网页导入学期，原个人课表仍保留。";
    emit("saved");
  } catch {
    error.value =
      "保存失败或存在冲突，原课表未被替换。请检查学期、作息和冲突提示。";
  } finally {
    busy.value = false;
  }
}
function selfTest() {
  if (!available.value || !consent.value || busy.value) return;
  error.value = "";
  commit(runDiagnosticSelfTest());
}
function cancel() {
  generation++;
  busy.value = false;
  coursePreview.value = null;
  consent.value = false;
  reviewed.value = false;
  opened.value = false;
  message.value =
    "本次本机诊断已取消。浏览器的学校登录会话需在学校网页自行退出。";
}
function remove() {
  generation++;
  busy.value = false;
  report.value = null;
  coursePreview.value = null;
  reviewed.value = false;
  error.value = "";
  try {
    deleteDiagnosticReport();
    message.value = "本机报告已删除；已主动分享的副本请自行管理。";
  } catch {
    error.value = "本机删除失败，请检查设备存储权限后重试。";
  }
}
async function copy() {
  if (!reviewed.value || !report.value) return;
  try {
    await navigator.clipboard.writeText(reportJSON(report.value));
    message.value = "脱敏 JSON 已复制，由你决定是否分享。";
  } catch {
    error.value = "系统未允许复制，请使用主动导出。";
  }
}
async function exportReport() {
  if (!reviewed.value || !report.value || busy.value) return;
  busy.value = true;
  try {
    await exportDiagnosticReport(report.value);
    message.value = "已交给系统分享界面；取消分享不会自动发送。";
  } catch {
    error.value = "导出未完成或已取消，报告仍在本机。";
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section class="diagnostic-page" aria-label="教务诊断工具">
    <button class="text-button diagnostic-back" @click="emit('back')">
      <ArrowLeft :size="18" />返回官方教务
    </button>
    <div class="diagnostic-intro">
      <ShieldCheck :size="23" />
      <div>
        <h2>连接学校教务</h2>
        <p>Android 开发者测试 · v0.4.2</p>
      </div>
      <span class="diagnostic-tag">非官方</span>
    </div>
    <p class="inline-note">
      邯郸校园是独立开发项目，非邯郸学院官方
      App。账号、密码和验证码只在学校真正的网页输入，fish
      不读取或保存。诊断不自动上传数据。
    </p>
    <template v-if="available">
      <div class="diagnostic-section">
        <h3>通过学校网页自行登录</h3>
        <p class="muted">
          打开固定地址 jwgl.hdc.edu.cn。后续导航交由系统浏览器处理，fish
          无法查看 DOM、Cookie 或登录结果，也无法代你退出浏览器会话。
        </p>
        <label class="diagnostic-check"
          ><input v-model="consent" type="checkbox" :disabled="busy" /><span
            >我了解登录不等于授权 fish
            读取数据；仅处理本人经明确选择、学校允许第三方处理的课程结构。</span
          ></label
        >
        <button
          class="secondary full"
          :disabled="!consent || busy"
          @click="schoolLogin"
        >
          登录邯郸学院教务系统 · 实验窗口
        </button>
        <p class="muted">
          实验窗口仅允许
          jwgl.hdc.edu.cn，学校密码由网页自行处理。你进入本人课表后，点击窗口底部“检测课表结构”；识别成功后可另行读取课程供本机预览。未知结构与认证域名会停止并提示，不猜测接口。
        </p>
        <button
          class="secondary full"
          :disabled="!consent || busy"
          @click="action('browser')"
        >
          <ExternalLink :size="18" />打开学校官方网页
        </button>
      </div>
      <div class="diagnostic-section">
        <h3>主动检查课表结构</h3>
        <p class="muted">
          系统浏览器没有页面读取通道，下方按钮只会生成边界说明。要检测实际课表，请使用上方实验窗口里的原生检测按钮；仅在你有权处理的本人课表页面主动操作。
        </p>
        <button
          class="secondary full"
          :disabled="!consent || !opened || busy"
          @click="action('check')"
        >
          <ScanSearch :size="18" />检测当前课表页面
        </button>
        <small class="muted"
          >学校登录、本人课程解析、第三方授权、持续同步均不作成功标记。请勿提供密码、Cookie、HAR
          或完整页面 HTML。</small
        >
      </div>
      <div class="diagnostic-section">
        <h3>离线验证工具本身</h3>
        <p class="muted">
          使用内置人工样本验证单双周、多安排与作息映射，不访问学校、不读取或修改你的课表。通过也不代表兼容邯郸学院真实系统。
        </p>
        <button
          class="secondary full"
          :disabled="!consent || busy"
          @click="selfTest"
        >
          <FlaskConical :size="18" />运行人工样本解析自检
        </button>
      </div>
      <div v-if="coursePreview" class="diagnostic-section">
        <h3>真实页面课程 · 本机预览</h3>
        <p>
          {{ coursePreview.preview.courses.length }} 门课程；{{
            coursePreview.preview.duplicates
          }}
          条重复记录。来源为你在学校网页主动读取，尚未验证自动同步。
        </p>
        <p class="muted">
          学期 {{ currentSemester.academicYear }}
          {{ currentSemester.season }}；第一教学周
          {{ currentSemester.weekStartDate }}；共
          {{ currentSemester.weekCount }} 周。作息：{{
            tableForSemester(schedule).name
          }}。这些配置来自本机，不是学校自动确认。
        </p>
        <ul>
          <li v-for="course in coursePreview.preview.courses" :key="course.id">
            <strong>{{ course.name }}</strong> · {{ course.teacher }}
            <div v-for="a in course.arrangements" :key="a.id">
              周{{ a.day }} {{ a.startPeriod }}–{{ a.endPeriod }}节 ·
              {{ a.start }}–{{ a.end }} · {{ a.room }}<br />教学周
              {{ a.customWeeks.join("、") }}
            </div>
          </li>
        </ul>
        <p
          v-for="problem in [
            ...coursePreview.preview.errors,
            ...coursePreview.preview.issues,
          ]"
          :key="problem"
          class="form-error"
        >
          {{ problem }}
        </p>
        <p
          v-for="warning in coursePreview.preview.warnings"
          :key="warning"
          class="muted"
        >
          {{ warning }}
        </p>
        <label class="diagnostic-check"
          ><input v-model="confirmedTimes" type="checkbox" /><span
            >我已逐门核对官方课表，并确认当前学期、教学周和每节课作息准确，愿意保存为新的独立学校导入学期。</span
          ></label
        >
        <button
          class="secondary full"
          :disabled="
            !confirmedTimes ||
            busy ||
            !!coursePreview.preview.errors.length ||
            !!coursePreview.preview.issues.length
          "
          @click="saveCourses"
        >
          确认保存独立学校课表
        </button>
      </div>
      <p v-if="error" class="form-error" role="alert">{{ error }}</p>
      <p v-if="message" class="inline-note" role="status">{{ message }}</p>
      <div v-if="report" class="diagnostic-section report-section">
        <h3>脱敏报告预览</h3>
        <p>
          {{
            fixture
              ? "人工样本自检报告 · 非学校数据"
              : report.source === "native-webview-user-action"
                ? "本人主动检查的网页结构 · 尚非同步授权"
                : "系统浏览器页面未读取"
          }}
        </p>
        <p class="muted">
          报告仅含固定结构状态。真实课程名、教师、教室、身份信息和凭据均不包含；未观察的字段标为
          unknown。
        </p>
        <pre aria-label="脱敏 JSON 报告">{{ json }}</pre>
        <label class="diagnostic-check"
          ><input v-model="reviewed" type="checkbox" /><span
            >我已审核以上脱敏 JSON，愿意主动复制或导出。</span
          ></label
        >
        <div class="diagnostic-report-actions">
          <button class="secondary" :disabled="!reviewed || busy" @click="copy">
            <Copy :size="17" />复制</button
          ><button
            class="secondary"
            :disabled="!reviewed || busy"
            @click="exportReport"
          >
            <Download :size="17" />导出 JSON
          </button>
        </div>
      </div>
      <div class="diagnostic-footer">
        <button class="text-button" :disabled="busy" @click="remove">
          <Trash2 :size="17" />删除报告</button
        ><button class="text-button" @click="cancel">取消本次诊断</button>
      </div>
      <p class="footnote">
        报告只保存在本机。导出才创建临时文件，系统分享完成或取消后删除临时副本；你主动保存或分享的副本由你管理。
      </p>
    </template>
    <p v-else class="inline-note">
      此工具仅在 Android
      专用测试构建中启用。原个人课表、备份与导入功能不受影响。
    </p>
  </section>
</template>
<style scoped>
.diagnostic-page {
  display: flex;
  flex-direction: column;
  gap: 14px;
  min-width: 0;
}
.diagnostic-back {
  align-self: flex-start;
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
}
.diagnostic-intro {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--color-primary);
}
.diagnostic-intro h2 {
  font-size: 20px;
  margin: 0;
  color: var(--color-text);
}
.diagnostic-intro p {
  font-size: 12px;
  margin: 4px 0 0;
  color: var(--color-muted);
}
.diagnostic-tag {
  margin-left: auto;
  white-space: nowrap;
  font-size: 12px;
  border: 1px solid var(--color-border);
  padding: 4px 8px;
  border-radius: 20px;
}
.diagnostic-section {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card, 18px);
  padding: 14px;
  background: var(--color-surface);
  display: flex;
  flex-direction: column;
  gap: 10px;
  min-width: 0;
}
.diagnostic-section h3 {
  font-size: 15px;
  margin: 0;
}
.diagnostic-section p {
  font-size: 13px;
  line-height: 1.65;
  margin: 0;
}
.diagnostic-check {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  min-height: 44px;
  font-size: 13px;
  line-height: 1.6;
}
.diagnostic-check input {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  margin: 2px 0;
  accent-color: var(--color-primary);
}
.diagnostic-page button {
  min-height: 44px;
  display: inline-flex;
  justify-content: center;
  align-items: center;
  gap: 8px;
}
.diagnostic-page button:disabled {
  opacity: 0.48;
}
.diagnostic-page small {
  font-size: 12px;
  line-height: 1.6;
}
.diagnostic-report-actions,
.diagnostic-footer {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}
.diagnostic-report-actions button {
  flex: 1;
}
.report-section pre {
  font-size: 12px;
  line-height: 1.5;
  background: var(--color-bg);
  border-radius: 12px;
  padding: 12px;
  max-height: 360px;
  overflow: auto;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  min-width: 0;
  margin: 0;
}
.diagnostic-footer {
  justify-content: space-between;
}
</style>
