import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: CampusStore
    @State private var mode = 0
    @State private var adding = false
    @State private var managingPersonalSchedule = false
    private var days: [Date] {
        let calendar = CampusTheme.calendar
        let weekday = (calendar.component(.weekday, from: store.selectedDate) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: store.selectedDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if store.pausedCourseAdjustments > 0 { Text("学校原安排已变化，\(store.pausedCourseAdjustments) 条按周调课记录已暂停，请按新课表重新核对。").font(.caption).foregroundStyle(CampusTheme.muted) }
                Picker("课表视图", selection: $mode) { Text("周课表").tag(0); Text("日程").tag(1) }.pickerStyle(.segmented)
                HStack {
                    Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一周")
                    Spacer()
                    VStack(spacing: 5) {
                        Text("\(store.isConnected ? "学校" : "个人")第\(store.week(for: store.selectedDate))周").font(.headline)
                        Text(CampusTheme.date(store.selectedDate, format: "yyyy年M月")).font(.caption).foregroundStyle(CampusTheme.muted)
                        if store.isConnected, store.courses.contains(where: { $0.source == "personal" }) {
                            Text("个人第\(ScheduleMath.week(on: store.selectedDate, start: store.semesterStart))周").font(.caption).foregroundStyle(CampusTheme.muted)
                        }
                    }
                    Spacer()
                    Button { shift(7) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下一周")
                }
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { date in
                        Button { store.selectedDate = date } label: {
                            VStack(spacing: 9) { Text(CampusTheme.date(date, format: "EE")).font(.caption2); Text(CampusTheme.date(date, format: "d")).font(.subheadline.weight(.semibold)); Circle().fill(CampusTheme.calendar.isDate(date, inSameDayAs: Date()) ? CampusTheme.primary : .clear).frame(width: 4, height: 4) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(CampusTheme.calendar.isDate(date, inSameDayAs: store.selectedDate) ? CampusTheme.tint : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel(CampusTheme.date(date)).accessibilityAddTraits(CampusTheme.calendar.isDate(date, inSameDayAs: store.selectedDate) ? .isSelected : [])
                    }
                }
                if mode == 0 { weekList } else { dayList }
                if !store.practice.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("实践教学").font(.headline)
                        ForEach(store.practice) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).font(.subheadline.weight(.semibold))
                                Text([item.teacher, item.weeks.isEmpty ? "" : "第\(item.weeks)周"].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(CampusTheme.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).campusCard()
                        }
                    }
                }
                if !store.isConnected {
                    Button { store.connectSchool() } label: { Label("连接教务系统", systemImage: "link").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.bordered).disabled(store.isBusy)
                }
            }.padding(20).frame(maxWidth: 680)
        }.background(CampusTheme.background).navigationTitle("我的课表").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("今天") { store.selectedDate = Date() } }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { managingPersonalSchedule = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("管理个人课表").accessibilityIdentifier("manage-personal-schedule")
                    Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加课程")
                }
            }.sheet(isPresented: $adding) { CourseEditorView() }
            .sheet(isPresented: $managingPersonalSchedule) { PersonalScheduleSettingsSheet() }
    }
    private var dayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CampusTheme.date(store.selectedDate)).font(.headline)
            if store.courses(on: store.selectedDate).isEmpty { CampusEmpty(title: "这一天没有课程", detail: "可以添加自己的学习安排", symbol: "calendar") }
            ForEach(store.courses(on: store.selectedDate)) { course in NavigationLink { CourseDetailView(course: course, occurrenceDate: store.selectedDate) } label: { CourseRow(course: course) }.buttonStyle(.plain) }
        }
    }
    private var weekList: some View {
        TimetableGrid(days: days, courses: days.map { store.courses(on: $0) })
    }
    private func shift(_ amount: Int) { if let date = CampusTheme.calendar.date(byAdding: .day, value: amount, to: store.selectedDate) { store.selectedDate = date } }
}

/// A shared minute axis keeps free periods and simultaneous classes visible.
/// Every overlapping event has its own lane; lanes never shrink below readable width.
private struct TimetableGrid: View {
    let days: [Date]
    let courses: [[Course]]
    @ScaledMetric(relativeTo: .caption) private var laneWidth: CGFloat = 112
    @ScaledMetric(relativeTo: .caption) private var minuteHeight: CGFloat = 1.4
    private let timeWidth: CGFloat = 54
    private let headerHeight: CGFloat = 48
    private var layouts: [TimetableDay] { courses.map(TimetableDay.init) }
    private var firstMinute: Int {
        min(480, (layouts.flatMap(\.events).map(\.start).min() ?? 480) / 60 * 60)
    }
    private var lastMinute: Int {
        max(1320, ((layouts.flatMap(\.events).map(\.end).max() ?? 1320) + 59) / 60 * 60)
    }
    private var height: CGFloat { CGFloat(lastMinute - firstMinute) * minuteHeight }
    private var hours: [Int] { Array(stride(from: firstMinute, through: lastMinute, by: 60)) }
    private func dayWidth(_ layout: TimetableDay) -> CGFloat { CGFloat(layout.laneCount) * laneWidth }
    private func y(_ minute: Int) -> CGFloat { CGFloat(minute - firstMinute) * minuteHeight }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按上课时间排列 · 左右滑动查看整周").font(.caption).foregroundStyle(CampusTheme.muted)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Text("时间").font(.caption).frame(width: timeWidth, height: headerHeight)
                        ZStack(alignment: .topLeading) {
                            ForEach(hours, id: \.self) { minute in
                                Text(String(format: "%02d:%02d", minute / 60, minute % 60))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(CampusTheme.muted)
                                    .frame(width: timeWidth, alignment: .center).offset(y: y(minute))
                            }
                        }.frame(width: timeWidth, height: height + 20, alignment: .topLeading)
                    }.accessibilityHidden(true)
                    ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                        dayColumn(date, layout: layouts[index])
                    }
                }
            }.background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CampusTheme.border, lineWidth: 0.7))
        }
    }
    private func dayColumn(_ date: Date, layout: TimetableDay) -> some View {
        VStack(spacing: 0) {
            Text(CampusTheme.date(date, format: "EE M/d"))
                .font(.caption.weight(.semibold)).frame(width: dayWidth(layout), height: headerHeight)
                .background(CampusTheme.calendar.isDateInToday(date) ? CampusTheme.tint : CampusTheme.background)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(CampusTheme.border).frame(width: 0.5, height: height)
                ForEach(hours, id: \.self) { minute in
                    Rectangle().fill(CampusTheme.border.opacity(0.7)).frame(width: dayWidth(layout), height: 0.5).offset(y: y(minute))
                }
                if layout.events.isEmpty {
                    Text("无课").font(.caption).foregroundStyle(CampusTheme.muted)
                        .frame(width: dayWidth(layout)).padding(.top, 22)
                }
                ForEach(layout.events) { event in
                    NavigationLink { CourseDetailView(course: event.course, occurrenceDate: date) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.course.name).font(.caption.weight(.semibold)).lineLimit(3)
                            Text(event.course.room).font(.caption2).lineLimit(2)
                            Text("\(event.course.start)–\(event.course.end)").font(.caption2.monospacedDigit()).lineLimit(1)
                            if !event.course.period.isEmpty { Text(event.course.period).font(.caption2).lineLimit(1) }
                        }.padding(6).frame(width: laneWidth - 6, height: max(1, CGFloat(event.end - event.start) * minuteHeight - 3), alignment: .topLeading)
                            .foregroundStyle(CampusTheme.course(event.course.color))
                            .background(CampusTheme.course(event.course.color).opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                            .clipped().contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(CampusTheme.date(date))，\(event.course.name)，\(event.course.start)至\(event.course.end)，\(event.course.room)，\(event.course.period)")
                        .offset(x: CGFloat(event.lane) * laneWidth + 3, y: y(event.start))
                }
            }.frame(width: dayWidth(layout), height: height + 20, alignment: .topLeading)
        }
    }
}

private struct TimetableEvent: Identifiable {
    let course: Course
    let start: Int
    let end: Int
    let lane: Int
    var id: UUID { course.id }
}

private struct TimetableDay {
    let events: [TimetableEvent]
    let laneCount: Int
    init(_ courses: [Course]) {
        var output: [TimetableEvent] = []
        var laneEnds: [Int] = []
        for course in courses.sorted(by: { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }) {
            guard let start = Self.minutes(course.start), let end = Self.minutes(course.end), end > start else { continue }
            let lane = laneEnds.firstIndex(where: { $0 <= start }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            output.append(TimetableEvent(course: course, start: start, end: end, lane: lane))
        }
        events = output
        laneCount = max(1, laneEnds.count)
    }
    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

struct CourseDetailView: View {
    @EnvironmentObject var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    let course: Course
    var occurrenceDate: Date? = nil
    @State private var confirming = false
    @State private var adjusting: SchoolCourseAdjustmentContext?
    @State private var restoring: SchoolCourseAdjustmentContext?
    @State private var error: String?
    var body: some View {
        Group {
            if let current = store.courses.first(where: { $0.id == course.id }) {
                details(current)
            } else {
                CampusEmpty(title: "课程记录已更新", detail: "该课程已删除、刷新或退出账号。请返回课表重新查看。", symbol: "calendar.badge.exclamationmark")
                    .padding(20)
            }
        }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
    }
    private func details(_ course: Course) -> some View {
        List {
            Section { Text(course.name).font(.title2.weight(.semibold)).padding(.vertical, 8) }
            Section("课程信息") {
                LabeledContent("教师", value: course.teacher.isEmpty ? "未提供" : course.teacher)
                LabeledContent("地点", value: course.room.isEmpty ? "未提供" : course.room)
                LabeledContent("上课时间", value: "\(course.start)–\(course.end)")
                LabeledContent("星期", value: ["一", "二", "三", "四", "五", "六", "日"][min(7, max(1, course.day)) - 1])
                if !course.period.isEmpty { LabeledContent("节次", value: course.period) }
                LabeledContent("教学周", value: course.weeks.map(String.init).joined(separator: "、"))
                LabeledContent("来源", value: course.source == "personal" ? "个人课程" : (course.locallyAdjusted == true ? "学校课程 · 已在本机调课" : "教务系统"))
                if !course.notes.isEmpty { Text(course.notes) }
            }
            if course.source == "school" {
                Section {
                    Button("调整时间/地点") {
                        if let context = store.schoolAdjustmentContext(for: course, date: occurrenceDate ?? Date()) { adjusting = context }
                        else { error = "学校原安排已变化或存在重复，请返回课表同步后重新核对。" }
                    }.accessibilityIdentifier("adjust-school-course")
                    if store.hasSchoolAdjustment(for: course) {
                        Button("恢复学校安排") { restoring = store.schoolAdjustmentContext(for: course, date: occurrenceDate ?? Date()) }
                    }
                    Text("只调整本人课表，不修改教务系统。可按周选择生效范围。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if course.source == "personal" { Section { Button("删除这个上课安排", role: .destructive) { confirming = true } } }
        }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $adjusting) { context in SchoolCourseAdjustmentView(context: context, onSaved: { dismiss() }).environmentObject(store) }
            .confirmationDialog("恢复这项上课安排所有周次的学校时间和地点？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
                Button("确认恢复") {
                    guard let context = restoring else { return }
                    do { try store.restoreSchoolAdjustment(context); dismiss() } catch { self.error = error.localizedDescription }
                    restoring = nil
                }
                Button("取消", role: .cancel) { restoring = nil }
            }
            .confirmationDialog("删除这个个人上课安排？", isPresented: $confirming, titleVisibility: .visible) {
                Button("删除安排", role: .destructive) {
                    store.deleteCourse(course.id)
                    if !store.courses.contains(where: { $0.id == course.id }) { dismiss() }
                }
                Button("取消", role: .cancel) { }
            } message: { Text("只删除当前安排；同一课程的其他安排及其他学期保留。若这是最后一个安排，该个人课程也会移除。") }
    }
}

struct CourseEditorView: View {
    @EnvironmentObject var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var teacher = ""
    @State private var room = ""
    @State private var day = 1
    @State private var firstWeek = 1
    @State private var lastWeek = 1
    @State private var initializedWeeks = false
    @State private var saveError: String?
    @State private var expectedSemesterID: String?
    @State private var courseID = UUID()
    @State private var start = CampusTheme.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8))!
    @State private var end = CampusTheme.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 40))!
    private var maximumWeek: Int { max(1, store.personalWeekCount) }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end > start && firstWeek <= lastWeek
            && firstWeek >= 1 && lastWeek <= maximumWeek
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("个人课程") { TextField("课程名称", text: $name); TextField("教师（选填）", text: $teacher); TextField("地点（选填）", text: $room) }
                Section("上课时间") {
                    Picker("星期", selection: $day) { ForEach(1...7, id: \.self) { value in Text("周" + ["一", "二", "三", "四", "五", "六", "日"][value - 1]).tag(value) } }
                    DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
                    if end <= start { Text("结束时间需晚于开始时间").font(.caption).foregroundStyle(.red) }
                }
                Section("教学周") {
                    Stepper("从第 \(firstWeek) 周", value: $firstWeek, in: 1...maximumWeek)
                    Stepper("到第 \(lastWeek) 周", value: $lastWeek, in: 1...maximumWeek)
                    if firstWeek > lastWeek { Text("结束周不能早于开始周").font(.caption).foregroundStyle(.red) }
                }
                if let saveError { Section { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("course-save-error") } }
            }.navigationTitle("添加课程").navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone, ScheduleMath.calendar.timeZone)
                .onAppear {
                    if !initializedWeeks {
                        lastWeek = maximumWeek; expectedSemesterID = store.personalSchedule?.activeSemesterId; initializedWeeks = true
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!valid) }
                }
        }
    }
    private func save() {
        guard valid else { return }
        guard expectedSemesterID == store.personalSchedule?.activeSemesterId else {
            saveError = "当前个人学期已变化，请关闭后重新添加，避免保存到错误学期。"; return
        }
        do {
            try store.saveCourse(Course(id: courseID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), teacher: teacher, room: room, day: day,
                                        start: CampusTheme.date(start, format: "HH:mm"), end: CampusTheme.date(end, format: "HH:mm"), weeks: Array(firstWeek...lastWeek)))
            dismiss()
        } catch { saveError = error.localizedDescription }
    }

}
