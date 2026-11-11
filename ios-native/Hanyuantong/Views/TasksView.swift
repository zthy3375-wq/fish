import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: CampusStore
    @State private var filter = 0
    @State private var adding = false
    @State private var deletion: CampusTask?
    private var visible: [CampusTask] {
        store.tasks.filter { filter == 2 || $0.completed == (filter == 1) }.sorted { $0.date < $1.date }
    }
    var body: some View {
        List {
            Section { Picker("待办筛选", selection: $filter) { Text("未完成").tag(0); Text("已完成").tag(1); Text("全部").tag(2) }.pickerStyle(.segmented) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if visible.isEmpty {
                CampusEmpty(title: filter == 1 ? "还没有已完成的待办" : "暂无待办", detail: "把要做的事记下来，一件一件完成。", symbol: "checklist").listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            ForEach(visible) { task in
                HStack(alignment: .top, spacing: 13) {
                    Button { store.toggleTask(task.id) } label: { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel(task.completed ? "标记未完成：\(task.title)" : "完成：\(task.title)")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title).font(.body).strikethrough(task.completed).foregroundStyle(task.completed ? CampusTheme.muted : CampusTheme.text)
                        Text(CampusTheme.date(task.date, format: "M月d日 HH:mm")).font(.caption).foregroundStyle(!task.completed && task.date < Date() ? Color(hex: 0xa34c54) : CampusTheme.muted)
                        if !task.notes.isEmpty { Text(task.notes).font(.caption).foregroundStyle(CampusTheme.muted) }
                    }.padding(.vertical, 8)
                }.swipeActions { Button("删除", role: .destructive) { deletion = task } }
            }
        }.scrollContentBackground(.hidden).background(CampusTheme.background)
            .navigationTitle("我的待办").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加待办") } }
            .sheet(isPresented: $adding) { TaskEditorView() }
            .confirmationDialog("删除这条待办？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("删除待办", role: .destructive) { if let task = deletion { store.deleteTask(task.id) }; deletion = nil }
            }
    }
}

struct TaskEditorView: View {
    @EnvironmentObject var store: CampusStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section("要做什么") {
                    TextField("待办内容", text: $title, axis: .vertical).lineLimit(2...5)
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 { Text("请将待办内容控制在200字以内").font(.caption).foregroundStyle(.red) }
                }
                Section("计划时间") { DatePicker("日期与时间", selection: $date) }
                Section { Text("待办保存在本机。本版本尚未接入系统通知提醒。").font(.caption).foregroundStyle(CampusTheme.muted) }
            }.navigationTitle("添加待办").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { let value = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty, value.count <= 200 else { return }; store.addTask(title: value, date: date); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).count > 200) }
                }
        }
    }
}
