<script setup lang="ts">
import { ref, computed } from "vue";
import { Capacitor } from "@capacitor/core";
import {
  schedule,
  semester,
  changeSchedule,
  saving,
  storageError,
} from "../composables/schedule";
import {
  uid,
  backup,
  restoreBackup,
  collisions,
  validateSemester,
  type ManagedCourse,
  type Semester,
} from "../domain/schedule";
import {
  fields,
  guessMapping,
  readTable,
  previewRows,
  previewICS,
  csvTemplate,
  type Table,
  type Mapping,
  type ImportPreview,
} from "../services/import-courses";
import { offlineStatus } from "../services/offline";
import { saveFile } from "../services/files";
import {
  reminderStatus,
  reconcileReminders,
  openExactSettings,
} from "../services/reminders";
import TimeTableManager from "./TimeTableManager.vue";
import { parseCourseFile } from "../services/import-adapters";
import { readMigrationBackup } from "../services/schedule-storage";
const props = defineProps<{ initial?: string }>();
const emit = defineEmits<{ changed: []; edit: [id: string]; create: [] }>();
const tab = ref(props.initial || "courses"),
  message = ref(""),
  problem = ref(""),
  pendingDelete = ref(""),
  danger = ref(""),
  phrase = ref(""),
  replace = ref(false),
  replaceConfirmed = ref(false),
  conflictsConfirmed = ref(false),
  restore = ref<ReturnType<typeof restoreBackup>>(),
  busy = ref(false),
  table = ref<Table>(),
  mapping = ref<Mapping>({}),
  preview = ref<ImportPreview>(),
  filename = ref(""),
  termDraft = ref<Semester>(JSON.parse(JSON.stringify(semester.value))),
  minutes = ref(schedule.value.reminders.minutes),
  enabled = ref(schedule.value.reminders.enabled);
const courses = computed(() =>
  schedule.value.courses.filter((c) => c.semesterId === semester.value.id),
);
async function run(fn: () => Promise<unknown>, success: string) {
  problem.value = "";
  message.value = "";
  busy.value = true;
  try {
    await fn();
    message.value = success;
    emit("changed");
  } catch (e) {
    problem.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
async function selectTerm(e: Event) {
  await run(async () => {
    await changeSchedule(
      (s) => (s.activeSemesterId = (e.target as HTMLSelectElement).value),
    );
    termDraft.value = JSON.parse(JSON.stringify(semester.value));
    preview.value = undefined;
    table.value = undefined;
  }, "已切换学期");
}
async function file(event: Event) {
  const input = event.target as HTMLInputElement;
  const f = input.files?.[0];
  if (!f) return;
  preview.value = undefined;
  table.value = undefined;
  restore.value = undefined;
  replaceConfirmed.value = false;
  conflictsConfirmed.value = false;
  await run(async () => {
    if (f.size > 5 * 1024 * 1024) throw Error("文件超过 5 MB");
    filename.value = f.name;
    const buffer = await f.arrayBuffer();
    if (/\.json$/i.test(f.name)) {
      restore.value = restoreBackup(new TextDecoder().decode(buffer));
      return;
    }
    const result = await parseCourseFile(f.name, buffer, {
      semester: semester.value,
      existing: replace.value ? [] : courses.value,
    });
    if (result.kind === "courses") preview.value = result.preview;
    else {
      table.value = result.table;
      mapping.value = guessMapping(table.value.headers);
      reparse();
    }
  }, "文件已读取；请核对映射与预览，确认前不会修改课表");
  input.value = "";
}
function reparse() {
  if (table.value)
    preview.value = previewRows(
      table.value,
      mapping.value,
      semester.value,
      replace.value ? [] : courses.value,
    );
  conflictsConfirmed.value = false;
  replaceConfirmed.value = false;
}
async function applyImport() {
  await run(async () => {
    const p = preview.value;
    if (!p || p.errors.length || !p.courses.length)
      throw Error("请先修正所有错误，再重新预览");
    if (replace.value && !replaceConfirmed.value)
      throw Error("请先确认替换当前学期课表");
    const check = p.courses.flatMap((c, i) =>
      collisions(c, [
        ...(replace.value ? [] : courses.value),
        ...p.courses.slice(0, i),
      ]),
    );
    if (check.some((x) => x.kind === "duplicate"))
      throw Error("当前课表已变化，存在重复记录，请重新解析文件");
    if (check.length && !conflictsConfirmed.value)
      throw Error("请核对时间冲突并明确确认保留");
    await changeSchedule((s) => {
      if (replace.value)
        s.courses = s.courses.filter(
          (c) => c.semesterId !== s.activeSemesterId,
        );
      s.courses.push(...p.courses);
      s.mode = "personal";
    });
    preview.value = undefined;
    table.value = undefined;
  }, "导入成功，已保存到本机");
}
function newTerm() {
  termDraft.value = {
    id: uid(),
    academicYear: "2026–2027",
    season: "春季",
    startDate: "2027-02-22",
    weekStartDate: "2027-02-22",
    weekCount: 18,
    timeTableId: semester.value.timeTableId,
  };
}
async function saveTerm() {
  await run(async () => {
    validateSemester(termDraft.value);
    await changeSchedule((s) => {
      s.semesters = s.semesters.filter((t) => t.id !== termDraft.value.id);
      s.semesters.push(JSON.parse(JSON.stringify(termDraft.value)));
      s.activeSemesterId = termDraft.value.id;
    });
    preview.value = undefined;
    table.value = undefined;
  }, "学期已保存；若缩短周数与已有课程冲突，请先修改课程");
}
async function exportData() {
  await run(
    () => saveFile("handan-campus-backup.json", backup(schedule.value)),
    "备份已生成；请妥善保存文件",
  );
}
async function clearData() {
  await run(async () => {
    if (
      phrase.value !== (danger.value === "all" ? "清空所有课表" : "清空本学期")
    )
      throw Error("请输入完整确认文字");
    await changeSchedule((s) => {
      s.courses =
        danger.value === "all"
          ? []
          : s.courses.filter((c) => c.semesterId !== s.activeSemesterId);
      s.mode = "personal";
    });
    danger.value = "";
    phrase.value = "";
  }, "课表已清空；主题与个人资料已保留");
}
</script>
<template>
  <div class="schedule-manager" :aria-busy="busy || saving">
    <h2>我的课表</h2>
    <p class="muted">
      {{
        schedule.mode === "demo"
          ? "正在体验演示课表，个人课程独立保存"
          : "个人课表 · 仅保存在本机"
      }}
      · 北京时间
    </p>
    <label class="form-label"
      >当前学期<select :value="schedule.activeSemesterId" @change="selectTerm">
        <option v-for="s in schedule.semesters" :key="s.id" :value="s.id">
          {{ s.academicYear }} {{ s.season }}
        </option>
      </select></label
    >
    <div class="manager-tabs">
      <button
        v-for="t in [
          { id: 'courses', label: '课程' },
          { id: 'import', label: '导入' },
          { id: 'times', label: '作息' },
          { id: 'semester', label: '学期' },
          { id: 'backup', label: '数据' },
          { id: 'reminders', label: '提醒' },
        ]"
        :key="t.id"
        :class="{ selected: tab === t.id }"
        :disabled="busy || saving"
        @click="
          tab = t.id;
          problem = '';
          message = '';
        "
      >
        {{ t.label }}
      </button>
    </div>
    <p v-if="problem || storageError" class="form-error" role="alert">
      {{ problem || storageError }}
    </p>
    <p v-if="message" class="inline-note" role="status">{{ message }}</p>
    <div v-if="busy || saving" role="status">正在处理，请稍候…</div>
    <div v-show="!busy && !saving">
      <template v-if="tab === 'courses'"
        ><div class="modal-actions">
          <button class="primary" @click="emit('create')">添加课程</button
          ><button
            class="secondary"
            @click="
              run(
                () =>
                  changeSchedule(
                    (s) => (s.mode = s.mode === 'demo' ? 'personal' : 'demo'),
                  ),
                '数据模式已切换',
              )
            "
          >
            {{ schedule.mode === "demo" ? "查看个人课表" : "体验演示课表" }}
          </button>
        </div>
        <p v-if="!courses.length" class="muted">
          这个学期还没有个人课程。可以手动添加或导入文件。
        </p>
        <div v-for="c in courses" :key="c.id" class="managed-row">
          <button class="course-edit-link" @click="emit('edit', c.id)">
            <strong>{{ c.name }}</strong
            ><small
              >{{ c.teacher || "未填教师" }} ·
              {{ c.arrangements.length }} 个安排 · 编辑</small
            ></button
          ><button
            v-if="pendingDelete !== c.id"
            class="text-button danger"
            @click="pendingDelete = c.id"
          >
            删除</button
          ><template v-else
            ><span>整门课程将删除</span
            ><button
              class="text-button danger"
              @click="
                run(
                  () =>
                    changeSchedule(
                      (s) =>
                        (s.courses = s.courses.filter((x) => x.id !== c.id)),
                    ),
                  '已删除课程',
                );
                pendingDelete = '';
              "
            >
              确认</button
            ><button class="text-button" @click="pendingDelete = ''">
              取消
            </button></template
          >
        </div></template
      >
      <TimeTableManager v-else-if="tab === 'times'" />
      <template v-else-if="tab === 'semester'"
        ><h3>学期与教学周</h3>
        <p class="muted">
          配置供个人课表使用；演示课表始终使用内置学期。请按学校校历设置第一周周一。
        </p>
        <form @submit.prevent="saveTerm">
          <div class="form-grid">
            <label class="form-label"
              >学年<input
                v-model="termDraft.academicYear"
                required
                maxlength="30" /></label
            ><label class="form-label"
              >学期<select v-model="termDraft.season">
                <option>春季</option>
                <option>秋季</option>
              </select></label
            >
          </div>
          <label class="form-label"
            >学期起始日期<input
              v-model="termDraft.startDate"
              type="date"
              required /></label
          ><label class="form-label"
            >第一教学周周一<input
              v-model="termDraft.weekStartDate"
              type="date"
              required /></label
          ><label class="form-label"
            >教学周数量<input
              v-model.number="termDraft.weekCount"
              type="number"
              min="1"
              max="40"
              required
          /></label>
          <div class="modal-actions">
            <button type="button" class="secondary" @click="newTerm">
              新建学期</button
            ><button class="primary">保存学期</button>
          </div>
        </form></template
      >
      <template v-else-if="tab === 'import'"
        ><h3>导入课程文件</h3>
        <p class="muted">
          CSV / XLSX 采用每行一个上课安排的列表表格，不支持图片、PDF
          或合并单元格周课表。ICS 支持定时事件和 RRULE /
          EXDATE，改期例外会报错。文件不上传服务器。
        </p>
        <button
          class="secondary full"
          @click="
            run(
              () =>
                saveFile(
                  '课程导入模板.csv',
                  '\uFEFF' + csvTemplate,
                  'text/csv;charset=utf-8',
                ),
              '模板已生成',
            )
          "
        >
          下载 CSV 标准模板</button
        ><label class="form-label"
          >导入方式<select
            v-model="replace"
            @change="
              preview = undefined;
              table = undefined;
            "
          >
            <option :value="false">合并到当前学期</option>
            <option :value="true">替换当前学期</option>
          </select></label
        ><label class="file-picker"
          >选择课程文件<input
            type="file"
            accept=".csv,.xlsx,.ics"
            @change="file"
        /></label>
        <p class="muted">
          当前文件：{{ filename || "未选择" }}。UTF-8 CSV，最多 5 MB / 3000 行。
        </p>
        <template v-if="table"
          ><h3>核对字段</h3>
          <p class="muted">
            已自动匹配常见列名。必填：课程名称、星期、开始时间、结束时间、教学周。无法匹配时，请在下方选择正确的列。
          </p>
          <div class="form-grid">
            <label v-for="(label, key) in fields" :key="key" class="form-label"
              >{{ label
              }}<select v-model="mapping[key]" @change="reparse">
                <option :value="undefined">不导入此列</option>
                <option v-for="header in table.headers" :key="header">
                  {{ header }}
                </option>
              </select></label
            >
          </div>
          <p class="muted">
            未映射列：{{
              table.headers
                .filter((h) => !Object.values(mapping).includes(h))
                .join("、") || "无"
            }}
          </p>
          <button class="secondary full" @click="reparse">
            重新生成预览
          </button></template
        ><template v-if="preview"
          ><h3>导入预览 · {{ preview.courses.length }} 门课程</h3>
          <p>
            {{
              preview.courses.reduce((n, c) => n + c.arrangements.length, 0)
            }}
            个安排 · 跳过 {{ preview.duplicates }} 条完全重复记录
          </p>
          <p
            v-for="(w, i) in preview.warnings"
            :key="'w' + i"
            class="inline-note"
          >
            {{ w }}
          </p>
          <p v-for="(e, i) in preview.errors" :key="'e' + i" class="form-error">
            {{ e }}
          </p>
          <details v-if="preview.issues.length">
            <summary>{{ preview.issues.length }} 处时间冲突</summary>
            <p v-for="(v, i) in preview.issues" :key="i">{{ v }}</p>
          </details>
          <div class="import-preview">
            <article v-for="c in preview.courses" :key="c.id">
              <strong>{{ c.name }} · {{ c.teacher || "未填教师" }}</strong>
              <p v-for="a in c.arrangements" :key="a.id">
                周{{ a.day }} {{ a.start }}–{{ a.end }} ·
                {{ a.room || "未填地点" }} ·
                {{
                  a.startWeek === a.endWeek
                    ? a.startWeek
                    : a.customWeeks.join(",")
                }}
                周
              </p>
            </article>
          </div>
          <label v-if="preview.issues.length" class="check-line"
            ><input
              v-model="conflictsConfirmed"
              type="checkbox"
            />已核对，保留冲突安排</label
          ><template v-if="replace"
            ><button class="secondary full" @click="exportData">
              先备份现有课表</button
            ><label class="check-line"
              ><input
                v-model="replaceConfirmed"
                type="checkbox"
              />确认替换本学期个人课表，其他学期保留</label
            ></template
          >
          <div class="modal-actions">
            <button
              class="secondary"
              @click="
                preview = undefined;
                table = undefined;
              "
            >
              取消导入</button
            ><button
              class="primary"
              :disabled="!!preview.errors.length || !preview.courses.length"
              @click="applyImport"
            >
              确认{{ replace ? "替换" : "合并" }}
            </button>
          </div></template
        >
        <p class="footnote">
          未确认邯郸学院学生课表官方导出格式，暂不提供学校一键导入，也不需要学校密码。
        </p></template
      >
      <template v-else-if="tab === 'backup'"
        ><h3>课表数据管理</h3>
        <p class="inline-note">{{ offlineStatus }}</p>
        <p class="muted">
          版本化 JSON 包含所有学期、作息方案与个人课程，可在 Android 和 Web
          之间恢复。不包含个人资料和主题。清除站点数据或卸载 App
          会丢失本机课表，请定期备份。
        </p>
        <button class="secondary full" @click="exportData">
          导出全部个人课表备份</button
        ><button
          class="text-button"
          @click="
            run(async () => {
              const old = await readMigrationBackup();
              if (!old) throw Error('此设备没有 v0.3 升级前课表快照');
              await saveFile(
                'handan-campus-before-v031.json',
                JSON.stringify(
                  { format: 'handan-campus-schedule', data: old },
                  null,
                  2,
                ),
              );
            }, '升级前备份已导出')
          "
        >
          导出升级前原始快照</button
        ><label class="file-picker"
          >读取 JSON 备份<input
            type="file"
            accept=".json"
            @change="file" /></label
        ><template v-if="restore"
          ><p>
            {{ restore.semesters.length }} 个学期 ·
            {{ restore.courses.length }} 门课程，恢复将覆盖全部个人课表。
          </p>
          <button class="secondary full" @click="exportData">
            先备份当前数据</button
          ><label class="check-line"
            ><input
              v-model="replaceConfirmed"
              type="checkbox"
            />确认使用备份替换全部课表</label
          ><button
            class="primary full"
            :disabled="!replaceConfirmed"
            @click="
              run(async () => {
                const value = JSON.parse(JSON.stringify(restore!));
                await changeSchedule((s) =>
                  Object.assign(s, value, {
                    reminders: { ...value.reminders, enabled: false },
                  }),
                );
                restore = undefined;
                termDraft = JSON.parse(JSON.stringify(semester));
              }, '恢复成功；课程提醒已关闭，请重新授权开启')
            "
          >
            确认恢复
          </button></template
        >
        <div class="modal-actions">
          <button
            class="secondary danger"
            @click="
              danger = 'term';
              phrase = '';
            "
          >
            清空本学期</button
          ><button
            class="secondary danger"
            @click="
              danger = 'all';
              phrase = '';
            "
          >
            清空全部课表
          </button>
        </div>
        <div v-if="danger" class="confirmation">
          <p>
            此操作无法撤销，请先导出备份。再次输入“{{
              danger === "all" ? "清空所有课表" : "清空本学期"
            }}”确认：
          </p>
          <input v-model="phrase" aria-label="清空确认文字" />
          <div class="modal-actions">
            <button class="secondary" @click="danger = ''">取消</button
            ><button class="primary" @click="clearData">确认清空</button>
          </div>
        </div></template
      >
      <template v-else
        ><h3>课程提醒</h3>
        <p class="muted">{{ reminderStatus }}</p>
        <p v-if="!Capacitor.isNativePlatform()" class="inline-note">
          Web 不提供可靠后台提醒。课表仍可离线查看；请在打包后的 Android
          App 开启提醒。
        </p>
        <template v-else
          ><label class="check-line"
            ><input v-model="enabled" type="checkbox" />开启个人课程提醒</label
          ><label class="form-label"
            >提前分钟数（1–120）<input
              v-model.number="minutes"
              type="number"
              min="1"
              max="120"
              list="lead-times" /><datalist id="lead-times">
              <option
                v-for="m in [5, 10, 15, 30]"
                :key="m"
                :value="m"
              /></datalist></label
          ><button
            class="primary full"
            @click="
              run(async () => {
                await changeSchedule(
                  (s) => (s.reminders = { enabled, minutes }),
                );
                await reconcileReminders(schedule, true);
              }, '提醒设置已保存，请检查上方权限状态')
            "
          >
            保存并检查系统授权
          </button></template
        ><button
          v-if="Capacitor.getPlatform() === 'android'"
          class="secondary full"
          @click="run(openExactSettings, '返回 App 后重新核对权限状态')"
        >
          Android 精确闹钟设置
        </button>
        <p class="footnote">
          最多调度近期 60 次提醒，打开 App
          时续排；系统省电、重启、时区和权限可能影响送达。原生通知尚待真机验证。
        </p></template
      >
    </div>
  </div>
</template>
