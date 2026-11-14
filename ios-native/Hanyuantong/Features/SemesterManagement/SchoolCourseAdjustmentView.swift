import SwiftUI

struct SchoolCourseAdjustmentView: View {
    @EnvironmentObject private var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    let context: SchoolCourseAdjustmentContext
    var onSaved: () -> Void = {}
    @State private var draft: SchoolCourseTimeChange
    @State private var week: Int
    @State private var range = "one"
    @State private var custom: Set<Int>
    @State private var confirmed = false
    @State private var error: String?
    @State private var discard = false
    private let initial: SchoolCourseTimeChange
    private let initialWeek: Int
    private let days = ["一", "二", "三", "四", "五", "六", "日"]

    init(context: SchoolCourseAdjustmentContext, onSaved: @escaping () -> Void = {}) {
        self.context = context; self.onSaved = onSaved
        let value = SchoolCourseTimeChange(course: context.current)
        initial = value; _draft = State(initialValue: value)
        let selected = context.source.weeks.contains(context.week) ? context.week : (context.source.weeks.first { $0 >= context.week } ?? context.source.weeks.first ?? 1)
        initialWeek = selected; _week = State(initialValue: selected); _custom = State(initialValue: [selected])
    }
    private var weeks: [Int] {
        switch range {
        case "future": return context.source.weeks.filter { $0 >= week }
        case "all": return context.source.weeks
        case "custom": return custom.sorted()
        default: return [week]
        }
    }
    private var dirty: Bool { draft != initial || range != "one" || week != initialWeek || custom != Set([initialWeek]) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(context.source.name).font(.headline)
                    Text("只调整你的课表，重新同步后保留。可随时恢复学校安排。退出或重新连接学校账号会清除本机调课记录。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                weekSection
                timeSection
                Section("学校原安排") {
                    Text("周\(days[context.source.day - 1]) \(context.source.start)–\(context.source.end) · \(context.source.room.isEmpty ? "地点未提供" : context.source.room)").font(.subheadline)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("school-adjustment-error")
                        if error.contains("重叠") { Toggle("已核对时间冲突，仍然保存", isOn: $confirmed) }
                    }
                }
            }.navigationTitle("调整时间/地点").navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone, ScheduleMath.calendar.timeZone)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(weeks.isEmpty) }
                }
                .interactiveDismissDisabled(dirty)
                .confirmationDialog("放弃尚未保存的调课？", isPresented: $discard, titleVisibility: .visible) {
                    Button("放弃修改", role: .destructive) { dismiss() }
                    Button("继续编辑", role: .cancel) { }
                }
                .onChange(of: draft) { _ in confirmed = false; error = nil }
                .onChange(of: weeks) { _ in confirmed = false; error = nil }
        }
    }
    private var weekSection: some View {
        Section("生效周次") {
            Picker("调整范围", selection: $range) {
                Text("仅某一周").tag("one"); Text("从某周起").tag("future")
                Text("全部上课周").tag("all"); Text("自选周次").tag("custom")
            }
            if range == "one" || range == "future" {
                Picker(range == "one" ? "生效周" : "起始周", selection: $week) {
                    ForEach(context.source.weeks, id: \.self) { Text("第 \($0) 周").tag($0) }
                }
            }
            if range == "custom" {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                    ForEach(context.source.weeks, id: \.self) { value in
                        Button {
                            if custom.contains(value) { custom.remove(value) } else { custom.insert(value) }
                        } label: {
                            Text(String(value)).frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(custom.contains(value) ? CampusTheme.onPrimary : CampusTheme.text)
                                .background(custom.contains(value) ? CampusTheme.primary : CampusTheme.background, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityLabel("第 \(value) 周")
                            .accessibilityAddTraits(custom.contains(value) ? .isSelected : [])
                    }
                }
            }
            Text("第 \(weeks.map(String.init).joined(separator: "、")) 周 · 共 \(weeks.count) 次").font(.caption).foregroundStyle(CampusTheme.muted)
        }
    }
    private var timeSection: some View {
        Section("新的上课安排") {
            Picker("星期", selection: $draft.day) { ForEach(1...7, id: \.self) { Text("星期\(days[$0 - 1])").tag($0) } }
            Toggle("按节次", isOn: $draft.usesPeriods).onChange(of: draft.usesPeriods) { enabled in
                if enabled { draft.startPeriod = draft.startPeriod ?? 1; draft.endPeriod = draft.endPeriod ?? draft.startPeriod; syncPeriods() }
            }
            if draft.usesPeriods {
                Picker("开始节次", selection: $draft.startPeriod) {
                    ForEach(context.periods, id: \.number) { Text("第 \($0.number) 节 · \($0.start)").tag(Optional($0.number)) }
                }.onChange(of: draft.startPeriod) { _ in
                    if (draft.endPeriod ?? 1) < (draft.startPeriod ?? 1) { draft.endPeriod = draft.startPeriod }; syncPeriods()
                }
                Picker("结束节次", selection: $draft.endPeriod) {
                    ForEach(context.periods.filter { $0.number >= (draft.startPeriod ?? 1) }, id: \.number) { Text("第 \($0.number) 节 · \($0.end)").tag(Optional($0.number)) }
                }.onChange(of: draft.endPeriod) { _ in syncPeriods() }
            } else {
                DatePicker("开始时间", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                DatePicker("结束时间", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
            }
            TextField("上课教室", text: $draft.room)
        }
    }
    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let pieces = (start ? draft.start : draft.end).split(separator: ":").compactMap { Int($0) }
            return ScheduleMath.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: pieces.first ?? 8, minute: pieces.last ?? 0))!
        }, set: { value in
            let time = CampusTheme.date(value, format: "HH:mm")
            if start { draft.start = time } else { draft.end = time }
        })
    }
    private func syncPeriods() {
        if let value = try? draft.validated(periods: context.periods) { draft = value }
    }
    private func save() {
        do {
            try store.saveSchoolAdjustment(context, weeks: weeks, change: draft, allowConflicts: confirmed)
            dismiss(); onSaved()
        } catch { self.error = error.localizedDescription }
    }
}
