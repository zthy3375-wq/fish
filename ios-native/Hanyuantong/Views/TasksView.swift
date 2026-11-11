import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var learning: LearningStore
    @State private var completionFilter = 0
    @State private var filter = TaskFilter()
    @State private var adding = false
    @State private var editing: CampusTask?
    @State private var deletion: CampusTask?
    @State private var actionError: String?

    private var effectiveFilter: TaskFilter {
        var value = filter
        if completionFilter == 1 { value.scope = .completed }
        if completionFilter == 2 { value.scope = .all }
        return value
    }
    private var groups: [TaskDateGroup] { TaskRules.groups(store.tasks, filter: effectiveFilter) }
    private var courses: [String] { Array(Set(store.tasks.map(\.course).filter { !$0.isEmpty })).sorted() }

    var body: some View {
        List {
            Section {
                NavigationLink { LearningCenterView(store: learning) } label: { Label("学习通作业、考试与通知", systemImage: "books.vertical") }
            }
            Section {
                Picker("待办筛选", selection: $completionFilter) {
                    Text("未完成").tag(0); Text("已完成").tag(1); Text("全部").tag(2)
                }.pickerStyle(.segmented)
                if completionFilter == 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([TaskListScope.pending, .today, .planned, .inbox, .due]) { scope in
                                Button { filter.scope = scope } label: {
                                    Text(scope == .pending ? "全部未完成" : scope.label)
                                        .font(.caption).padding(.horizontal, 12).padding(.vertical, 10)
                                        .foregroundStyle(filter.scope == scope ? CampusTheme.onPrimary : CampusTheme.text)
                                        .background(filter.scope == scope ? CampusTheme.primary : CampusTheme.surface, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(filter.scope == scope ? .isSelected : [])
                            }
                        }
                    }
                }
                DisclosureGroup("筛选与排序") {
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
                CampusEmpty(title: completionFilter == 1 ? "还没有已完成的待办" : "暂无待办", detail: "把要做的事记下来，一件一件完成。也可以调整筛选。", symbol: "checklist")
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.tasks) { task in taskRow(task) }
                }
            }
        }
        .searchable(text: $filter.search, prompt: "搜索标题、课程或备注")
        .scrollContentBackground(.hidden).background(CampusTheme.background)
        .navigationTitle("我的待办").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加待办")
            }
        }
        .sheet(isPresented: $adding) { TaskEditorView() }
        .sheet(item: $editing) { TaskEditorView(task: $0) }
        .confirmationDialog("删除这条待办？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("删除待办", role: .destructive) { if let task = deletion { store.deleteTask(task.id) }; deletion = nil }
        }
        .alert("待办操作未完成", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("好") { actionError = nil }
        } message: { Text(actionError ?? "") }
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
    private func change(_ task: CampusTask, update: (inout CampusTask) -> Void) {
        var task = task; update(&task)
        do { try store.saveTask(task) } catch { actionError = error.localizedDescription }
    }
}

private extension Int { var clampedPriority: Int { min(3, max(0, self)) } }

enum TaskPresentation {
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TaskClock.calendar.timeZone
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
