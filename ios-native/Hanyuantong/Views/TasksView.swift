import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var learning: LearningStore
    @State private var filter = TaskFilter(scope: .today)
    @State private var agenda = false
    @State private var agendaDay = Date()
    @State private var showFilters = false
    @State private var source: TaskSource = .all
    @State private var learningDetail: LearningItem?
    @State private var quickTitle = ""
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var adding = false
    @State private var editing: CampusTask?
    @State private var deletion: CampusTask?
    @State private var actionError: String?

    private enum TaskSource: String, CaseIterable, Identifiable {
        case all = "全部来源"
        case personal = "个人待办"
        case learning = "学习通"
        var id: Self { self }
    }

    private var courses: [String] {
        let personal = source == .learning ? [] : store.tasks.map(\.course)
        let official = source == .personal || !learning.connected ? [] : learning.cache.items.map(\.course)
        return Set(personal + official).filter { !$0.isEmpty }.sorted()
    }

    private func taskSelection(scope: TaskListScope) -> (tasks: [CampusTask], official: [UUID: LearningItem]) {
        let personal = source == .learning ? [] : store.tasks
        guard source != .personal else { return (personal, [:]) }
        let personalIDs = Set(personal.map(\.id))
        let entries = learning.cache.taskListEntries(scope: scope).filter { !personalIDs.contains($0.projection.id) }
        return (personal + entries.map { $0.projection }, Dictionary(entries.map { ($0.projection.id, $0.item) }, uniquingKeysWith: { first, _ in first }))
    }

    private var canDiscoverEmptyList: Bool {
        store.personalDataAvailable && learning.canConfirmTaskList && actionError == nil &&
        source == .all && filter.search.isEmpty && filter.course.isEmpty && filter.priority == -1 &&
        filter.scope != .completed && !taskSelection(scope: .all).tasks.contains { !$0.completed }
    }

    private var newTaskDay: String? {
        if agenda { return TaskClock.day(agendaDay) }
        return filter.scope == .today ? TaskClock.day(Date()) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                NavigationLink { LearningCenterView(store: learning) } label: {
                    HStack { Image(systemName: "book"); Text("学习通作业").fontWeight(.semibold)
                        Text("按课程查看与安排").font(.caption).foregroundStyle(CampusTheme.muted)
                        Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                        .padding(.horizontal, 14).frame(minHeight: 48).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(CampusPressStyle())
                if let message = learning.message, learning.connected {
                    Text(message).font(.caption).foregroundStyle(CampusTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Picker("待办与日程", selection: $agenda) { Text("任务清单").tag(false); Text("日程").tag(true) }.pickerStyle(.segmented)
                    Button { adding = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("添加待办").disabled(!store.personalDataAvailable)
                }
                if !agenda {
                    HStack(spacing: 3) {
                        ForEach([TaskListScope.today, .due, .planned, .inbox]) { scope in
                            let count = TaskRules.select(taskSelection(scope: scope).tasks, filter: TaskFilter(scope: scope)).count
                            Button { filter.scope = scope } label: {
                                HStack(spacing: 3) { Text(scope.label); Text(String(count)).font(.caption2.monospacedDigit()) }
                                    .font(.caption).frame(maxWidth: .infinity, minHeight: 42)
                                    .background(filter.scope == scope ? CampusTheme.tint : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.accessibilityLabel(scope.label).accessibilityValue(String(count))
                             .accessibilityAddTraits(filter.scope == scope ? .isSelected : [])
                        }
                    }.buttonStyle(CampusPressStyle())
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("搜索任务、课程或备注", text: $filter.search).accessibilityLabel("搜索任务")
                        Button("筛选") { withAnimation(reduce ? nil : .easeOut(duration: 0.12)) { showFilters.toggle() } }
                    }.font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(CampusTheme.tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
            if agenda { CampusAgendaView(embedded: true, sharedDay: $agendaDay) }
            else { taskList }
        }
        .background(CampusTheme.background)
        .background(LearningPresenterAnchor { learning.attachPresenter($0) }.frame(width: 0, height: 0))
        .navigationTitle("我的待办").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .navigationBarLeading) { CampusRootTitle(title: "待办", subtitle: "今天、接下来，按自己的节奏") }
        }
        .sheet(isPresented: $adding) { TaskEditorView(defaultPlannedDay: newTaskDay) }
        .sheet(item: $editing) { TaskEditorView(task: $0) }
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
        .confirmationDialog("删除这条待办？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("删除待办", role: .destructive) { if let task = deletion { store.deleteTask(task.id) }; deletion = nil }
        }
        .alert("待办操作未完成", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("好") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private var taskList: some View {
        let selection = taskSelection(scope: filter.scope)
        let groups = TaskRules.groups(selection.tasks, filter: filter, unknownCompletionDates: Set(selection.official.keys))
        return List {
            if showFilters {
                Section {
                    Picker("任务范围", selection: $filter.scope) {
                        ForEach(TaskListScope.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu).accessibilityIdentifier("task-scope-picker")
                    Picker("任务来源", selection: $source) {
                        ForEach(TaskSource.allCases) { Text($0.rawValue).tag($0) }
                    }.onChange(of: source) { _ in
                        if !courses.contains(filter.course) { filter.course = "" }
                    }
                    Picker("关联课程筛选", selection: $filter.course) {
                        Text("所有课程").tag("")
                        ForEach(courses, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("优先级筛选", selection: $filter.priority) {
                        Text("全部优先级").tag(-1)
                        ForEach(0..<TaskRules.priorities.count, id: \.self) { Text(TaskRules.priorities[$0]).tag($0) }
                    }
                    Picker("任务排序", selection: $filter.sort) {
                        ForEach(TaskSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("按课程分组", isOn: $filter.groupByCourse)
                }
            }
            if groups.isEmpty {
                VStack(spacing: 8) {
                    if canDiscoverEmptyList {
                        DiscoverySurface("emptyfish", label: "清单里的小金鱼") { CampusHeroFish().frame(width: 36, height: 25) }
                    } else { Image(systemName: "checkmark").foregroundStyle(CampusTheme.muted) }
                    Text(filter.search.isEmpty ? "这里暂时没有任务" : "没有匹配任务").font(.subheadline.weight(.semibold))
                    Text("在下方输入标题即可添加，也可以把学习通作业安排到今天。")
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(CampusTheme.muted)
                }.frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.vertical, 62).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.tasks) { task in
                        if let item = selection.official[task.id] { learningRow(item, projection: task) }
                        else { taskRow(task) }
                    }
                }
            }
            quickEntry.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }.listStyle(.plain).campusScrollBackground().background(CampusTheme.background)
    }

    private var quickEntry: some View {
        HStack {
            Image(systemName: "plus").foregroundStyle(CampusTheme.primary)
            TextField("添加任务，回车保存", text: $quickTitle).submitLabel(.done).onSubmit { saveQuick() }
                .accessibilityIdentifier("quick-task-title")
            Button(action: saveQuick) {
                Image(systemName: "arrow.up").frame(width: 38, height: 38)
                    .foregroundStyle(CampusTheme.onPrimary).background(CampusTheme.primary, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel("快速保存任务").disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(8).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(CampusTheme.border, lineWidth: 1))
            .padding(.horizontal, 16).padding(.vertical, 8).disabled(!store.personalDataAvailable)
    }
    private func saveQuick() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, store.personalDataAvailable else { return }
        var task = TaskRules.makeTask(title: title)
        task.plannedDay = filter.scope == .today ? CampusTheme.date(Date(), format: "yyyy-MM-dd") : nil
        task.course = filter.course
        do {
            try store.saveTask(task)
            quickTitle = ""
            if filter.scope != .today { filter.scope = .inbox }
            if source == .learning { source = .all }
        } catch { actionError = error.localizedDescription }
    }

    private func learningRow(_ item: LearningItem, projection: CampusTask) -> some View {
        Button {
            learningDetail = item
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.body).foregroundStyle(CampusTheme.text)
                    if !item.course.isEmpty { Text(item.course).font(.caption).foregroundStyle(CampusTheme.muted) }
                    Text(LearningDisplay.state(item).label).font(.caption.weight(.semibold)).foregroundStyle(CampusTheme.primary)
                    if let day = projection.plannedDay { Text("计划 " + day).font(.caption).foregroundStyle(CampusTheme.muted) }
                    if projection.deadline != nil { Text(LearningDisplay.deadline(item)).font(.caption).foregroundStyle(CampusTheme.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
            } icon: {
                Image(systemName: "book").frame(width: 44, height: 44).foregroundStyle(CampusTheme.primary)
            }
        }.buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if projection.plannedDay != nil {
                    Button("取消安排", role: .destructive) { learning.setPlannedDay(nil, for: item) }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("今天做") { learning.today(item) }.tint(CampusTheme.primary)
                if let tomorrow = TaskClock.shifted(TaskClock.day(Date()), days: 1) {
                    Button("明天做") { learning.setPlannedDay(tomorrow, for: item) }.tint(.orange)
                }
            }
    }

    private func taskRow(_ task: CampusTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { store.toggleTask(task.id) } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel(task.completed ? "标记未完成：\(task.title)" : "完成：\(task.title)")
            Button { editing = task } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(task.title).font(.body).strikethrough(task.completed)
                            .foregroundStyle(task.completed ? CampusTheme.muted : CampusTheme.text)
                        if task.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(CampusTheme.primary).accessibilityLabel("已置顶") }
                    }
                    if !task.course.isEmpty { Text(task.course).font(.caption).foregroundStyle(CampusTheme.muted) }
                    if let at = task.plannedAt { Text("计划 " + TaskPresentation.date(at)).font(.caption).foregroundStyle(CampusTheme.muted) }
                    else if let day = task.plannedDay { Text("计划 " + day + " · 当天安排").font(.caption).foregroundStyle(CampusTheme.muted) }
                    if let deadline = task.deadline {
                        Text("截止 " + TaskPresentation.date(deadline)).font(.caption)
                            .foregroundStyle(TaskRules.isOverdue(task) ? Color(hex: 0xa34c54) : CampusTheme.muted)
                    }
                    HStack(spacing: 10) {
                        if task.priority > 0 { Text(TaskRules.priorities[task.priority.clampedPriority] + "优先级") }
                        if !task.steps.isEmpty { Text("步骤 \(task.steps.filter(\.completed).count)/\(task.steps.count)") }
                        if let repeatRule = task.repeatRule { Label(repeatRule.kind.label, systemImage: "repeat") }
                        if task.prepared { Text("准备就绪") }
                    }.font(.caption2).foregroundStyle(CampusTheme.muted)
                    if !task.notes.isEmpty { Text(task.notes).font(.caption).lineLimit(2).foregroundStyle(CampusTheme.muted) }
                    if let at = task.snoozedUntil { Text("稍后提醒 " + TaskPresentation.date(at)).font(.caption2).foregroundStyle(CampusTheme.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
                // Keep the native button's action/traits, with explicit persisted identity and metadata.
                // An extra accessibilityElement wrapper hides those traits on some iOS versions.
                .accessibilityIdentifier("task-edit-" + task.id.uuidString)
                .accessibilityLabel("编辑待办：\(task.title)")
                .accessibilityValue(taskAccessibilitySummary(task))
                .accessibilityHint("打开并编辑个人待办")
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) { deletion = task }
            Button("编辑") { editing = task }.tint(CampusTheme.primary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(task.pinned ? "取消置顶" : "置顶") { change(task) { $0.pinned.toggle() } }.tint(CampusTheme.primary)
            if !task.completed {
                Button("稍后10分钟") {
                    do { try store.saveTask(TaskRules.snoozed(task, until: TaskRules.futurePickerMinute(minutes: 10))) }
                    catch { actionError = error.localizedDescription }
                }.tint(.orange)
            }
        }
    }
    private func taskAccessibilitySummary(_ task: CampusTask) -> String {
        var parts = [task.completed ? "已完成" : "未完成"]
        if !task.course.isEmpty { parts.append(task.course) }
        if let at = task.plannedAt { parts.append("计划 " + TaskPresentation.date(at)) }
        else if let day = task.plannedDay { parts.append("计划 " + day + "，当天安排") }
        else { parts.append("未安排") }
        if let at = task.deadline { parts.append("截止 " + TaskPresentation.date(at)) }
        if task.pinned { parts.append("已置顶") }
        if task.priority > 0 { parts.append(TaskRules.priorities[task.priority.clampedPriority] + "优先级") }
        if !task.steps.isEmpty { parts.append("步骤 \(task.steps.filter(\.completed).count)/\(task.steps.count)") }
        if let rule = task.repeatRule { parts.append(rule.kind.label + "重复") }
        if task.prepared { parts.append("准备就绪") }
        if !task.notes.isEmpty { parts.append(task.notes) }
        if let at = task.snoozedUntil { parts.append("稍后提醒 " + TaskPresentation.date(at)) }
        return parts.joined(separator: "，")
    }
    private func change(_ task: CampusTask, update: (inout CampusTask) -> Void) {
        var task = task; update(&task)
        do { try store.saveTask(task) } catch { actionError = error.localizedDescription }
    }
}

private extension Int { var clampedPriority: Int { Swift.min(3, Swift.max(0, self)) } }

enum TaskPresentation {
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TaskClock.calendar.timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
