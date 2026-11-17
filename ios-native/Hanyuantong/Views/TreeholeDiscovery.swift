import SwiftUI

struct TreeholeDiscoveryBar: View {
    @ObservedObject var tree: TreeholeStore
    let select: (String, String) -> Void
    private var sections: [(String, String)] { [("all", "全部")] + (tree.discoveryEnabled ? TreeholeCategories.sections : TreeholeCategories.all) }
    private var selected: String { tree.discoveryEnabled ? TreeholeCategories.section(tree.category) : tree.category }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CampusAdaptiveRow { HStack(spacing: 0) { sectionButtons } } fallback: { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 18) { sectionButtons } } }.accessibilityElement(children: .contain).accessibilityLabel("帖子分区")
            if tree.discoveryEnabled, selected == "daily" {
                chips([("daily", "全部日常"), ("help", "提问求助"), ("study", "学习交流")], selected: tree.category) { select($0, "") }
            }
            if tree.discoveryEnabled, selected == "entertainment" {
                chips([("", "全部兴趣")] + TreeholeCategories.interests, selected: tree.interest) { select("entertainment", $0) }
            }
            if tree.discoveryEnabled, let text = TreeholeCategories.description(tree.category) {
                Text(text).font(.caption).foregroundStyle(TreeholeTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4).disabled(tree.busy)
    }
    private var sectionButtons: some View {
        ForEach(sections, id: \.0) { id, label in
            Button { select(id, "") } label: {
                VStack(spacing: 6) {
                    Text(label).font(.subheadline.weight(selected == id ? .semibold : .regular)).fixedSize()
                    Capsule().fill(selected == id ? TreeholeTheme.primary : .clear).frame(height: 3)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(selected == id ? TreeholeTheme.text : TreeholeTheme.muted).accessibilityAddTraits(selected == id ? .isSelected : [])
        }
    }
    private func chips(_ items: [(String, String)], selected: String, choose: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { id, label in
                    Button { choose(id) } label: { Text(label).font(.caption).padding(.horizontal, 12).frame(minHeight: 44).background(selected == id ? TreeholeTheme.tint : TreeholeTheme.background, in: Capsule()) }
                        .buttonStyle(.plain).foregroundStyle(selected == id ? TreeholeTheme.primary : TreeholeTheme.muted).accessibilityAddTraits(selected == id ? .isSelected : [])
                }
            }
        }
    }
}

struct TreeholeDiscoveryComposer: View {
    @Binding var draft: TreeholeDraft
    let enabled: Bool
    private var categories: [(String, String)] { enabled ? TreeholeCategories.sections + TreeholeCategories.all.filter { ["help", "study"].contains($0.0) } : TreeholeCategories.all + (TreeholeCategories.all.contains { $0.0 == draft.category } ? [] : [(draft.category, TreeholeCategories.name(draft.category) + "（暂不可用）")]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("选择分区", selection: $draft.category) { ForEach(categories, id: \.0) { id, label in Text(label).tag(id) } }
            if enabled, draft.category == "entertainment" {
                Picker("选择兴趣标签", selection: Binding(get: { draft.interest ?? "" }, set: { draft.interest = $0 })) {
                    Text("综合 · 不选标签").tag("")
                    ForEach(TreeholeCategories.interests, id: \.0) { id, label in Text(label).tag(id) }
                }
            }
            if draft.category == "treehole" { Text("匿名树洞统一匿名，发布后不会显示你的昵称和头像。").font(.caption).foregroundStyle(.secondary) }
        }.font(.subheadline)
            .onChange(of: draft.category) { category in
                if category == "treehole" { draft.anonymous = true }
                if category != "entertainment" { draft.interest = nil }
            }
            .onAppear { if draft.category == "treehole" { draft.anonymous = true } }
    }
}
