import SwiftUI

struct TreeholeDiscoveryBar: View {
    @ObservedObject var tree: TreeholeStore
    let select: (String, String) -> Void
    private let primary = [("all", "全部"), ("daily", "校园"), ("study", "学习"), ("entertainment", "兴趣"), ("buddies", "搭子"), ("treehole", "树洞")]
    private var selected: String { tree.category == "help" ? "daily" : tree.category }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if tree.discoveryEnabled {
                HStack(spacing: 2) {
                    ForEach(primary, id: \.0) { id, label in
                        Button { if selected != id { select(id, "") } } label: {
                            Text(label).font(.subheadline.weight(selected == id ? .bold : .medium))
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if selected == id { Capsule().fill(TreeholeTheme.primary).frame(width: 16, height: 2).padding(.bottom, 5) }
                                }
                        }.accessibilityAddTraits(selected == id ? .isSelected : [])
                    }
                }.accessibilityElement(children: .contain).accessibilityLabel("帖子分区")
                if selected == "daily" {
                    chips([("daily", "日常"), ("help", "校园互助")], selected: tree.category) { select($0, "") }
                } else if selected == "study", tree.boardsEnabled {
                    chips([("", "全部学习"), ("graduate", "考研")], selected: tree.interest) { select("study", $0) }
                } else if selected == "entertainment" {
                    HStack {
                        chips([("", "全部兴趣")] + (tree.boardsEnabled ? [("reading", "读书"), ("fitness", "健身")] : []), selected: tree.interest) { select("entertainment", $0) }
                        Menu {
                            ForEach(TreeholeCategories.interests, id: \.0) { id, name in Button(name) { select("entertainment", id) } }
                        } label: { Label(TreeholeCategories.interests.first { $0.0 == tree.interest }?.1 ?? "更多", systemImage: "chevron.down") }
                        .fixedSize().accessibilityLabel("更多兴趣")
                    }.font(.caption)
                }
            } else {
                Menu(tree.category == "all" ? "全部分区" : TreeholeCategories.name(tree.category)) {
                    Button("全部分区") { select("all", "") }
                    ForEach(TreeholeCategories.all, id: \.0) { id, name in Button(name) { select(id, "") } }
                }.frame(minHeight: 44).accessibilityLabel("帖子分区")
            }
            Divider()
        }.buttonStyle(.plain).disabled(tree.busy)
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
    var boards=false
    private var categories: [(String, String)] { enabled ? TreeholeCategories.sections + TreeholeCategories.all.filter { ["help", "study"].contains($0.0) } : TreeholeCategories.all + (TreeholeCategories.all.contains { $0.0 == draft.category } ? [] : [(draft.category, TreeholeCategories.name(draft.category) + "（暂不可用）")]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("选择分区", selection: $draft.category) { ForEach(categories, id: \.0) { id, label in Text(label).tag(id) } }
            if enabled, !TreeholeCategories.topics(draft.category,boards:boards).isEmpty {
                Picker("选择兴趣标签", selection: Binding(get: { draft.interest ?? "" }, set: { draft.interest = $0 })) {
                    Text("综合 · 不选标签").tag("")
                    ForEach(TreeholeCategories.topics(draft.category,boards:boards), id: \.0) { id, label in Text(label).tag(id) }
                }
            }
            if draft.category == "treehole" { Text("匿名树洞统一匿名，发布后不会显示你的昵称和头像。").font(.caption).foregroundStyle(.secondary) }
        }.font(.subheadline)
            .onChange(of: draft.category) { category in
                if category == "treehole" { draft.anonymous = true }
                if !TreeholeCategories.topics(category,boards:boards).contains(where:{$0.0 == draft.interest}) { draft.interest=nil }
            }
            .onAppear { if draft.category == "treehole" { draft.anonymous = true } }
    }
}
