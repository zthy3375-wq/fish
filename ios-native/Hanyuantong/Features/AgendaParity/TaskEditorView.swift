import SwiftUI

struct TaskEditorView: View {
    @EnvironmentObject var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CampusTask
    @State private var newStep = ""
    @State private var errorMessage: String?
    @State private var discard = false
    @State private var saving = false
    private let original: CampusTask
    private let isNew: Bool

    init(task: CampusTask? = nil) {
        let value = task ?? TaskRules.makeTask()
        _draft = State(initialValue: value)
        original = value; isNew = task == nil
    }
    private var changed: Bool { draft != original || !newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var titleValid: Bool {
        let value = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 200
    }
    private var planMode: Binding<Int> {
        Binding(get: { draft.plannedAt != nil ? 2 : draft.plannedDay != nil ? 1 : 0 }, set: { mode in
            let day = TaskRules.plannedDay(draft) ?? TaskClock.day(Date())
            let start = TaskClock.start(day) ?? Date()
            if mode == 0 { draft.plannedAt = nil; draft.plannedDay = nil }
            else if mode == 1 { draft.plannedAt = nil; draft.plannedDay = day }
            else {
                draft.plannedAt = draft.plannedAt ?? TaskClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: start)
                draft.plannedDay = nil
            }
            draft.snoozedUntil = nil
        })
    }
    private var planDate: Binding<Date> {
        Binding(get: { draft.plannedAt ?? draft.plannedDay.flatMap(TaskClock.start) ?? Date() }, set: { value in
            if draft.plannedAt != nil { draft.plannedAt = TaskRules.pickerMinute(value); draft.plannedDay = nil }
            else { draft.plannedDay = TaskClock.day(value) }
            draft.snoozedUntil = nil
        })
    }
    private var repeatKind: Binding<String> {
        Binding(get: { draft.repeatRule?.kind.rawValue ?? "none" }, set: { value in
            if let kind = TaskRepeatKind(rawValue: value) {
                draft.repeatRule = TaskRepeatRule(kind: kind, interval: 1, weekdays: kind == .days ? [1] : [])
            } else { draft.repeatRule = nil }
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("task-save-error") } }
                basicSection
                planSection
                classificationSection
                stepsSection
                repeatSection
                remindersSection
                if !draft.completed { snoozeSection }
                Section {
                    Text("待办只保存在本机，所有日期按北京时间。个人准备状态不会更改学习通提交结果。系统提醒需在“我的 → 系统提醒”开启，iOS 可能因权限或专注模式延迟送达。")
                        .font(.caption).foregroundStyle(CampusTheme.muted)
                }
            }
            .navigationTitle(isNew ? "添加待办" : "编辑待办").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if changed { discard = true } else { dismiss() } }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!titleValid || saving) }
            }
            .confirmationDialog("修改尚未保存", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) { }
            }
            .interactiveDismissDisabled(changed || saving)
        }.environment(\.timeZone, TaskClock.calendar.timeZone)
    }

    private var basicSection: some View {
        Section("要做什么") {
            TextField("待办内容", text: $draft.title, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("task-title-editor")
            if draft.title.count > 200 { Text("请将待办内容控制在200字以内").font(.caption).foregroundStyle(.red) }
            TextField("关联课程（可不填）", text: $draft.course).accessibilityLabel("关联课程").accessibilityIdentifier("task-course-editor")
            TextField("待办备注", text: $draft.notes, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("task-notes-editor")
            if isNew {
                Menu("从常用模板创建") {
                    template("作业", title: "完成课程作业", minutes: 60, steps: ["梳理要求", "完成题目", "检查并提交"])
                    template("实验报告", title: "提交实验报告", minutes: 90, steps: ["整理实验数据", "分析与结论", "检查格式并提交"])
                    template("考试复习", title: "考试复习计划", minutes: 60, steps: ["整理考试范围", "复习知识点", "练习与错题回顾"])
                    template("论文", title: "论文阶段任务", minutes: 90, steps: ["确定提纲", "查阅文献", "完成草稿", "修改与提交"])
                    template("报名", title: "完成报名", minutes: 15, steps: ["核对条件和截止时间", "准备材料", "提交并确认结果"])
                }
            }
        }
    }
    private func template(_ label: String, title: String, minutes: Int, steps: [String]) -> some View {
        Button(label) {
            draft.title = title; draft.durationMinutes = minutes
            draft.steps = steps.map { TaskStep(title: $0) }
        }
    }
    private var planSection: some View {
        Section("计划与截止") {
            Picker("计划方式", selection: planMode) { Text("未安排").tag(0); Text("仅日期").tag(1); Text("具体时间").tag(2) }
            if planMode.wrappedValue != 0 {
                DatePicker(planMode.wrappedValue == 1 ? "计划日期" : "日期与时间", selection: planDate,
                           displayedComponents: planMode.wrappedValue == 1 ? [.date] : [.date, .hourAndMinute])
                HStack {
                    Button("今天") { replan(0) }.buttonStyle(.borderless)
                    Button("明天") { replan(1) }.buttonStyle(.borderless)
                }
            }
            if draft.plannedAt != nil { Stepper("预计 \(draft.durationMinutes) 分钟", value: $draft.durationMinutes, in: 5...1440, step: 5) }
            Toggle("设置截止时间", isOn: Binding(get: { draft.deadline != nil }, set: { draft.deadline = $0 ? draft.deadline ?? TaskRules.futurePickerMinute(minutes: 60) : nil }))
            if draft.deadline != nil {
                DatePicker("待办截止时间", selection: Binding(get: { draft.deadline ?? TaskRules.futurePickerMinute(minutes: 60) }, set: { draft.deadline = TaskRules.pickerMinute($0) }))
            }
            if let day = TaskRules.plannedDay(draft), let deadline = draft.deadline, day > TaskClock.day(deadline) {
                Text("计划日期晚于截止日期，请留意提交要求。只能在官方平台完成提交。").font(.caption).foregroundStyle(.red)
            }
        }
    }
    private var classificationSection: some View {
        Section("分类与优先级") {
            Picker("任务优先级", selection: $draft.priority) {
                ForEach(0..<TaskRules.priorities.count, id: \.self) { Text(TaskRules.priorities[$0]).tag($0) }
            }
            Toggle("置顶任务", isOn: $draft.pinned)
            Toggle("准备就绪", isOn: $draft.prepared)
        }
    }
    private var stepsSection: some View {
        Section("步骤") {
            ForEach($draft.steps) { $step in
                HStack {
                    Toggle("完成步骤 \(step.title)", isOn: $step.completed).labelsHidden()
                    TextField("步骤标题", text: $step.title)
                    Button { draft.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).accessibilityLabel("删除步骤 \(step.title)")
                }
            }
            HStack {
                TextField("新步骤标题", text: $newStep).onSubmit(addStep)
                Button("添加步骤", action: addStep).disabled(draft.steps.count >= 50 || newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !draft.steps.isEmpty { Text("完成 \(draft.steps.filter(\.completed).count)/\(draft.steps.count) · 最多50项").font(.caption).foregroundStyle(CampusTheme.muted) }
        }
    }
    private var repeatSection: some View {
        Section("重复") {
            Picker("任务重复规则", selection: repeatKind) {
                Text("不重复").tag("none")
                ForEach(TaskRepeatKind.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            if draft.repeatRule?.kind == .interval {
                Stepper("每 \(draft.repeatRule?.interval ?? 1) 天", value: Binding(get: { draft.repeatRule?.interval ?? 1 }, set: { draft.repeatRule?.interval = $0 }), in: 1...365)
            }
            if draft.repeatRule?.kind == .days {
                HStack(spacing: 0) {
                    ForEach(1...7, id: \.self) { weekday in
                        Button {
                            guard var rule = draft.repeatRule else { return }
                            if rule.weekdays.contains(weekday) { rule.weekdays.removeAll { $0 == weekday } }
                            else { rule.weekdays.append(weekday) }
                            draft.repeatRule = rule
                        } label: {
                            Text(["一", "二", "三", "四", "五", "六", "日"][weekday - 1]).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(draft.repeatRule?.weekdays.contains(weekday) == true ? Color.white : CampusTheme.text)
                                .background(draft.repeatRule?.weekdays.contains(weekday) == true ? CampusTheme.primary : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.borderless).accessibilityLabel("重复星期\(weekday)")
                    }
                }
            }
            if draft.repeatRule != nil {
                Text("完成后只生成下一次未来任务，保留计划与截止之间的间隔。已修改的下一次任务不会因撤销完成而丢失。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
            }
        }
    }
    private var remindersSection: some View {
        Section("提醒") {
            if draft.legacyReminder {
                Toggle("沿用原计划时间提醒", isOn: $draft.legacyReminder)
                Text("未设置单独提醒时，沿用“系统提醒”中的提前时间。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            ForEach($draft.reminders) { $reminder in
                TaskReminderEditorRow(reminder: $reminder) { draft.reminders.removeAll { $0.id == reminder.id } }
            }
            Button("添加提醒") {
                draft.reminders.append(TaskReminder(anchor: draft.deadline == nil ? .start : .deadline))
            }.disabled(draft.reminders.count >= 5)
            Text("最多5次。只安排日期不会触发开始提醒，未填写截止时间也不会触发截止提醒。").font(.caption).foregroundStyle(CampusTheme.muted)
        }
    }
    private var snoozeSection: some View {
        Section("稍后提醒") {
            Toggle("稍后再提醒我", isOn: Binding(get: { draft.snoozedUntil != nil }, set: { draft.snoozedUntil = $0 ? draft.snoozedUntil ?? TaskRules.futurePickerMinute(minutes: 10) : nil }))
            if draft.snoozedUntil != nil {
                DatePicker("稍后提醒时间", selection: Binding(get: { draft.snoozedUntil ?? TaskRules.futurePickerMinute(minutes: 10) }, set: { draft.snoozedUntil = TaskRules.pickerMinute($0) }))
            }
        }
    }
    private func replan(_ days: Int) {
        guard let day = TaskClock.shifted(TaskClock.day(Date()), days: days) else { return }
        let target = TaskClock.start(day) ?? Date()
        if let at = draft.plannedAt {
            let parts = TaskClock.calendar.dateComponents([.hour, .minute], from: at)
            draft.plannedAt = TaskClock.calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: target)
        } else { draft.plannedDay = day }
        draft.snoozedUntil = nil
    }
    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100, draft.steps.count < 50 else { return }
        draft.steps.append(TaskStep(title: title)); newStep = ""
    }
    private func save() {
        guard !saving else { return }
        saving = true; defer { saving = false }
        do {
            if !newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard newStep.count <= 100, draft.steps.count < 50 else { throw TaskRules.Failure("步骤最多100字，共50项") }
                addStep()
            }
            let now = Date()
            if draft.snoozedUntil != original.snoozedUntil, let until = draft.snoozedUntil, until <= now {
                throw TaskRules.Failure("请选择将来的稍后提醒时间")
            }
            draft.updatedAt = now
            let value = try TaskRules.validated(draft)
            try store.saveTask(value)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct TaskReminderEditorRow: View {
    @Binding var reminder: TaskReminder
    var remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("提醒依据", selection: $reminder.anchor) {
                ForEach(TaskReminderAnchor.allCases, id: \.self) { Text($0.label).tag($0) }
            }.onChange(of: reminder.anchor) { anchor in
                if anchor == .absolute && reminder.at == nil { reminder.at = TaskRules.futurePickerMinute(minutes: 30) }
            }
            if reminder.anchor == .absolute {
                DatePicker("指定提醒时间", selection: Binding(get: { reminder.at ?? TaskRules.futurePickerMinute(minutes: 30) }, set: { reminder.at = TaskRules.pickerMinute($0) }))
            } else {
                HStack {
                    Text("提前分钟")
                    TextField("提前分钟", value: $reminder.minutes, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
            Button("删除提醒", role: .destructive, action: remove).buttonStyle(.borderless)
        }
    }
}
