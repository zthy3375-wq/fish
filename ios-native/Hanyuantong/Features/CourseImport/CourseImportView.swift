import SwiftUI
import UniformTypeIdentifiers

/// Integration: present in a NavigationStack/sheet. onImport must atomically validate/save
/// the entire batch, preserve school records, and throw on failure. Called only after consent.
struct CourseImportView: View {
    let semesterStart: Date
    let existing: [Course]
    var weekCount: Int = 18
    var onReplace: (([Course]) throws -> Void)? = nil
    let onImport: ([Course]) throws -> Void

    private enum Mode: String { case merge, replace }
    @State private var mode = Mode.merge
    @State private var replacementConfirmed = false

    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false
    @State private var showingConfirmation = false
    @State private var fileName = ""
    @State private var table: CourseImportTable?
    @State private var mapping: CourseImportEngine.Mapping = [:]
    @State private var preview: CourseImportPreview?
    @State private var message: String?
    @State private var conflictsConfirmed = false
    @State private var isReading = false
    @State private var isSaving = false
    @State private var generation = UUID()
    @State private var templateDocument = CourseCSVTemplateDocument()
    @State private var exportingTemplate = false

    private var existingForPreview: [Course] {
        mode == .replace ? existing.filter { $0.source != "personal" } : existing
    }
    private var actionTitle: String { mode == .replace ? "替换" : "合并" }

    private var allowedTypes: [UTType] {
        [UTType.commaSeparatedText, UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "ics")].compactMap { $0 }
    }

    private var semesterLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = ScheduleMath.calendar
        formatter.timeZone = ScheduleMath.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: semesterStart)
    }

    var body: some View {
        Form {
            Section {
                Text("文件只在本机解析，确认前不会修改课表。导入为个人课程，学校同步记录保持独立。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if onReplace != nil {
                    Picker("导入方式", selection: $mode) {
                        Text("合并到个人课表").tag(Mode.merge)
                        Text("替换全部个人课程").tag(Mode.replace)
                    }.disabled(isReading || isSaving)
                    if mode == .replace {
                        Text("替换会删除当前全部个人课程，仅保留本次导入内容。待办与学校同步数据保留。建议先到“个人备份与恢复”导出备份；替换无法自动撤销。")
                            .font(.caption).foregroundStyle(.red)
                    }
                } else { LabeledContent("导入方式", value: "合并到个人课表") }
                LabeledContent("教学周", value: "1–\(weekCount) 周")
                Text("学期起点：\(semesterLabel)")
                    .font(.caption).foregroundStyle(.secondary)
                Button { showingPicker = true } label: { Label("选择 CSV / XLSX / ICS 文件", systemImage: "doc.badge.plus") }
                    .disabled(isReading || isSaving)
                    .accessibilityIdentifier("courseImport.chooseFile")
                Button { exportingTemplate = true } label: { Label("导出 CSV 标准模板", systemImage: "square.and.arrow.up") }
                    .disabled(isReading || isSaving)
                Text("UTF-8 CSV、单工作表 XLSX 或 ICS；最多 5 MB、3000 行、50 列。Excel 时间请设为文本 HH:mm。")
                    .font(.caption).foregroundStyle(.secondary)
                if !fileName.isEmpty { Text(fileName).font(.caption) }
                if isReading { ProgressView("正在本机检查文件…") }
            }
            if let message {
                Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("courseImport.error") }
            }
            if let table {
                Section("核对字段映射") {
                    Text("带 * 的列为必填。未映射列不会导入。更改映射后需重新生成预览。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(CourseImportField.allCases) { field in
                        Picker(field.title + (field.required ? " *" : ""), selection: Binding(
                            get: { mapping[field] ?? "" },
                            set: { value in
                                mapping[field] = value.isEmpty ? nil : value
                                generation = UUID(); isReading = false; showingConfirmation = false
                                preview = nil; conflictsConfirmed = false; replacementConfirmed = false
                            })) {
                            Text("不导入此列").tag("")
                            ForEach(table.headers, id: \.self) { Text($0).tag($0) }
                        }.disabled(isReading || isSaving)
                    }
                    let unmapped = table.headers.filter { !mapping.values.contains($0) }
                    Text("未映射列：" + (unmapped.isEmpty ? "无" : unmapped.joined(separator: "、")))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重新生成预览") { rebuild() }
                        .disabled(isReading || isSaving)
                        .accessibilityIdentifier("courseImport.preview")
                }
            }
            if let preview {
                Section("导入预览 · \(preview.courses.count) 个安排") {
                    Text("跳过 \(preview.duplicates) 条完全重复记录")
                        .font(.subheadline)
                    ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(preview.errors.prefix(30).enumerated()), id: \.offset) { _, error in
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if preview.errors.count > 30 { Text("另有 \(preview.errors.count - 30) 个错误。请修正文件后重新选择。") }
                    ForEach(preview.courses.prefix(100)) { course in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(course.name).font(.headline)
                            Text("周\(course.day) \(course.start)–\(course.end) · \(course.room.isEmpty ? "未填地点" : course.room)")
                            Text("第 \(course.weeks.map(String.init).joined(separator: ",")) 周 · \(course.teacher.isEmpty ? "未填教师" : course.teacher)")
                                .font(.caption).foregroundStyle(.secondary)
                            if !course.notes.isEmpty { Text(course.notes).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if preview.courses.count > 100 {
                        NavigationLink("查看全部 \(preview.courses.count) 个安排") {
                            List(preview.courses) { course in
                                VStack(alignment: .leading) {
                                    Text(course.name).font(.headline)
                                    Text("周\(course.day) \(course.start)–\(course.end) · \(course.room)")
                                    Text("第 \(course.weeks.map(String.init).joined(separator: ",")) 周")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.navigationTitle("全部导入安排")
                        }
                    }
                }
                if !preview.issues.isEmpty {
                    Section("时间冲突") {
                        DisclosureGroup("查看冲突提示（\(preview.issues.count)）") {
                            ForEach(Array(preview.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption) }
                        }
                        Toggle("已核对，保留冲突安排", isOn: $conflictsConfirmed)
                            .accessibilityIdentifier("courseImport.allowConflicts")
                    }
                }
                Section {
                    if mode == .replace {
                        Toggle("确认替换全部个人课程，学校数据与待办保留", isOn: $replacementConfirmed)
                            .accessibilityIdentifier("courseImport.allowReplacement")
                    }
                    Button("确认\(actionTitle) \(preview.courses.count) 个个人课程安排") { showingConfirmation = true }
                        .disabled(!preview.canImport || (!preview.issues.isEmpty && !conflictsConfirmed) || (mode == .replace && !replacementConfirmed) || isReading || isSaving)
                        .accessibilityIdentifier("courseImport.confirm")
                    Button("取消导入", role: .cancel) { clear() }
                        .disabled(isSaving)
                }
            }
        }
        .navigationTitle("导入个人课程")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { generation = UUID(); dismiss() }.disabled(isSaving) } }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { load(url) }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $exportingTemplate, document: templateDocument, contentType: .commaSeparatedText, defaultFilename: "个人课程模板.csv") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .confirmationDialog("确认导入个人课表？", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("确认\(actionTitle)", role: mode == .replace ? .destructive : nil) { commit() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(mode == .replace
                 ? "将删除全部现有个人课程，以预览中的 \(preview?.courses.count ?? 0) 个安排替换。学校数据与待办保留，无法自动撤销。"
                 : "将新增预览中的 \(preview?.courses.count ?? 0) 个个人课程安排，不会替换已有课程。\(conflictsConfirmed ? "你已确认保留时间冲突。" : "")")
        }
        .onChange(of: mode) { _ in invalidateForChange() }
        .onChange(of: existing) { _ in invalidateForChange() }
        .onChange(of: semesterStart) { _ in invalidateForChange() }
        .onChange(of: weekCount) { _ in invalidateForChange() }
        .onDisappear { generation = UUID() }
    }

    private func load(_ url: URL) {
        clear(); isReading = true; fileName = url.lastPathComponent
        let token = generation, start = semesterStart, count = weekCount, current = existingForPreview
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CourseImportResult, Error> in
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                return Result { try CourseImportEngine.read(from: url, semesterStart: start, weekCount: count, existing: current) }
            }.value
            guard generation == token else { return }
            isReading = false
            switch result {
            case .success(.table(let value)):
                table = value; mapping = CourseImportEngine.guessMapping(value.headers); rebuild()
            case .success(.preview(let value)): preview = value
            case .failure(let error): message = "无法解析 \(fileName)：\(error.localizedDescription) 可使用 CSV 标准模板重试。"
            }
        }
    }
    private func rebuild() {
        guard let table else { return }
        conflictsConfirmed = false; replacementConfirmed = false; message = nil; isReading = true; preview = nil
        generation = UUID()
        let token = generation, selection = mapping, start = semesterStart, count = weekCount, current = existingForPreview
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CourseImportEngine.preview(table, mapping: selection, semesterStart: start, weekCount: count, existing: current)
            }.value
            guard generation == token else { return }
            preview = result; isReading = false
        }
    }
    private func commit() {
        guard let preview, preview.canImport, !isSaving, preview.issues.isEmpty || conflictsConfirmed, mode != .replace || replacementConfirmed else { return }
        // Store changes invalidate preview via onChange; recheck immediately before the write too.
        for course in preview.courses {
            if existingForPreview.contains(where: { CourseImportEngine.isDuplicate(course, $0) }) {
                message = "当前课表已变化，存在重复记录，请重新预览。"; self.preview = nil; return
            }
            if !conflictsConfirmed && existingForPreview.contains(where: { CourseImportEngine.overlaps(course, $0) }) {
                message = "当前课表已变化，出现新冲突，请重新预览。"; self.preview = nil; return
            }
        }
        isSaving = true
        do {
            if mode == .replace {
                guard let onReplace else { throw CourseImportFailure("当前页面不支持替换，请改用合并导入。") }
                try onReplace(preview.courses)
            } else { try onImport(preview.courses) }
            dismiss()
        }
        catch { message = error.localizedDescription; isSaving = false }
    }
    private func clear() {
        generation = UUID(); table = nil; mapping = [:]; preview = nil; message = nil
        fileName = ""; conflictsConfirmed = false; replacementConfirmed = false; isReading = false; showingConfirmation = false
    }
    private func invalidateForChange() {
        guard !isSaving, table != nil || preview != nil || isReading else { return }
        generation = UUID(); isReading = false; conflictsConfirmed = false; replacementConfirmed = false; showingConfirmation = false
        preview = nil
        message = "导入方式、课表或学期设置已变化。请重新生成预览；ICS 文件请重新选择。"
    }
}

private struct CourseCSVTemplateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(CourseImportEngine.csvTemplate.utf8))
    }
}
