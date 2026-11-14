import SwiftUI

extension CampusDisplayTheme {
    var colorScheme: ColorScheme? {
        switch self { case .light: return .light; case .dark: return .dark; case .system: return nil }
    }
}

@MainActor struct DisplayPreferencesSettingsView: View {
    @ObservedObject var store: DisplayPreferencesStore
    @State private var editingProfile = false
    @State private var confirmingReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("本机资料") {
                LabeledContent("昵称", value: store.preferences.name)
                LabeledContent("专业 / 年级", value: store.preferences.major.isEmpty ? "未填写" : store.preferences.major)
                Button("编辑个人资料") { editingProfile = true }
                    .disabled(!store.canEdit).accessibilityIdentifier("edit-local-profile")
                Text("无需填写真实学号和身份信息。昵称与专业 / 年级仅加密保存在本机，不修改学校资料，也不加入匿名统计或发送到学校。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Section("偏好与数据") {
                Picker("主题", selection: Binding(get: { store.preferences.theme }, set: { value in
                    perform { try store.updateTheme(value) }
                })) {
                    ForEach(CampusDisplayTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.symbol).tag(theme)
                    }
                }.pickerStyle(.segmented).disabled(!store.canEdit).accessibilityIdentifier("display-theme")
                Toggle(isOn: Binding(get: { store.preferences.compact }, set: { value in
                    perform { try store.updateCompact(value) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("紧凑布局")
                        Text("更少留白，更高信息密度").font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                }.disabled(!store.canEdit).accessibilityIdentifier("display-compact")
                Text("主题与布局立即应用，保存失败时保留原设置。紧凑布局不会缩小系统文字；辅助功能大字号仍保留阅读空间。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
            }
            if !store.canEdit {
                Section("设置暂不可用") {
                    Text(store.error ?? DisplayPreferencesFailure.unavailable.localizedDescription)
                        .foregroundStyle(CampusTheme.muted).accessibilityIdentifier("display-storage-unavailable")
                    Button("重新读取本机设置") { message = nil; store.reload() }
                        .accessibilityIdentifier("display-retry-load")
                }
            } else if let issue = message ?? store.error {
                Section { Text(issue).foregroundStyle(CampusTheme.muted).accessibilityIdentifier("display-message") }
            }
            Section {
                Button("恢复默认本机设置", role: .destructive) { confirmingReset = true }
                    .disabled(!store.canEdit).accessibilityIdentifier("display-reset")
            } footer: {
                Text("只恢复昵称、专业 / 年级、主题和紧凑布局，不影响学校连接、个人课程、待办、系统提醒、小组件或匿名统计选择。")
            }
        }
        .scrollContentBackground(.hidden).background(CampusTheme.background)
        .navigationTitle("显示与本机资料").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingProfile) { LocalProfileEditorView(store: store) }
        .confirmationDialog("恢复默认本机设置？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("确认重置", role: .destructive) {
                perform { try store.reset(confirmed: true) }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("昵称恢复为“同学”，清空本机专业 / 年级，使用浅色主题和普通布局。课程、待办及账号连接不受影响。")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); message = "本机设置已保存" }
        catch { message = error.localizedDescription }
    }
}

/// Keeps the existing profile strip and official-profile precedence; edits remain strictly local.
@MainActor struct LocalProfileSummaryView: View {
    @ObservedObject var store: DisplayPreferencesStore
    var academicName: String? = nil
    var academicMajor: String? = nil
    var academicClass: String? = nil
    @Environment(\.campusCompactLayout) private var compact
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing = false

    private func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    private var name: String { nonempty(academicName) ?? store.preferences.name }
    private var major: String { nonempty(academicMajor) ?? store.preferences.major }

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 13) {
                Text(String(store.preferences.name.prefix(1))).font(.title2.weight(.medium))
                    .frame(width: 49, height: 49).foregroundStyle(CampusTheme.primary)
                    .background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 17)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.title3.weight(.semibold)).foregroundStyle(CampusTheme.text)
                    if !major.isEmpty { Text(major).font(.subheadline).foregroundStyle(CampusTheme.muted) }
                    Text(nonempty(academicClass) ?? "本地资料").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                Spacer(minLength: 4)
                Label("编辑", systemImage: "chevron.right").font(.caption).foregroundStyle(CampusTheme.primary)
            }.padding(.vertical, compact && !typeSize.isAccessibilitySize ? 8 : 12).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!store.canEdit).accessibilityIdentifier("local-profile-summary")
        .sheet(isPresented: $editing) { LocalProfileEditorView(store: store) }
    }
}

@MainActor struct LocalProfileEditorView: View {
    @ObservedObject var store: DisplayPreferencesStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var major: String
    @State private var error: String?

    init(store: DisplayPreferencesStore) {
        self.store = store
        _name = State(initialValue: store.preferences.name)
        _major = State(initialValue: store.preferences.major)
    }

    private var valid: Bool { (try? store.preferences.editingProfile(name: name, major: major)) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("昵称", text: $name).textContentType(.nickname)
                        .accessibilityIdentifier("local-profile-name")
                    TextField("专业 / 年级", text: $major)
                        .accessibilityIdentifier("local-profile-major")
                } header: { Text("本机资料") } footer: {
                    Text("无需填写真实学号和身份信息。昵称最多20字，专业 / 年级最多50字；表情可能占多个字。留空昵称将使用“同学”。")
                }
                Section {
                    Text("只修改本机显示资料，不会修改教务资料。若已读取学校资料，个人页仍优先展示学校返回的信息。")
                        .font(.caption).foregroundStyle(CampusTheme.muted)
                }
                if !valid { Section { Text(DisplayPreferencesFailure.invalidProfile.localizedDescription).foregroundStyle(.red) } }
                if let issue = error ?? (!store.canEdit ? store.error : nil) {
                    Section { Text(issue).foregroundStyle(.red).accessibilityIdentifier("local-profile-error") }
                }
            }
            .scrollContentBackground(.hidden).background(CampusTheme.background)
            .navigationTitle("编辑个人资料").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("local-profile-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存资料") {
                        do { try store.updateProfile(name: name, major: major); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!valid || !store.canEdit).accessibilityIdentifier("local-profile-save")
                }
            }
        }.tint(CampusTheme.primary)
    }
}
