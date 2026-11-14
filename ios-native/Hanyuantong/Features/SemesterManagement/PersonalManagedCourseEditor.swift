import SwiftUI

struct PersonalManagedCourseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var course: AndroidManagedCourse
    let semester: AndroidSemester
    let table: AndroidTimeTable
    let state: AndroidScheduleState
    let save: (AndroidManagedCourse) throws -> Void
    @State private var arrangementDraft: AndroidArrangement?
    @State private var removing: AndroidArrangement?
    @State private var conflictMessages: [String] = []
    @State private var showingConflicts = false
    @State private var error: String?

    init(course: AndroidManagedCourse, semester: AndroidSemester, table: AndroidTimeTable, state: AndroidScheduleState, save: @escaping (AndroidManagedCourse) throws -> Void) {
        _course = State(initialValue: course); self.semester = semester; self.table = table; self.state = state; self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("个人课程") {
                    TextField("课程名称", text: $course.name)
                    TextField("教师（选填）", text: $course.teacher)
                    Picker("颜色", selection: $course.color) {
                        Text("蓝色").tag("blue"); Text("紫色").tag("purple"); Text("绿色").tag("green"); Text("橙色").tag("orange")
                    }
                    TextField("备注（选填）", text: $course.notes, axis: .vertical).lineLimit(3...6)
                }
                Section("上课安排 · \(course.arrangements.count) 个") {
                    ForEach(course.arrangements) { arrangement in
                        Button { arrangementDraft = arrangement } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("周\(arrangement.day) · \(arrangement.start)–\(arrangement.end)").foregroundStyle(CampusTheme.text)
                                Text("第\(arrangement.startWeek)–\(arrangement.endWeek)周 · \(ruleTitle(arrangement.rule)) · \(arrangement.timeMode == "period" ? "按节次" : "自定义时间")")
                                    .font(.caption).foregroundStyle(CampusTheme.muted)
                                if !arrangement.room.isEmpty { Text(arrangement.room).font(.caption).foregroundStyle(CampusTheme.muted) }
                            }
                        }.swipeActions { Button("删除", role: .destructive) { removing = arrangement }.disabled(course.arrangements.count <= 1) }
                    }
                    Button { arrangementDraft = PersonalSemesterRules.newArrangement(semester: semester, table: table) } label: { Label("添加上课安排", systemImage: "plus") }
                        .disabled(course.arrangements.count >= 100)
                    Text("课程名称、教师、颜色和备注由所有安排共用；每个安排可单独设置地点、时间、周次和单双周。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("编辑个人课程").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { prepareSave() } }
                }
                .sheet(item: $arrangementDraft) { draft in
                    PersonalArrangementEditor(arrangement: draft, semester: semester, table: table) { updated in
                        if let index = course.arrangements.firstIndex(where: { $0.id == updated.id }) { course.arrangements[index] = updated }
                        else { course.arrangements.append(updated) }
                    }
                }
                .confirmationDialog("删除这个上课安排？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                    Button("删除安排", role: .destructive) {
                        if let removing, course.arrangements.count > 1 { course.arrangements.removeAll { $0.id == removing.id } }
                        removing = nil
                    }
                    Button("取消", role: .cancel) { removing = nil }
                } message: { Text("其他上课安排保留；保存课程后才会写入本机。") }
                .confirmationDialog("存在时间重叠，确认保留？", isPresented: $showingConflicts, titleVisibility: .visible) {
                    Button("已核对，保留并保存") { finishSave() }
                    Button("返回修改", role: .cancel) { }
                } message: { Text(conflictMessages.prefix(8).joined(separator: "\n")) }
        }.tint(CampusTheme.primary)
    }
    private func prepareSave() {
        do {
            let next = try PersonalSemesterRules.saveCourse(course, in: state)
            conflictMessages = try PersonalSemesterRules.conflicts(in: next, semesterID: semester.id)
            if conflictMessages.isEmpty { finishSave() } else { showingConflicts = true }
        } catch { self.error = error.localizedDescription }
    }
    private func finishSave() {
        do { try save(course); dismiss() } catch { self.error = error.localizedDescription }
    }
    private func ruleTitle(_ rule: String) -> String {
        switch rule { case "odd": return "单周"; case "even": return "双周"; case "custom": return "指定周"; default: return "每周" }
    }
}

private struct PersonalArrangementEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var arrangement: AndroidArrangement
    let semester: AndroidSemester
    let table: AndroidTimeTable
    let save: (AndroidArrangement) -> Void
    @State private var customWeeks: String
    @State private var error: String?

    init(arrangement: AndroidArrangement, semester: AndroidSemester, table: AndroidTimeTable, save: @escaping (AndroidArrangement) -> Void) {
        _arrangement = State(initialValue: arrangement); _customWeeks = State(initialValue: arrangement.customWeeks.map(String.init).joined(separator: ","))
        self.semester = semester; self.table = table; self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("时间与地点") {
                    Picker("星期", selection: $arrangement.day) { ForEach(1...7, id: \.self) { Text("周" + ["一", "二", "三", "四", "五", "六", "日"][$0 - 1]).tag($0) } }
                    TextField("地点（选填）", text: $arrangement.room)
                    Picker("时间方式", selection: $arrangement.timeMode) { Text("按节次").tag("period"); Text("自定义时间").tag("custom") }
                        .onChange(of: arrangement.timeMode) { mode in
                            if mode == "period" {
                                if !(1...max(1, table.slots.count)).contains(arrangement.startPeriod ?? 0) { arrangement.startPeriod = 1 }
                                if !(1...max(1, table.slots.count)).contains(arrangement.endPeriod ?? 0) { arrangement.endPeriod = arrangement.startPeriod }
                                resolvePeriods()
                            }
                        }
                    if arrangement.timeMode == "period" {
                        periodPicker("开始节次", value: $arrangement.startPeriod).onChange(of: arrangement.startPeriod) { _ in resolvePeriods() }
                        periodPicker("结束节次", value: $arrangement.endPeriod).onChange(of: arrangement.endPeriod) { _ in resolvePeriods() }
                        Text("按“\(table.name)”的节次计算，上课时间会随本学期作息联动。").font(.caption).foregroundStyle(CampusTheme.muted)
                    } else {
                        TextField("开始时间 HH:mm", text: $arrangement.start).keyboardType(.numbersAndPunctuation)
                        TextField("结束时间 HH:mm", text: $arrangement.end).keyboardType(.numbersAndPunctuation)
                        Button("清除节次标记") { arrangement.startPeriod = nil; arrangement.endPeriod = nil }
                        Text("保留自定义时钟时间，不跟随作息变化。").font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                }
                Section("教学周") {
                    Stepper("从第 \(arrangement.startWeek) 周", value: $arrangement.startWeek, in: 1...semester.weekCount)
                    Stepper("到第 \(arrangement.endWeek) 周", value: $arrangement.endWeek, in: 1...semester.weekCount)
                    Picker("周规则", selection: $arrangement.rule) { Text("每周").tag("all"); Text("单周").tag("odd"); Text("双周").tag("even"); Text("指定周").tag("custom") }
                    if arrangement.rule == "custom" {
                        TextField("如 1,3,5 或 1-4,8", text: $customWeeks).keyboardType(.numbersAndPunctuation)
                        Text("指定周必须在上述起止周之间。").font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("上课安排").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存安排") { apply() } }
                }
        }
    }
    private func periodPicker(_ title: String, value: Binding<Int?>) -> some View {
        Picker(title, selection: value) { ForEach(table.slots, id: \.number) { Text("第 \($0.number) 节 · \($0.start)–\($0.end)").tag(Optional($0.number)) } }
    }
    private func resolvePeriods() {
        guard arrangement.timeMode == "period", let first = arrangement.startPeriod, var last = arrangement.endPeriod else { return }
        if last < first { last = first; arrangement.endPeriod = first }
        if let start = table.slots.first(where: { $0.number == first }), let end = table.slots.first(where: { $0.number == last }) {
            arrangement.start = start.start; arrangement.end = end.end
        }
    }
    private func apply() {
        do {
            var draft = arrangement
            draft.customWeeks = draft.rule == "custom" ? try PersonalSemesterRules.parseCustomWeeks(customWeeks) : []
            // Reuse the one strict Android schema validator, including period resolution and empty-week rejection.
            let course = AndroidManagedCourse(id: "arrangement-preview", semesterId: semester.id, name: "安排", teacher: "", color: "blue", notes: "", arrangements: [draft])
            let preview = AndroidScheduleState(timeTables: [table], mode: "personal", activeSemesterId: semester.id, semesters: [semester], courses: [course], reminders: AndroidScheduleReminders(enabled: false, minutes: 10), updatedAt: BackupValue.timestampString(Date()))
            let clean = try preview.validated()
            guard let result = clean.courses.first?.arrangements.first else { return }
            save(result); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
