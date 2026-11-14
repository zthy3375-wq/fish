import SwiftUI
import UniformTypeIdentifiers

struct PersonalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(backup: PersonalBackup) throws { try self.init(data: backup.encode()) }
    init(data: Data) throws {
        _ = try PersonalBackupImport.parse(data)
        self.data = data
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw PersonalBackup.Failure.invalid }
        try self.init(data: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PersonalBackupView: View {
    @EnvironmentObject private var store: CampusStore
    @State private var document: PersonalBackupDocument?
    @State private var importing = false
    @State private var exporting = false
    @State private var filename = "邯院通-iPhone-个人备份"
    @State private var pending: PersonalBackupPreview?
    @State private var completionMessage: String?
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Text("备份个人学期、作息、课程与待办。不包含学校课表、成绩、考试、学习平台状态、生活服务缓存、账号或登录信息。")
                Text("导出是未加密的 JSON 文件，包含个人安排和备注。请选择可信的保存位置；只有在系统文件面板确认后才会保存文件。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("导出") {
                Button { prepareExport(.native) } label: { Label("导出 iPhone 完整个人备份", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("exportNativePersonalBackup")
                Button { prepareExport(.schedule) } label: { Label("导出 Android 个人课表", systemImage: "calendar") }
                    .accessibilityIdentifier("exportAndroidScheduleBackup")
                Button { prepareExport(.tasks) } label: { Label("导出 Android 个人待办", systemImage: "checklist") }
                    .accessibilityIdentifier("exportAndroidTaskBackup")
                Text("iPhone 备份同时保留课程与待办。Android 使用两个独立文件；课程导出包含所有个人学期。若内容超过 Android 的字数、周次或时间精度限制，会明确提示，不会删减后导出。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("导入与恢复") {
                Button { pending = nil; completionMessage = nil; importing = true } label: { Label("选择 JSON 备份", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("importPersonalBackup")
                Text("支持 iPhone 与 Android 的版本 1、2 个人备份。选文件后先预览，再确认恢复。iPhone 完整恢复会替换全部个人数据；Android 课表替换个人课表，待办按编号合并。建议先导出当前备份。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("文件最多 5 MB，不接受压缩包。Android 待办最多 500 条，课表最多 30 个学期；当前显示的学期最多 2000 条课程安排。通知开关沿用本机设置，导入不会请求通知权限。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("个人备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: filename) { result in
            switch result {
            case .success: resultMessage = "个人备份已导出。请妥善保管该未加密文件。"
            case .failure(let error): if !isCancelled(error) { resultMessage = error.localizedDescription }
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let value = try PersonalBackupImport.read(from: url)
                pending = PersonalBackupPreview(value: value, filename: url.lastPathComponent)
            } catch { pending = nil; if !isCancelled(error) { resultMessage = error.localizedDescription } }
        }
        .sheet(item: $pending, onDismiss: {
            if let message = completionMessage { resultMessage = message; completionMessage = nil }
        }) { preview in
            PersonalBackupPreviewView(preview: preview) { message in
                completionMessage = message
                pending = nil
            }
        }
        .alert("个人备份", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("好", role: .cancel) { resultMessage = nil }
        } message: { Text(resultMessage ?? "") }
    }

    private enum ExportFormat { case native, schedule, tasks }
    private func prepareExport(_ format: ExportFormat) {
        guard !exporting else { return }
        do {
            // This also checks that encrypted personal storage was loaded successfully.
            let backup = try store.makePersonalBackup()
            let today = BackupValue.dayString(Date())
            let data: Data
            switch format {
            case .native:
                data = try backup.encode(); filename = "邯院通-iPhone-个人备份-" + today
            case .schedule:
                let plan: AndroidScheduleImportPlan
                if let state = backup.personalSchedule {
                    plan = AndroidScheduleImportPlan(sourceVersion: 2, exportedAt: BackupValue.timestampString(Date()), state: try state.validated(), excludedSchoolSemesters: 0, excludedSchoolCourses: 0)
                } else {
                    plan = try AndroidScheduleImportPlan.fromNative(courses: backup.courses, semesterStart: backup.semesterStart)
                }
                data = try plan.exportData(); filename = "handan-schedule-" + today
            case .tasks:
                data = try AndroidTaskImportPlan.export(tasks: backup.tasks, notificationsEnabled: store.reminders.preferences.tasks)
                filename = "handan-tasks-" + today
            }
            document = try PersonalBackupDocument(data: data)
            exporting = true
        } catch { document = nil; resultMessage = error.localizedDescription }
    }

    private func isCancelled(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}

private struct PersonalBackupPreview: Identifiable {
    let id = UUID()
    let value: PersonalBackupImport
    let filename: String
}

private struct PersonalBackupPreviewView: View {
    @EnvironmentObject private var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    let preview: PersonalBackupPreview
    let completed: (String) -> Void
    @State private var selectedSemesterID = ""
    @State private var selection: AndroidScheduleSelection?
    @State private var taskPreview: AndroidTaskMergePreview?
    @State private var error: String?
    @State private var confirming = false
    @State private var applying = false
    @State private var applied = false
    @State private var baseline: PersonalBackupBaseline?

    var body: some View {
        NavigationStack {
            Form {
                Section("文件") {
                    Text(preview.filename).font(.subheadline)
                    Text(formatTitle).font(.footnote).foregroundStyle(.secondary)
                }
                previewSections
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("personalBackupPreviewError") } }
                Section {
                    Text("个人教学周与学校教学周独立管理。恢复不会改变学校记录、学习平台状态或登录状态。通知开关沿用本机设置。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(actionTitle, role: isReplacement ? .destructive : nil) { prepareConfirmation() }
                        .disabled(!canApply || applying || applied)
                        .accessibilityIdentifier("confirmPersonalBackupPreview")
                }
            }
            .navigationTitle("备份预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(applying) } }
            .onAppear { initializePreview() }
            .onChange(of: selectedSemesterID) { _ in refreshSelection() }
            .alert(isReplacement ? "替换个人记录？" : "合并个人待办？", isPresented: $confirming) {
                Button("取消", role: .cancel) { baseline = nil }
                Button(isReplacement ? "替换并恢复" : "确认合并", role: isReplacement ? .destructive : nil) { apply() }
            } message: { Text(confirmationText) }
        }
        .interactiveDismissDisabled(applying)
    }

    @ViewBuilder private var previewSections: some View {
        switch preview.value {
        case .native(let backup):
            Section("iPhone 完整个人备份") {
                if let schedule = backup.personalSchedule {
                    LabeledContent("个人学期", value: "\(schedule.semesters.count) 个")
                    LabeledContent("作息方案", value: "\(schedule.timeTables.count) 个")
                    LabeledContent("全部个人课程", value: "\(schedule.courses.count) 门")
                    LabeledContent("全部课程安排", value: "\(schedule.courses.reduce(0) { $0 + $1.arrangements.count }) 条")
                    if let active = schedule.semesters.first(where: { $0.id == schedule.activeSemesterId }) { LabeledContent("恢复后显示学期", value: active.title) }
                } else {
                    LabeledContent("个人课程安排", value: "\(backup.courses.count) 条")
                    Text("此备份未包含多学期管理数据，将按旧版个人课表恢复。").font(.footnote).foregroundStyle(.secondary)
                }
                LabeledContent("个人待办", value: "\(backup.tasks.count) 条")
                LabeledContent("个人第一教学周", value: BackupValue.dayString(backup.semesterStart))
                Text("会替换本机全部个人学期、课程与待办，包括现有其他个人学期。建议先取消并导出当前数据。")
                    .font(.footnote).foregroundStyle(.red)
            }
        case .androidSchedule(let plan):
            Section("Android 个人课表") {
                LabeledContent("个人学期", value: "\(plan.state.semesters.count) 个")
                LabeledContent("作息方案", value: "\(plan.state.timeTables.count) 个")
                LabeledContent("全部个人课程", value: "\(plan.state.courses.count) 门")
                LabeledContent("全部课程安排", value: "\(plan.state.courses.reduce(0) { $0 + $1.arrangements.count }) 条")
                Picker("恢复后显示学期", selection: $selectedSemesterID) {
                    Text("请选择学期").tag("")
                    ForEach(plan.state.semesters) { semester in Text(semester.title).tag(semester.id) }
                }.accessibilityIdentifier("backupSemesterSelection")
                Text("备份中的全部个人学期和作息都会保存，不会只导入所选学期。恢复后可在个人课表管理中切换。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote).foregroundStyle(.secondary) }
            }
            if let selection {
                Section("所选学期预览") {
                    LabeledContent("教学周起点", value: selection.semester.weekStartDate)
                    LabeledContent("教学周数量", value: "\(selection.semester.weekCount) 周")
                    LabeledContent("作息方案", value: selection.timeTable.name)
                    LabeledContent("课程安排", value: "\(selection.courses.count) 条")
                    ForEach(selection.courses.prefix(8)) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name)
                            Text("周\(course.day) \(course.start)–\(course.end) · \(course.room.isEmpty ? "地点未填写" : course.room)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if selection.courses.count > 8 { Text("另有 \(selection.courses.count - 8) 条安排，将一并导入。").font(.footnote).foregroundStyle(.secondary) }
                    if selection.courses.isEmpty { Text("这个学期没有个人课程；其他学期仍会完整保留。").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text("本机现有全部个人课表将被此备份替换，包括现有其他学期。个人待办保留。")
                    .font(.footnote).foregroundStyle(.red)
            }
        case .androidTasks(let plan):
            Section("Android 个人待办") {
                LabeledContent("备份待办", value: "\(plan.tasks.count) 条")
                LabeledContent("含子任务", value: "\(plan.tasks.filter { !$0.steps.isEmpty }.count) 条")
                LabeledContent("含重复规则", value: "\(plan.tasks.filter { $0.repeatRule != nil }.count) 条")
                LabeledContent("提醒规则", value: "\(plan.tasks.reduce(0) { $0 + $1.reminders.count }) 条")
                if let taskPreview {
                    LabeledContent("将新增", value: "\(taskPreview.addedCount) 条")
                    LabeledContent("重复编号，保留本机", value: "\(taskPreview.duplicateCount) 条")
                    LabeledContent("合并后共有", value: "\(taskPreview.tasks.count) 条")
                    if !taskPreview.conflictingTitles.isEmpty {
                        Text("有 \(taskPreview.conflictingTitles.count) 条同编号记录内容不同，保留本机版本：").font(.footnote).foregroundStyle(.orange)
                        ForEach(Array(taskPreview.conflictingTitles.prefix(8).enumerated()), id: \.offset) { _, title in Text(title).font(.footnote) }
                        if taskPreview.conflictingTitles.count > 8 { Text("另有 \(taskPreview.conflictingTitles.count - 8) 条同编号差异。").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote).foregroundStyle(.secondary) }
                Text("不会删除本机待办，也不会替换个人课表。若需要用备份覆盖一条已有待办，请先单独核对，不会自动按更新时间覆盖。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var formatTitle: String {
        switch preview.value {
        case .native(let value): return "iPhone 个人备份 · 版本 \(value.version)"
        case .androidSchedule(let value): return "Android 个人课表 · 版本 \(value.sourceVersion)"
        case .androidTasks(let value): return "Android 个人待办 · 版本 \(value.sourceVersion)"
        }
    }
    private var isReplacement: Bool { if case .androidTasks = preview.value { return false }; return true }
    private var actionTitle: String {
        switch preview.value {
        case .native: return "恢复完整个人备份…"
        case .androidSchedule: return "恢复全部个人学期…"
        case .androidTasks: return "合并个人待办…"
        }
    }
    private var canApply: Bool {
        switch preview.value {
        case .native: return true
        case .androidSchedule: return selection != nil
        case .androidTasks: return taskPreview != nil
        }
    }
    private var confirmationText: String {
        switch preview.value {
        case .native(let backup):
            return "将用备份替换本机全部个人学期、课程与 \(backup.tasks.count) 条待办，并恢复个人教学周起点。现有记录不会保留副本，需用先前导出的备份撤销。学校记录和登录状态不变。"
        case .androidSchedule(let plan):
            return "将替换本机全部个人课表，保存备份中的 \(plan.state.semesters.count) 个个人学期与 \(plan.state.courses.count) 门课程，显示“\(selection?.semester.title ?? "")”。本机现有其他个人学期也会被替换；待办保留。需用先前备份撤销。"
        case .androidTasks:
            return "新增 \(taskPreview?.addedCount ?? 0) 条待办；\(taskPreview?.duplicateCount ?? 0) 条重复编号保留本机版本，其中 \(taskPreview?.conflictingTitles.count ?? 0) 条内容不同。课表与通知开关不变。"
        }
    }

    private func initializePreview() {
        switch preview.value {
        case .native: break
        case .androidSchedule(let plan):
            if selectedSemesterID.isEmpty, plan.state.semesters.count == 1 { selectedSemesterID = plan.state.semesters[0].id }
            refreshSelection()
        case .androidTasks(let plan):
            do { taskPreview = try plan.merge(into: store.tasks); error = nil }
            catch { taskPreview = nil; self.error = error.localizedDescription }
        }
    }
    private func refreshSelection() {
        guard case .androidSchedule(let plan) = preview.value else { return }
        selection = nil; error = nil
        guard !selectedSemesterID.isEmpty else { return }
        do { selection = try plan.selection(semesterID: selectedSemesterID) }
        catch { self.error = error.localizedDescription }
    }
    private func prepareConfirmation() {
        guard !applied, !applying else { return }
        initializePreview()
        guard canApply else { return }
        baseline = PersonalBackupBaseline(store: store)
        confirming = true
    }
    private func apply() {
        guard !applying, !applied, let baseline else { return }
        let current = PersonalBackupBaseline(store: store)
        let unchanged: Bool
        switch preview.value {
        case .native: unchanged = current == baseline
        case .androidSchedule: unchanged = current.courses == baseline.courses && current.schedule == baseline.schedule && current.semesterStart == baseline.semesterStart
        case .androidTasks: unchanged = current.tasks == baseline.tasks
        }
        guard unchanged else {
            initializePreview(); error = "本机个人记录刚刚有变化，已刷新预览。请重新核对并确认。"; self.baseline = nil
            return
        }
        applying = true
        defer { applying = false }
        do {
            let message: String
            switch preview.value {
            case .native(let backup):
                try store.restorePersonalBackup(backup)
                message = "已恢复完整个人备份。学校记录、登录状态与通知开关未改变。"
            case .androidSchedule(let plan):
                guard let selection else { throw BackupCompatibilityFailure("请先选择个人学期。") }
                try store.restoreAndroidSchedule(plan, semesterID: selection.semester.id)
                message = "已保存 \(plan.state.semesters.count) 个个人学期，当前显示“\(selection.semester.title)”。个人待办、学校记录与通知开关未改变。"
            case .androidTasks(let plan):
                let result = try store.mergeAndroidTasks(plan)
                message = "已新增 \(result.addedCount) 条个人待办，\(result.duplicateCount) 条重复编号保留本机版本。个人课表与通知开关未改变。"
            }
            applied = true; self.baseline = nil
            completed(message)
        } catch { self.error = error.localizedDescription; self.baseline = nil }
    }
}

/// Recheck the exact replacement/merge scope after confirmation, without coupling it to school refreshes.
private struct PersonalBackupBaseline: Equatable {
    let courses: [Course]
    let tasks: [CampusTask]
    let semesterStart: Date
    let schedule: AndroidScheduleState?
    @MainActor init(store: CampusStore) {
        courses = store.courses.filter { $0.source == "personal" }
        tasks = store.tasks; semesterStart = store.semesterStart; schedule = store.personalSchedule
    }
}
