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
    @State private var learningDetail: LearningItem?

    private enum Entry: Identifiable {
        case course(Course)
        case exam(ExamRecord)
        case personal(CampusTask, deadline: Bool)
        case official(LearningItem, kind: OfficialKind)

        enum OfficialKind: String { case plan, deadline, exam }

        var id: String {
            switch self {
            case .course(let value): return "course/" + value.id.uuidString
            case .exam(let value): return "exam/" + String(describing: value.id)
            case .personal(let value, let deadline): return (deadline ? "deadline/" : "plan/") + value.id.uuidString
            case .official(let value, let kind): return "learning/" + kind.rawValue + "/" + value.id
            }
        }

        var minute: Int? {
            switch self {
            case .course(let value):
                return TimetableDay.minutes(value.start)
            case .exam(let value):
                let separated = value.time.components(separatedBy: CharacterSet(charactersIn: "-–—~至"))
                guard separated.count == 2,
                      let start = TimetableDay.minutes(separated[0].trimmingCharacters(in: .whitespaces)),
                      let end = TimetableDay.minutes(separated[1].trimmingCharacters(in: .whitespaces)), end > start else { return nil }
                return start
            case .personal(let value, let deadline):
                return (deadline ? value.deadline : value.plannedAt).map(Self.minuteOfDay)
            case .official(let value, let kind):
                let stamp = kind == .exam ? value.startAt : kind == .deadline ? value.deadline : nil
                return LearningDisplay.date(stamp).map(Self.minuteOfDay)
            }
        }

        private static func minuteOfDay(_ date: Date) -> Int {
            let clock = ScheduleMath.calendar
            return clock.component(.hour, from: date) * 60 + clock.component(.minute, from: date)
        }
    }

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
                let entries = agendaEntries(for: day)
                Section {
                    if entries.isEmpty { Text("暂无已知安排").foregroundStyle(CampusTheme.muted) }
                    ForEach(entries) { entry in agendaRow(entry, day: day) }
                } header: {
                    Text(CampusTheme.date(day))
                }
            }
        }
        .environment(\.timeZone, ScheduleMath.calendar.timeZone)
        .sheet(item: $task) { TaskEditorView(task: $0) }
        .background {
            if !embedded { LearningPresenterAnchor { learning.attachPresenter($0) }.frame(width: 0, height: 0) }
        }
        .onChange(of: learning.cache.account) { _ in learningDetail = nil }
        .sheet(item: $learningDetail) { item in
            LearningItemDetail(store: learning, item: item) {
                let account = learning.cache.account
                learningDetail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if learning.cache.account == account { learning.openItem(item) }
                }
            }
        }
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

    private func agendaEntries(for day: Date) -> [Entry] {
        let key = TaskClock.day(day)
        var entries: [Entry] = []
        if kind == .all || kind == .course { entries += campus.courses(on: day).map(Entry.course) }
        if kind == .all || kind == .exam {
            entries += campus.exams.filter { NativeExamPresentation.day($0).map(TaskClock.day) == key }.map(Entry.exam)
        }
        let showTasks = kind == .all || kind == .task
        if showTasks {
            for task in campus.tasks where !task.completed {
                if TaskRules.plannedDay(task) == key { entries.append(.personal(task, deadline: false)) }
                if task.deadline.map(TaskClock.day) == key { entries.append(.personal(task, deadline: true)) }
            }
        }
        if learning.connected {
            for item in learning.cache.items {
                let examStart = item.kind == "exam" ? LearningDisplay.date(item.startAt) : nil
                if (kind == .all || kind == .exam), examStart.map(TaskClock.day) == key {
                    entries.append(.official(item, kind: .exam))
                }
                guard showTasks, item.status != "submitted", item.status != "closed" else { continue }
                if learning.cache.plans[item.id]?.plannedDay == key { entries.append(.official(item, kind: .plan)) }
                if examStart == nil, item.deadline?.prefix(10) == Substring(key) { entries.append(.official(item, kind: .deadline)) }
            }
        }
        return entries.sorted {
            let first = $0.minute ?? Int.max, second = $1.minute ?? Int.max
            return first == second ? $0.id < $1.id : first < second
        }
    }

    @ViewBuilder private func agendaRow(_ entry: Entry, day: Date) -> some View {
        switch entry {
        case .course(let course):
            NavigationLink { CourseDetailView(course: course, occurrenceDate: day) } label: { CourseRow(course: course) }
        case .exam(let exam):
            NavigationLink { AcademicRecordsView(initialSelection: 1) } label: {
                agendaLabel(exam.name, detail: [exam.time, exam.room].filter { !$0.isEmpty }.joined(separator: " · "), icon: "calendar.badge.clock")
            }
        case .personal(let item, let deadline):
            Button { task = item } label: {
                let time = (deadline ? item.deadline : item.plannedAt).map { CampusTheme.date($0, format: "HH:mm") }
                agendaLabel(item.title, detail: deadline ? "截止 " + (time ?? "") : time ?? "当天安排",
                            icon: deadline ? "clock.badge.exclamationmark" : "checklist")
            }
        case .official(let item, let kind):
            Button { learningDetail = item } label: {
                switch kind {
                case .plan:
                    agendaLabel(item.title, detail: "学习通计划 · " + LearningDisplay.state(item).label, icon: "book")
                case .deadline:
                    agendaLabel(item.title, detail: "学习通 · " + LearningDisplay.deadline(item), icon: "clock.badge.exclamationmark")
                case .exam:
                    let start = item.startAt.map { String($0.dropFirst(11)) } ?? ""
                    let finish = item.deadline.map { String($0.dropFirst(11)) } ?? "结束未知"
                    agendaLabel(item.title, detail: start + "–" + finish + " · 学习通考试", icon: "calendar.badge.clock")
                }
            }
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
