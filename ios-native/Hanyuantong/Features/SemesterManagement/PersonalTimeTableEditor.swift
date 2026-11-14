import SwiftUI

struct PersonalTimeTableEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: AndroidScheduleState
    let semester: AndroidSemester
    let save: (AndroidScheduleState) throws -> Void
    @State private var selectedID: String
    @State private var draft: AndroidTimeTable
    @State private var pending: AndroidScheduleState?
    @State private var changes: [String] = []
    @State private var conflicts: [String] = []
    @State private var confirmed = false
    @State private var error: String?

    init(state: AndroidScheduleState, semester: AndroidSemester, table: AndroidTimeTable, save: @escaping (AndroidScheduleState) throws -> Void) {
        self.state = state; self.semester = semester; self.save = save
        _selectedID = State(initialValue: table.id); _draft = State(initialValue: table)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择作息方案") {
                    Picker("已有方案", selection: $selectedID) { ForEach(state.timeTables) { Text($0.name).tag($0.id) } }
                        .onChange(of: selectedID) { id in
                            if let value = state.timeTables.first(where: { $0.id == id }) { draft = value }
                            clearPreview()
                        }
                    Button("预览切换到这个方案") {
                        if let selected = state.timeTables.first(where: { $0.id == selectedID }) { prepare(selected, saveCopy: false) }
                    }
                    Button("载入邯郸学院作息 · 40分钟 / 13节") { draft = PersonalSemesterRules.handanTimeTable(); clearPreview() }
                    Text("邯郸学院作息依据用户提供的时间表，并非实时校历。请预览后核对。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                Section("另存新的作息方案") {
                    TextField("方案名称", text: $draft.name)
                    ForEach(draft.slots.indices, id: \.self) { index in
                        HStack {
                            Text("\(index + 1)").frame(width: 24)
                            TextField("HH:mm", text: $draft.slots[index].start).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never)
                                .accessibilityLabel("第\(index + 1)节开始时间")
                            Text("–").foregroundStyle(CampusTheme.muted)
                            TextField("HH:mm", text: $draft.slots[index].end).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never)
                                .accessibilityLabel("第\(index + 1)节结束时间")
                        }
                    }
                    Button("增加一节") { addSlot() }.disabled(draft.slots.count >= 24)
                    Button("移除最后一节", role: .destructive) { draft.slots.removeLast() }.disabled(draft.slots.count <= 1)
                    Button("预览另存并应用到当前学期") {
                        var copy = draft; copy.id = UUID().uuidString
                        prepare(copy, saveCopy: true)
                    }
                    Text("作息须有1–24节，连续编号，使用24小时制 HH:mm，按时间排序且不重叠。另存不修改其他学期使用的原方案。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                if pending != nil {
                    Section("应用预览") {
                        Text("只应用于 \(semester.title)")
                        if changes.isEmpty { Text("课程时间无需调整。").font(.caption) }
                        ForEach(Array(changes.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                        ForEach(Array(conflicts.enumerated()), id: \.offset) { Text($0.element).font(.caption).foregroundStyle(.orange) }
                        if !changes.isEmpty || !conflicts.isEmpty { Toggle("我已核对时间变化和冲突，确认保留", isOn: $confirmed) }
                        Button("确认应用") { apply() }
                            .disabled((!changes.isEmpty || !conflicts.isEmpty) && !confirmed)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("作息时间表").navigationBarTitleDisplayMode(.inline)
                .onChange(of: draft) { _ in clearPreview() }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.tint(CampusTheme.primary)
    }

    private func clearPreview() { pending = nil; changes = []; conflicts = []; confirmed = false; error = nil }
    private func prepare(_ table: AndroidTimeTable, saveCopy: Bool) {
        clearPreview()
        do {
            let next = try PersonalSemesterRules.applyTimeTable(table, to: semester.id, saveCopy: saveCopy, in: state)
            let old = try state.projectedCourses(semesterID: semester.id)
            let updated = try next.projectedCourses(semesterID: semester.id)
            let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
            changes = updated.compactMap { course in
                guard let previous = oldByID[course.id], previous.start != course.start || previous.end != course.end else { return nil }
                return "\(course.name)：\(previous.start)–\(previous.end) → \(course.start)–\(course.end)"
            }
            conflicts = try PersonalSemesterRules.conflicts(in: next, semesterID: semester.id)
            pending = next
        } catch { self.error = error.localizedDescription }
    }
    private func apply() {
        guard let pending, (changes.isEmpty && conflicts.isEmpty) || confirmed else { return }
        do { try save(pending); dismiss() } catch { self.error = error.localizedDescription }
    }
    private func addSlot() {
        guard let last = draft.slots.last, let clock = try? BackupValue.clock(last.end) else { error = "请先填好最后一节的结束时间。"; return }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let start = parts[0] * 60 + parts[1] + 10, end = start + 45
        guard end < 1440 else { error = "当天已没有更多可用时间。"; return }
        func format(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
        draft.slots.append(AndroidTimeSlot(number: draft.slots.count + 1, start: format(start), end: format(end)))
    }
}
