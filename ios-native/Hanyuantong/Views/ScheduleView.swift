import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: CampusStore
    @StateObject private var offline = OfflineScheduleCheck()
    @State private var firstWeekContext: Date?
    @State private var surprise: String?
    @State private var mode = 0
    @State private var comfortable = false
    @State private var showingCalibration = false
    @State private var calibrationWeek = 1
    @State private var calibrationMessage: String?
    @State private var adding = false
    @State private var cell: ScheduleCell?
    @State private var viewportHeight: CGFloat = 640
    @State private var managingPersonalSchedule = false
    private var subtitle: String {
        if store.isConnected { return "学校课表" }
        if let state = store.personalSchedule, let term = try? PersonalSemesterRules.activeSemester(in: state) {
            return term.title + " · 个人课表"
        }
        return "个人课表"
    }
    private var days: [Date] {
        let calendar = CampusTheme.calendar
        let weekday = (calendar.component(.weekday, from: store.selectedDate) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: store.selectedDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if store.pausedCourseAdjustments > 0 { Text("学校原安排已变化，\(store.pausedCourseAdjustments) 条按周调课记录已暂停，请按新课表重新核对。").font(.caption).foregroundStyle(CampusTheme.muted) }
                if store.isConnected && !store.semesters.isEmpty { schoolTermPicker }
                calibration
                scheduleToolbar
                HStack {
                    Text(store.isConnected ? "学校课表" : "个人课表").foregroundStyle(CampusTheme.muted)
                    Spacer()
                    Button { managingPersonalSchedule = true } label: {
                        Label("管理个人课程", systemImage: "chevron.right").labelStyle(TitleThenIconLabel())
                            .frame(minHeight: 44)
                    }.foregroundStyle(CampusTheme.primary).accessibilityIdentifier("manage-personal-schedule")
                }.font(.caption)
                weekNavigation
                if mode == 1 { HStack(spacing: 4) {
                    ForEach(days, id: \.self) { date in
                        Button { select(date,checkDay:true) } label: {
                            VStack(spacing: 9) { Text(CampusTheme.date(date, format: "EE")).font(.caption2); Text(CampusTheme.date(date, format: "d")).font(.subheadline.weight(.semibold)); Circle().fill(CampusTheme.calendar.isDate(date, inSameDayAs: Date()) ? CampusTheme.primary : .clear).frame(width: 4, height: 4) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(CampusTheme.calendar.isDate(date, inSameDayAs: store.selectedDate) ? CampusTheme.tint : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel(CampusTheme.date(date)).accessibilityAddTraits(CampusTheme.calendar.isDate(date, inSameDayAs: store.selectedDate) ? .isSelected : [])
                    }
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
            }.padding(.horizontal, 8).padding(.vertical, 10).frame(maxWidth: 680)
        }.background(GeometryReader { bounds in
            Color.clear.onAppear { viewportHeight = bounds.size.height }
                .onChange(of: bounds.size.height) { viewportHeight = $0 }
        }).background(CampusTheme.background).navigationTitle("我的课表").navigationBarTitleDisplayMode(.inline)
            .overlay(alignment:.top) { if let surprise { Text(surprise == "freeday" ? "今天属于你自己。" : "回到本周了。").padding(10).background(.thinMaterial,in:Capsule()).allowsHitTesting(false) } }
            .task(id:surprise) { guard let code=surprise else { return }; do { try await Task.sleep(nanoseconds:450_000_000) } catch { return }; MedalJournal.shared.unlock(code); surprise=nil }
            .onAppear {
                if store.lastSynced != nil && store.courses.contains(where: { $0.source != "personal" }) {
                    offline.start(scope: store.schoolMedalScope)
                }
                if store.selectedTab == .schedule { keepSelectionInTerm() }
            }
            .onChange(of: store.selectedTab) { tab in
                if tab == .schedule { keepSelectionInTerm() }
            }
            .onChange(of: store.displayedSchoolTerm) { _ in resetTermSelection() }
            .onChange(of: store.personalSchedule?.activeSemesterId) { _ in
                if !store.isConnected { resetTermSelection() }
            }
            .onDisappear { offline.stop(); firstWeekContext=nil }
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                ToolbarItem(placement: .navigationBarLeading) {
                    CampusRootTitle(title: "课程表", subtitle: subtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus").frame(width: 40, height: 40).background(CampusTheme.tint, in: Circle()) }
                        .accessibilityLabel("添加课程")
                }
            }.sheet(isPresented: $adding) { CourseEditorView() }
            .sheet(item: $cell) { CourseEditorView(preset: $0) }
            .sheet(isPresented: $managingPersonalSchedule) { PersonalScheduleSettingsSheet() }
    }
    private var schoolTermPicker: some View {
        HStack {
            Text("学期").foregroundStyle(CampusTheme.muted)
            Spacer()
            Menu {
                ForEach(store.semesters, id: \.self) { term in
                    Button(term.title) { store.selectSchoolTerm(term) }
                }
            } label: {
                Label(store.displayedSchoolTerm?.title ?? "当前学期", systemImage: "chevron.down")
                    .labelStyle(TitleThenIconLabel()).frame(minHeight: 44)
            }.accessibilityLabel("课表学期").disabled(store.isBusy)
        }.font(.subheadline).padding(.horizontal, 10)
            .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var calibration: some View {
        DisclosureGroup(isExpanded: $showingCalibration) {
            VStack(alignment: .leading, spacing: 8) {
                Text("按学校或老师确认的周次设置。只调整本学期的日期对应关系，保留课程的单双周和上课周次。")
                HStack {
                    Picker("本周教学周", selection: $calibrationWeek) {
                        ForEach(1...store.scheduleWeekCount, id: \.self) { Text("第 \($0) 周").tag($0) }
                    }.pickerStyle(.menu)
                    Spacer()
                    Button("保存校准", action: saveCalibration).buttonStyle(.borderedProminent)
                        .frame(minHeight: 44).disabled(store.isBusy)
                }.font(.subheadline)
                Text("第一教学周周一：\(CampusTheme.date(semesterStart, format: "yyyy-MM-dd")) · 本机设置")
                if let calibrationMessage { Text(calibrationMessage).accessibilityIdentifier("week-calibration-result") }
            }.font(.caption).foregroundStyle(CampusTheme.muted)
                .padding(12).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        } label: {
            Text("教学周不对？校准本周").font(.caption).foregroundStyle(CampusTheme.primary).frame(minHeight: 44)
        }.padding(.horizontal, 6)
            .onChange(of: showingCalibration) { opened in
                if opened { calibrationWeek = boundedWeek(for: Date()); calibrationMessage = nil }
            }
    }

    private var scheduleToolbar: some View {
        HStack {
            Button(comfortable ? "舒适阅读" : "整周总览") { comfortable.toggle() }
                .accessibilityAddTraits(comfortable ? .isSelected : [])
                .foregroundStyle(CampusTheme.primary).frame(minHeight: 44)
            Spacer(minLength: 6)
            Picker("课表视图", selection: $mode) { Text("日视图").tag(1); Text("周视图").tag(0) }
                .pickerStyle(.segmented).frame(maxWidth: 138)
            Spacer(minLength: 6)
            Button("回到本周", action: goToCurrentWeek).foregroundStyle(CampusTheme.primary).frame(minHeight: 44)
        }.font(.caption)
    }

    private var weekNavigation: some View {
        let week = boundedWeek(for: store.selectedDate)
        return HStack {
            Button { jump(to: week - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("上一周").disabled(week == 1)
            Spacer()
            VStack(spacing: 5) {
                Menu {
                    ForEach(1...store.scheduleWeekCount, id: \.self) { number in
                        Button("第 \(number) 周") { jump(to: number) }
                    }
                } label: {
                    Label("第 \(week) 周", systemImage: "chevron.down")
                        .labelStyle(TitleThenIconLabel()).font(.headline).padding(.horizontal, 8)
                        .frame(minHeight: 36)
                }.accessibilityLabel("跳转教学周").accessibilityValue("第 \(week) 周")
                Text(CampusTheme.date(days.first ?? store.selectedDate, format: "M/d") + " — " +
                     CampusTheme.date(days.last ?? store.selectedDate, format: "M/d") +
                     (week == boundedWeek(for: Date()) ? " · 当前周" : " · 非当前周"))
                    .font(.caption).foregroundStyle(CampusTheme.muted)
                if store.isConnected, store.courses.contains(where: { $0.source == "personal" }) {
                    Text("个人第\(ScheduleMath.week(on: store.selectedDate, start: store.semesterStart))周")
                        .font(.caption).foregroundStyle(CampusTheme.muted)
                }
            }
            Spacer()
            Button { jump(to: week + 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.accessibilityLabel("下一周").disabled(week == store.scheduleWeekCount)
        }
    }

    private var semesterStart: Date { store.isConnected ? store.schoolSemesterStart : store.semesterStart }
    private func boundedWeek(for date: Date) -> Int { min(store.scheduleWeekCount, max(1, store.week(for: date))) }
    private func jump(to week: Int, weekday: Int? = nil) {
        guard (1...store.scheduleWeekCount).contains(week) else { return }
        let day = weekday ?? ScheduleMath.weekday(on: store.selectedDate)
        let offset = (day - ScheduleMath.weekday(on: semesterStart) + 7) % 7
        if let date = ScheduleMath.calendar.date(byAdding: .day, value: (week - 1) * 7 + offset, to: semesterStart) {
            select(date, checkDay: false)
        }
    }
    private func goToCurrentWeek() {
        let now = Date()
        jump(to: boundedWeek(for: now), weekday: ScheduleMath.weekday(on: now))
    }
    private func keepSelectionInTerm() {
        let week = store.week(for: store.selectedDate)
        if week != boundedWeek(for: store.selectedDate) { jump(to: boundedWeek(for: store.selectedDate)) }
    }
    private func resetTermSelection() {
        goToCurrentWeek()
        calibrationWeek = boundedWeek(for: Date())
        calibrationMessage = nil
    }
    private func saveCalibration() {
        do {
            try store.calibrateTeachingWeek(calibrationWeek)
            goToCurrentWeek()
            calibrationMessage = "已校准，首页和课表同步生效"
        } catch { calibrationMessage = error.localizedDescription }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CampusTheme.date(store.selectedDate)).font(.headline)
            if store.courses(on: store.selectedDate).isEmpty { CampusEmpty(title: "这一天没有课程", detail: "可以添加自己的学习安排", symbol: "calendar") }
            ForEach(store.courses(on: store.selectedDate)) { course in NavigationLink { CourseDetailView(course: course, occurrenceDate: store.selectedDate) } label: { CourseRow(course: course) }.buttonStyle(.plain) }
        }
    }
    private var weekList: some View {
        TimetableGrid(days: days, courses: days.map { store.courses(on: $0) }, periods: store.visiblePeriods,
                      viewportHeight: viewportHeight, comfortable: comfortable, create: { date, slot in
            guard !store.isConnected else { return }
            cell = ScheduleCell(date: date, slot: slot)
        }, editable: !store.isConnected) { date in
            select(date, checkDay: false)
            mode = 1
        }
    }
    private func select(_ date: Date, checkDay: Bool) {
        let start = store.isConnected ? store.schoolSemesterStart : store.semesterStart
        let week=store.week(for:date), today=store.week(for:Date())
        let previous=store.week(for:store.selectedDate)
        store.selectedDate=date
        guard today > 0 && today <= store.scheduleWeekCount, !store.courses.isEmpty else { return }
        if week == 1 && today > 1 && previous != 1 { firstWeekContext=start }
        if week == today && previous != today && firstWeekContext == start { surprise="timewalk"; firstWeekContext=nil }
        else if checkDay && week > 0 && week <= store.scheduleWeekCount && store.courses(on:date).isEmpty { mode=1; surprise="freeday" }
    }
}

struct TitleThenIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon.font(.caption2) }
    }
}

struct ScheduleCell: Identifiable {
    let id = UUID()
    let date: Date
    let slot: AndroidTimeSlot
}

/// Mirrors buildTimeAxis/timePosition in the Android timetable. A class during a
/// break keeps its real duration, even when the user supplies a custom timetable.
struct SchedulePeriodAxis {
    struct Segment {
        let start: Int
        let end: Int
        let from: CGFloat
        let length: CGFloat
    }
    let segments: [Segment]
    var units: CGFloat { segments.last.map { $0.from + $0.length } ?? 1 }
    init(slots: [AndroidTimeSlot], events: [Range<Int>]) {
        let teaching: [Range<Int>] = slots.compactMap { slot in
            guard let a = TimetableDay.minutes(slot.start), let b = TimetableDay.minutes(slot.end), a < b else { return nil }
            return a..<b
        }.sorted { $0.lowerBound < $1.lowerBound }
        var output: [Segment] = []
        var position: CGFloat = 0
        func add(_ a: Int, _ b: Int, length: CGFloat) {
            guard a < b else { return }
            output.append(Segment(start: a, end: b, from: position, length: length))
            position += length
        }
        let earliest = min(teaching.first?.lowerBound ?? 1440, events.map(\.lowerBound).min() ?? 1440)
        let latest = max(teaching.last?.upperBound ?? 0, events.map(\.upperBound).max() ?? 0)
        var previous = earliest
        for (index, period) in teaching.enumerated() {
            let gap = CGFloat(period.lowerBound - previous) / 45
            let occupied = events.contains {
                ($0.lowerBound >= previous && $0.lowerBound < period.lowerBound) ||
                ($0.upperBound > previous && $0.upperBound <= period.lowerBound)
            }
            add(previous, period.lowerBound, length: index == 0 || occupied ? gap : min(0.35, gap))
            add(period.lowerBound, period.upperBound, length: 1)
            previous = period.upperBound
        }
        add(previous, latest, length: CGFloat(latest - previous) / 45)
        segments = output
    }
    func position(_ minute: Int) -> CGFloat {
        guard let segment = segments.first(where: { $0.start <= minute && minute <= $0.end }) else {
            return minute < (segments.first?.start ?? 1440) ? 0 : units
        }
        return segment.from + CGFloat(minute - segment.start) / CGFloat(segment.end - segment.start) * segment.length
    }
}

/// A shared minute axis keeps free periods and simultaneous classes visible.
/// Every overlapping event has its own lane; lanes never shrink below readable width.
private struct TimetableGrid: View {
    let days: [Date]
    let periods: [AndroidTimeSlot]
    let viewportHeight: CGFloat
    let comfortable: Bool
    let create: (Date, AndroidTimeSlot) -> Void
    let editable: Bool
    let openDay: (Date) -> Void
    private let layouts: [TimetableDay]
    private let axis: SchedulePeriodAxis
    init(days: [Date], courses: [[Course]], periods: [AndroidTimeSlot], viewportHeight: CGFloat, comfortable: Bool,
         create: @escaping (Date, AndroidTimeSlot) -> Void, editable: Bool, openDay: @escaping (Date) -> Void) {
        self.days = days; self.periods = periods
        self.viewportHeight = viewportHeight; self.comfortable = comfortable; self.create = create; self.editable = editable; self.openDay = openDay
        let daysLayout = courses.map(TimetableDay.init)
        self.layouts = daysLayout
        self.axis = SchedulePeriodAxis(slots: periods, events: daysLayout.flatMap(\.events).map { $0.start..<$0.end })
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var laneWidth: CGFloat = 112
    @ScaledMetric(relativeTo: .caption) private var minimumRow: CGFloat = 38
    private let timeWidth: CGFloat = 54
    private let headerHeight: CGFloat = 44
    private var rowHeight: CGFloat { max(minimumRow, min(60, (viewportHeight - 170) / max(1, axis.units))) }
    private var height: CGFloat { axis.units * rowHeight }
    private var ticks: [AndroidTimeSlot] { periods.sorted { $0.start < $1.start } }

    private func dayWidth(_ layout: TimetableDay) -> CGFloat { CGFloat(layout.laneCount) * laneWidth }
    private func y(_ minute: Int) -> CGFloat { axis.position(minute) * rowHeight }
    var body: some View {
        if comfortable || typeSize.isAccessibilitySize {
            ScrollView(.horizontal) { grid(compactDayWidth: nil) }
        } else {
            GeometryReader { bounds in
                grid(compactDayWidth: max(1, (bounds.size.width - 36) / CGFloat(max(1, days.count))))
            }.frame(height: headerHeight + height + 20)
        }
    }

    private func grid(compactDayWidth: CGFloat?) -> some View {
        let axisWidth = compactDayWidth == nil ? timeWidth : 36
        let week = layouts
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Text("节次").font(.caption).frame(width: axisWidth, height: headerHeight)
                ZStack(alignment: .topLeading) {
                    ForEach(ticks, id: \.number) { slot in
                        if let minute = TimetableDay.minutes(slot.start) {
                            VStack(spacing: 1) {
                                Text(String(slot.number)).font(.caption.weight(.semibold))
                                Text(slot.start); Text(slot.end)
                            }.font(.system(size: 9)).monospacedDigit().foregroundStyle(CampusTheme.muted)
                                .frame(width: axisWidth).offset(y: y(minute) + 2)
                        }
                    }
                }.frame(width: axisWidth, height: height + 20, alignment: .topLeading)
            }.accessibilityHidden(true)
            ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                dayColumn(date, layout: week[index], compactDayWidth: compactDayWidth)
            }
        }
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CampusTheme.border, lineWidth: 0.7))
    }

    private func dayColumn(_ date: Date, layout: TimetableDay, compactDayWidth: CGFloat?) -> some View {
        let width = compactDayWidth ?? dayWidth(layout)
        return VStack(spacing: 0) {
            Button { openDay(date) } label: {
                VStack(spacing: 2) {
                    Text(CampusTheme.date(date, format: "EE"))
                    Text(CampusTheme.date(date, format: "M/d")).font(.system(size: 9))
                }.frame(maxWidth: .infinity)
            }.buttonStyle(CampusPressStyle()).accessibilityLabel(CampusTheme.date(date))
                .font(.caption.weight(.semibold)).frame(width: width, height: headerHeight)
                .background(CampusTheme.calendar.isDateInToday(date) ? CampusTheme.tint : CampusTheme.background)
            ZStack(alignment: .topLeading) {
                if CampusTheme.calendar.isDateInToday(date) {
                    Rectangle().fill(CampusTheme.tint.opacity(0.30)).frame(width: width, height: height)
                }
                Rectangle().fill(CampusTheme.border).frame(width: 0.5, height: height)
                ForEach(ticks, id: \.number) { slot in
                    if let minute = TimetableDay.minutes(slot.start) {
                        if editable, let end = TimetableDay.minutes(slot.end) {
                            Button { create(date, slot) } label: {
                                Color.clear.frame(width: width, height: max(1, y(end) - y(minute))).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("添加" + CampusTheme.date(date, format: "EEEE") + "第\(slot.number)节课程")
                                .offset(y: y(minute))
                        }
                        Rectangle().fill(CampusTheme.border.opacity(0.7)).frame(width: width, height: 0.5).offset(y: y(minute))
                    }
                }
                if compactDayWidth != nil {
                    ForEach(layout.clusters, id: \.firstID) { cluster in
                        Group {
                            if cluster.count == 1 {
                                NavigationLink { CourseDetailView(course: cluster.first.course, occurrenceDate: date) } label: {
                                    compactLabel(cluster.first.course.name, cluster: cluster, width: width)
                                }.accessibilityLabel("\(cluster.first.course.name)，\(cluster.first.course.start)至\(cluster.first.course.end)")
                            } else {
                                Button { openDay(date) } label: {
                                    compactLabel("\(cluster.count) 门重叠", cluster: cluster, width: width)
                                }.accessibilityLabel("查看当天 \(cluster.count) 门时间重叠的课程")
                            }
                        }.buttonStyle(.plain).offset(x: 1, y: y(cluster.first.start))
                    }
                } else {
                    ForEach(layout.events) { event in
                        NavigationLink { CourseDetailView(course: event.course, occurrenceDate: date) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.course.name).font(.caption.weight(.semibold)).lineLimit(3)
                                Text(event.course.room).font(.caption2).lineLimit(2)
                                Text("\(event.course.start)–\(event.course.end)").font(.caption2.monospacedDigit()).lineLimit(1)
                                if !event.course.period.isEmpty { Text(event.course.period).font(.caption2).lineLimit(1) }
                            }.padding(6).frame(width: laneWidth - 6, height: max(1, y(event.end) - y(event.start) - 3), alignment: .topLeading)
                                .foregroundStyle(CampusTheme.course(event.course.color))
                                .background(CampusTheme.course(event.course.color).opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                                .clipped().contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(CampusTheme.date(date))，\(event.course.name)，\(event.course.start)至\(event.course.end)，\(event.course.room)，\(event.course.period)")
                            .offset(x: CGFloat(event.lane) * laneWidth + 3, y: y(event.start))
                    }
                }
                if CampusTheme.calendar.isDateInToday(date) {
                    TimelineView(.periodic(from: .now, by: 60)) { clock in
                        let time = CampusTheme.calendar.dateComponents([.hour, .minute], from: clock.date)
                        let position = y((time.hour ?? 0) * 60 + (time.minute ?? 0))
                        if position > 0 && position < height {
                            Rectangle().fill(CampusTheme.primary).frame(width: width, height: 1.5)
                                .overlay(alignment: .leading) { Circle().fill(CampusTheme.primary).frame(width: 5, height: 5) }
                                .offset(y: position)
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }.frame(width: width, height: height + 20, alignment: .topLeading)
        }
    }
    private func compactLabel(_ text: String, cluster: TimetableCluster, width: CGFloat) -> some View {
        let color = CampusTheme.course(cluster.first.course.color)
        return Text(text).font(.caption2.weight(.medium)).lineLimit(4)
            .padding(2).frame(width: max(1, width - 2), height: max(1, y(cluster.end) - y(cluster.first.start) - 2), alignment: .topLeading)
            .foregroundStyle(color).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .clipped().contentShape(Rectangle())
    }

}

struct TimetableEvent: Identifiable {
    let course: Course
    let start: Int
    let end: Int
    let lane: Int
    var id: UUID { course.id }
}

struct TimetableCluster {
    let first: TimetableEvent
    var count: Int
    var end: Int
    var firstID: UUID { first.id }
}

struct TimetableDay {
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
    var clusters: [TimetableCluster] {
        var result: [TimetableCluster] = []
        for event in events {
            if let last = result.indices.last, event.start < result[last].end {
                result[last].count += 1
                result[last].end = max(result[last].end, event.end)
            } else {
                result.append(TimetableCluster(first: event, count: 1, end: event.end))
            }
        }
        return result
    }

    static func minutes(_ value: String) -> Int? {
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
                CampusLabeledValue("教师", value: course.teacher.isEmpty ? "未提供" : course.teacher)
                CampusLabeledValue("地点", value: course.room.isEmpty ? "未提供" : course.room)
                CampusLabeledValue("上课时间", value: "\(course.start)–\(course.end)")
                CampusLabeledValue("星期", value: ["一", "二", "三", "四", "五", "六", "日"][min(7, max(1, course.day)) - 1])
                if !course.period.isEmpty { CampusLabeledValue("节次", value: course.period) }
                CampusLabeledValue("教学周", value: course.weeks.map(String.init).joined(separator: "、"))
                CampusLabeledValue("来源", value: course.source == "personal" ? "个人课程" : (course.locallyAdjusted == true ? "学校课程 · 已在本机调课" : "教务系统"))
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
    var preset: ScheduleCell? = nil
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
        CampusNavigation {
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
                        if let preset {
                            day = ScheduleMath.weekday(on: preset.date)
                            let week = ScheduleMath.week(on: preset.date, start: store.semesterStart)
                            firstWeek = min(max(1, week), maximumWeek)
                            lastWeek = firstWeek
                            if let a = TimetableDay.minutes(preset.slot.start), let b = TimetableDay.minutes(preset.slot.end) {
                                let midnight = CampusTheme.calendar.startOfDay(for: preset.date)
                                start = midnight.addingTimeInterval(Double(a) * 60)
                                end = midnight.addingTimeInterval(Double(b) * 60)
                            }
                        } else { lastWeek = maximumWeek }
                        expectedSemesterID = store.personalSchedule?.activeSemesterId; initializedWeeks = true
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
