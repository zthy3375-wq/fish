import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: CampusStore
    @State private var mode = 0
    @State private var adding = false
    private var days: [Date] {
        let calendar = CampusTheme.calendar
        let weekday = (calendar.component(.weekday, from: store.selectedDate) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: store.selectedDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("课表视图", selection: $mode) { Text("周课表").tag(0); Text("日程").tag(1) }.pickerStyle(.segmented)
                HStack {
                    Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一周")
                    Spacer()
                    VStack(spacing: 5) { Text("第\(store.week(for: store.selectedDate))周").font(.headline); Text(CampusTheme.date(store.selectedDate, format: "yyyy年M月")).font(.caption).foregroundStyle(CampusTheme.muted) }
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
                ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加课程") }
            }.sheet(isPresented: $adding) { CourseEditorView() }
    }
    private var dayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CampusTheme.date(store.selectedDate)).font(.headline)
            if store.courses(on: store.selectedDate).isEmpty { CampusEmpty(title: "这一天没有课程", detail: "可以添加自己的学习安排", symbol: "calendar") }
            ForEach(store.courses(on: store.selectedDate)) { course in NavigationLink { CourseDetailView(course: course) } label: { CourseRow(course: course) }.buttonStyle(.plain) }
        }
    }
    private var weekList: some View {
        // Horizontal scrolling preserves readable names on smaller iPhones and at larger text sizes.
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(days, id: \.self) { date in
                    VStack(spacing: 8) {
                        Text(CampusTheme.date(date, format: "EE M/d")).font(.caption.weight(.semibold)).padding(.vertical, 10)
                        let courses = store.courses(on: date)
                        if courses.isEmpty { Text("无课").font(.caption).foregroundStyle(CampusTheme.muted).padding(.vertical, 30) }
                        ForEach(courses) { course in
                            NavigationLink { CourseDetailView(course: course) } label: {
                                VStack(alignment: .leading, spacing: 9) { Text(course.name).font(.subheadline.weight(.medium)); Text(course.room).font(.caption); Text("\(course.start)–\(course.end)").font(.caption2) }.frame(maxWidth: .infinity, alignment: .leading).padding(10).foregroundStyle(CampusTheme.course(course.color)).background(CampusTheme.course(course.color).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }.frame(width: 125).frame(maxHeight: .infinity, alignment: .top)
                }
            }.padding(10)
        }.background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(CampusTheme.border, lineWidth: 0.7))
    }
    private func shift(_ amount: Int) { if let date = CampusTheme.calendar.date(byAdding: .day, value: amount, to: store.selectedDate) { store.selectedDate = date } }
}

struct CourseDetailView: View {
    @EnvironmentObject var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    let course: Course
    @State private var confirming = false
    var body: some View {
        List {
            Section { Text(course.name).font(.title2.weight(.semibold)).padding(.vertical, 8) }
            Section("课程信息") {
                LabeledContent("教师", value: course.teacher.isEmpty ? "未提供" : course.teacher)
                LabeledContent("地点", value: course.room.isEmpty ? "未提供" : course.room)
                LabeledContent("上课时间", value: "\(course.start)–\(course.end)")
                LabeledContent("星期", value: ["一", "二", "三", "四", "五", "六", "日"][min(7, max(1, course.day)) - 1])
                if !course.period.isEmpty { LabeledContent("节次", value: course.period) }
                LabeledContent("教学周", value: course.weeks.map(String.init).joined(separator: "、"))
                LabeledContent("来源", value: course.source == "personal" ? "个人课程" : "教务系统")
                if !course.notes.isEmpty { Text(course.notes) }
            }
            if course.source == "personal" { Section { Button("删除个人课程", role: .destructive) { confirming = true } } }
        }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("删除这门个人课程？", isPresented: $confirming, titleVisibility: .visible) { Button("删除课程", role: .destructive) { store.deleteCourse(course.id); dismiss() } }
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
    @State private var lastWeek = 20
    @State private var start = CampusTheme.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8))!
    @State private var end = CampusTheme.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 40))!
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end > start && firstWeek <= lastWeek }
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
                    Stepper("从第 \(firstWeek) 周", value: $firstWeek, in: 1...40)
                    Stepper("到第 \(lastWeek) 周", value: $lastWeek, in: 1...40)
                    if firstWeek > lastWeek { Text("结束周不能早于开始周").font(.caption).foregroundStyle(.red) }
                }
            }.navigationTitle("添加课程").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { guard valid else { return }; store.addCourse(Course(name: name.trimmingCharacters(in: .whitespacesAndNewlines), teacher: teacher, room: room, day: day, start: CampusTheme.date(start, format: "HH:mm"), end: CampusTheme.date(end, format: "HH:mm"), weeks: Array(firstWeek...lastWeek))); dismiss() }.disabled(!valid) }
                }
        }
    }
}
