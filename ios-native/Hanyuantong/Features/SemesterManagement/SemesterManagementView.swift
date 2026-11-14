import SwiftUI

/// The owning store supplies an encrypted, atomic commit. Cancelled editors never call it.
struct SemesterManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state: AndroidScheduleState
    private let commit: (AndroidScheduleState) throws -> Void
    @State private var section = 0
    @State private var semesterDraft: AndroidSemester?
    @State private var courseDraft: AndroidManagedCourse?
    @State private var showingTimeTable = false
    @State private var removingSemester: AndroidSemester?
    @State private var removingCourse: AndroidManagedCourse?
    @State private var error: String?

    init(state: AndroidScheduleState, commit: @escaping (AndroidScheduleState) throws -> Void) {
        _state = State(initialValue: state); self.commit = commit
    }

    private var semester: AndroidSemester? { state.semesters.first { $0.id == state.activeSemesterId } }
    private var table: AndroidTimeTable? { state.timeTables.first { $0.id == semester?.timeTableId } }
    private var courses: [AndroidManagedCourse] { state.courses.filter { $0.semesterId == state.activeSemesterId } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("当前个人学期", selection: Binding(get: { state.activeSemesterId }, set: { id in
                        perform { try PersonalSemesterRules.selectSemester(id: id, in: state) }
                    })) {
                        ForEach(state.semesters) { Text($0.title).tag($0.id) }
                    }
                    Text("个人课表独立保存，切换或编辑不会改动学校同步记录。").font(.caption).foregroundStyle(CampusTheme.muted)
                    Picker("管理内容", selection: $section) {
                        Text("课程").tag(0); Text("学期").tag(1); Text("作息").tag(2)
                    }.pickerStyle(.segmented)
                }
                if section == 0 { courseSection }
                else if section == 1 { semesterSection }
                else { timeTableSection }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("semesterManagementError") } }
            }.navigationTitle("个人课表管理").navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden).background(CampusTheme.background)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .sheet(item: $semesterDraft) { draft in
                    PersonalSemesterEditor(semester: draft) { updated in
                        try apply(PersonalSemesterRules.saveSemester(updated, in: state))
                    }
                }
                .sheet(item: $courseDraft) { draft in
                    if let semester, let table {
                        PersonalManagedCourseEditor(course: draft, semester: semester, table: table, state: state) { updated in
                            try apply(PersonalSemesterRules.saveCourse(updated, in: state))
                        }
                    }
                }
                .sheet(isPresented: $showingTimeTable) {
                    if let semester, let table {
                        PersonalTimeTableEditor(state: state, semester: semester, table: table) { updated in try apply(updated) }
                    }
                }
                .confirmationDialog("删除这个个人学期及全部课程？", isPresented: Binding(get: { removingSemester != nil }, set: { if !$0 { removingSemester = nil } }), titleVisibility: .visible) {
                    Button("删除学期及其中的个人课程", role: .destructive) {
                        if let target = removingSemester { perform { try PersonalSemesterRules.deleteSemester(id: target.id, confirmed: true, in: state) } }
                        removingSemester = nil
                    }
                    Button("取消", role: .cancel) { removingSemester = nil }
                } message: {
                    Text("只删除“\(removingSemester?.title ?? "")”；其他学期、待办和学校记录保留。删除后只能从已有备份恢复。")
                }
                .confirmationDialog("删除这门课程的全部上课安排？", isPresented: Binding(get: { removingCourse != nil }, set: { if !$0 { removingCourse = nil } }), titleVisibility: .visible) {
                    Button("删除个人课程", role: .destructive) {
                        if let target = removingCourse { perform { try PersonalSemesterRules.deleteCourse(id: target.id, confirmed: true, in: state) } }
                        removingCourse = nil
                    }
                    Button("取消", role: .cancel) { removingCourse = nil }
                } message: { Text("只删除“\(removingCourse?.name ?? "")”及其安排，其他课程保留。") }
        }.tint(CampusTheme.primary)
    }

    private var courseSection: some View {
        Section("当前学期 · \(courses.count) 门课程") {
            if courses.isEmpty { Text("还没有个人课程，可添加一门课程和多个上课安排。").font(.subheadline).foregroundStyle(CampusTheme.muted) }
            ForEach(courses) { course in
                Button { courseDraft = course } label: {
                    HStack(spacing: 12) {
                        Circle().fill(CampusTheme.course(course.color)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(course.name).foregroundStyle(CampusTheme.text)
                            Text("\(course.arrangements.count) 个安排" + (course.teacher.isEmpty ? "" : " · \(course.teacher)"))
                                .font(.caption).foregroundStyle(CampusTheme.muted)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(CampusTheme.muted)
                    }
                }.swipeActions { Button("删除", role: .destructive) { removingCourse = course } }
            }
            Button { if let semester, let table { courseDraft = PersonalSemesterRules.newCourse(semester: semester, table: table) } } label: { Label("添加个人课程", systemImage: "plus") }
                .disabled(semester == nil || table == nil)
        }
    }

    private var semesterSection: some View {
        Section("学期与教学周") {
            if let semester {
                LabeledContent("学期", value: semester.title)
                LabeledContent("学期起始日期", value: semester.startDate)
                LabeledContent("第一教学周周一", value: semester.weekStartDate)
                LabeledContent("教学周数量", value: "\(semester.weekCount) 周")
                Button("编辑当前学期") { semesterDraft = semester }
                Button("删除当前学期", role: .destructive) { removingSemester = semester }.disabled(state.semesters.count <= 1)
            }
            Button { newSemester() } label: { Label("新建学期", systemImage: "plus") }
            Text("按校历设置第一周周一。缩短教学周时，须先调整超出范围的课程；不会自动裁掉安排。至少保留一个学期。").font(.caption).foregroundStyle(CampusTheme.muted)
        }
    }

    private var timeTableSection: some View {
        Section("作息时间表") {
            if let table {
                Text(table.name).font(.headline)
                ForEach(table.slots, id: \.number) { slot in
                    LabeledContent("第 \(slot.number) 节", value: "\(slot.start)–\(slot.end)")
                }
                Button("管理作息方案") { showingTimeTable = true }
            }
            Text("仅“按节次”安排随作息联动。旧版和自定义时间课程保持原时间，另存方案只应用于当前学期。").font(.caption).foregroundStyle(CampusTheme.muted)
        }
    }

    private func newSemester() {
        guard let original = semester else { return }
        let start = BackupValue.dayDate(original.weekStartDate)
        let next = ScheduleMath.calendar.date(byAdding: .day, value: 182, to: start) ?? start
        let year = ScheduleMath.calendar.component(.year, from: next)
        let autumn = ScheduleMath.calendar.component(.month, from: next) >= 7
        let firstYear = autumn ? year : year - 1
        semesterDraft = AndroidSemester(id: UUID().uuidString, academicYear: "\(firstYear)–\(firstYear + 1)", season: autumn ? "秋季" : "春季", startDate: BackupValue.dayString(next), weekStartDate: BackupValue.dayString(next), weekCount: 18, timeTableId: original.timeTableId)
    }

    private func perform(_ operation: () throws -> AndroidScheduleState) {
        do { try apply(operation()); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func apply(_ next: AndroidScheduleState) throws {
        let clean = try PersonalSemesterRules.validated(next)
        try commit(clean)
        state = clean; error = nil
    }
}

private struct PersonalSemesterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var semester: AndroidSemester
    let save: (AndroidSemester) throws -> Void
    @State private var error: String?
    init(semester: AndroidSemester, save: @escaping (AndroidSemester) throws -> Void) {
        _semester = State(initialValue: semester); self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("学期信息") {
                    TextField("学年", text: $semester.academicYear)
                    Picker("学期", selection: $semester.season) { Text("春季").tag("春季"); Text("秋季").tag("秋季") }
                    DatePicker("学期起始日期", selection: dateBinding(\.startDate), displayedComponents: .date)
                    DatePicker("第一教学周周一", selection: dateBinding(\.weekStartDate), displayedComponents: .date)
                    Stepper("\(semester.weekCount) 个教学周", value: $semester.weekCount, in: 1...40)
                    if ScheduleMath.weekday(on: BackupValue.dayDate(semester.weekStartDate)) != 1 {
                        Text("第一教学周必须从星期一开始。").font(.caption).foregroundStyle(.red)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("学期与教学周").navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone, ScheduleMath.calendar.timeZone)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { do { try save(semester); dismiss() } catch { self.error = error.localizedDescription } } }
                }
        }
    }
    private func dateBinding(_ key: WritableKeyPath<AndroidSemester, String>) -> Binding<Date> {
        Binding(get: { BackupValue.dayDate(semester[keyPath: key]) }, set: { semester[keyPath: key] = BackupValue.dayString($0) })
    }
}
