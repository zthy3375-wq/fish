import SwiftUI

struct CampusAgendaView: View {
    let embedded: Bool
    let sharedDay: Binding<Date>?
    @EnvironmentObject private var campus: CampusStore
    @EnvironmentObject private var learning: LearningStore
    @State private var localDay = Date()
    @State private var range = 1
    @State private var kind: AgendaKind = .all
    @State private var task: CampusTask?

    private enum AgendaKind: String, CaseIterable, Identifiable {
        case all = "全部安排"
        case course = "课程"
        case exam = "考试"
        case task = "任务"
        var id: Self { self }
    }

    init(embedded: Bool = false, sharedDay: Binding<Date>? = nil) {
        self.embedded = embedded
        self.sharedDay = sharedDay
    }

    private var selectedDay: Binding<Date> { sharedDay ?? $localDay }
    private var days: [Date] {
        let calendar = ScheduleMath.calendar
        let start = calendar.startOfDay(for: selectedDay.wrappedValue)
        return (0..<range).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        if embedded { agendaList } else { agendaList.navigationTitle("统一日程") }
    }

    private var agendaList: some View {
        List {
            Section {
                HStack(spacing: 5) {
                    Button { moveDay(-1) } label: { chevron("chevron.left", label: "前一天日程") }
                    DatePicker("日程日期", selection: selectedDay, displayedComponents: .date).labelsHidden()
                    Button { moveDay(1) } label: { chevron("chevron.right", label: "后一天日程") }
                    Spacer(minLength: 0)
                    Button("今天") { selectedDay.wrappedValue = Date() }.frame(minHeight: 44)
                }.buttonStyle(.borderless)
                HStack(spacing: 10) {
                    Picker("日程范围", selection: $range) {
                        Text("当天").tag(1)
                        Text("未来7天").tag(7)
                    }.pickerStyle(.segmented)
                    Button("周视图", action: openWeek).buttonStyle(.borderless).frame(minHeight: 44)
                }
                Picker("日程类型", selection: $kind) {
                    ForEach(AgendaKind.allCases) { value in Text(value.rawValue).tag(value) }
                }.pickerStyle(.menu)
            }
            ForEach(days, id: \.self) { day in
                Section {
                    agendaRows(for: day)
                } header: {
                    Text(CampusTheme.date(day))
                }
            }
        }
        .environment(\.timeZone, ScheduleMath.calendar.timeZone)
        .sheet(item: $task) { TaskEditorView(task: $0) }
    }

    private func chevron(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol).frame(width: 38, height: 44).accessibilityLabel(label)
    }

    private func moveDay(_ offset: Int) {
        if let day = ScheduleMath.calendar.date(byAdding: .day, value: offset, to: selectedDay.wrappedValue) {
            selectedDay.wrappedValue = day
        }
    }

    private func openWeek() {
        if let monday = ScheduleMath.calendar.dateInterval(of: .weekOfYear, for: selectedDay.wrappedValue)?.start {
            selectedDay.wrappedValue = monday
        }
        range = 7
    }

    @ViewBuilder private func agendaRows(for day: Date) -> some View {
        let calendar = ScheduleMath.calendar
        let key = TaskClock.day(day)
        let courses = kind == .all || kind == .course ? campus.courses(on: day) : []
        let exams = kind == .all || kind == .exam ? campus.exams.filter { exam in
            NativeExamPresentation.day(exam).map { calendar.isDate($0, inSameDayAs: day) } ?? false
        } : []
        let showTasks = kind == .all || kind == .task
        let tasks = showTasks ? campus.tasks.filter { task in
            !task.completed && (TaskRules.plannedDay(task) == key || task.deadline.map(TaskClock.day) == key)
        } : []
        let learningItems = showTasks ? learning.cache.items.filter { item in
            guard item.status != "submitted", item.status != "closed" else { return false }
            return item.deadline?.prefix(10) == Substring(key) || learning.cache.plans[item.id]?.plannedDay == key
        } : []

        ForEach(courses) { course in
            NavigationLink { CourseDetailView(course: course, occurrenceDate: day) } label: { CourseRow(course: course) }
        }
        ForEach(exams) { exam in
            NavigationLink { AcademicRecordsView(initialSelection: 1) } label: {
                agendaLabel(exam.name, detail: [exam.time, exam.room].filter { !$0.isEmpty }.joined(separator: " · "), icon: "calendar.badge.clock")
            }
        }
        ForEach(tasks) { item in
            if TaskRules.plannedDay(item) == key {
                Button { task = item } label: {
                    agendaLabel(item.title, detail: item.plannedAt.map { CampusTheme.date($0, format: "HH:mm") } ?? "当天安排", icon: "checklist")
                }
            }
            if let deadline = item.deadline, TaskClock.day(deadline) == key {
                Button { task = item } label: {
                    agendaLabel(item.title, detail: "截止 " + CampusTheme.date(deadline, format: "HH:mm"), icon: "clock.badge.exclamationmark")
                }
            }
        }
        ForEach(learningItems) { item in
            if learning.cache.plans[item.id]?.plannedDay == key {
                Button { learning.openItem(item) } label: {
                    agendaLabel(item.title, detail: "学习通计划 · " + LearningDisplay.state(item).label, icon: "book")
                }.disabled(!item.hasLink)
            }
            if let deadline = item.deadline, deadline.prefix(10) == Substring(key) {
                Button { learning.openItem(item) } label: {
                    let time = String(deadline.dropFirst(11))
                    agendaLabel(item.title, detail: time.isEmpty ? "学习通截止" : "学习通截止 " + time, icon: "clock.badge.exclamationmark")
                }.disabled(!item.hasLink)
            }
        }
        if courses.isEmpty && exams.isEmpty && tasks.isEmpty && learningItems.isEmpty {
            Text("暂无已知安排").foregroundStyle(CampusTheme.muted)
        }
    }

    private func agendaLabel(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(CampusTheme.text)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(CampusTheme.muted) }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(CampusTheme.primary)
        }
    }
}

struct SemesterCalendar:View {
    @EnvironmentObject var campus:CampusStore
    @Environment(\.dismiss) var dismiss
    private var start:Date { campus.isConnected ? campus.schoolSemesterStart : campus.semesterStart }
    private var weeks:Int {
        if campus.isConnected { return min(60,campus.courses.filter{$0.source == "school"}.flatMap(\.weeks).max() ?? 0) }
        return min(60,campus.personalWeekCount)
    }
    var body:some View {
        List {
            Section("第一周周一") {
                Text(CampusTheme.date(start,format:"yyyy年M月d日"))
                Text(campus.isConnected ? "按校准日期及已保存学校课程的教学周显示。" : "按当前个人学期设置显示。").font(.footnote).foregroundStyle(.secondary)
            }
            if weeks == 0 { Text("同步学校课表后显示教学周。") }
            else {
                ForEach(1...max(1,weeks),id:\.self) { week in
                    if let monday=ScheduleMath.calendar.date(byAdding:.weekOfYear,value:week-1,to:start),
                       let sunday=ScheduleMath.calendar.date(byAdding:.day,value:6,to:monday) {
                        Button { campus.selectedDate=monday; dismiss(); campus.selectedTab = .schedule } label: {
                            HStack {
                                Text("第 \(week) 周"); Spacer()
                                Text(CampusTheme.date(monday,format:"M.d") + " – " + CampusTheme.date(sunday,format:"M.d"))
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }.accessibilityHint("打开这一周的课表")
                    }
                }
            }
        }.navigationTitle("学期校历")
    }
}
