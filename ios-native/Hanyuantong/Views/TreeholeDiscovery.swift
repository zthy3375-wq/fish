import SwiftUI

struct TreeholeDiscoveryBar: View {
    @ObservedObject var tree: TreeholeStore
    let select: (String, String) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var boardWidth: CGFloat = 46
    private let primary = [("all", "全部"), ("daily", "校园"), ("study", "学习"), ("entertainment", "兴趣"), ("buddies", "搭子"), ("treehole", "树洞")]
    private var selected: String { tree.category == "help" ? "daily" : tree.category }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if tree.discoveryEnabled {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: boardWidth), spacing: 2)], spacing: 0) {
                    ForEach(primary, id: \.0) { id, label in
                        Button { if selected != id { select(id, "") } } label: {
                            Text(label).font(.subheadline.weight(selected == id ? .bold : .medium))
                                .fixedSize(horizontal: false, vertical: true)
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
    @State private var choosing = false
    @State private var more = false
    private var destination: String {
        if let topic = draft.interest, !TreeholeCategories.interestName(topic).isEmpty {
            return TreeholeCategories.interestName(topic)
        }
        return ["help": "校园互助", "entertainment": "兴趣闲聊", "buddies": "找搭子"][draft.category] ?? TreeholeCategories.name(draft.category)
    }
    private var legacyCategories: [(String, String)] {
        TreeholeCategories.all.contains { $0.0 == draft.category } ? TreeholeCategories.all :
            TreeholeCategories.all + [(draft.category, destination + "（暂不可用）")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if enabled {
                Button {
                    more = TreeholeCategories.interests.contains { $0.0 == draft.interest }
                    choosing = true
                } label: {
                    HStack { Text("发布到"); Spacer(); Text(destination).bold(); Image(systemName: "chevron.down") }
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("选择分区").accessibilityValue(destination)
            } else {
                Picker("选择分区", selection: $draft.category) {
                    ForEach(legacyCategories, id: \.0) { id, label in Text(label).tag(id) }
                }
            }
            if draft.category == "treehole" { Text("匿名树洞统一匿名，发布后不会显示你的昵称和头像。").font(.caption).foregroundStyle(.secondary) }
        }.font(.subheadline)
            .onChange(of: draft.category) { category in
                if category == "treehole" { draft.anonymous = true }
                if !TreeholeCategories.topics(category, boards: boards).contains(where: { $0.0 == draft.interest }) { draft.interest = nil }
            }
            .onAppear { if draft.category == "treehole" { draft.anonymous = true } }
            .sheet(isPresented: $choosing) {
                CampusNavigation {
                    List {
                        Section("校园") { option("校园日常", "daily"); option("校园互助", "help") }
                        Section("学习") { option("学习交流", "study"); if boards { option("考研", "study", "graduate") } }
                        Section("兴趣") {
                            option("兴趣闲聊", "entertainment")
                            if boards { option("读书", "entertainment", "reading"); option("健身", "entertainment", "fitness") }
                            DisclosureGroup("更多兴趣", isExpanded: $more) {
                                ForEach(TreeholeCategories.interests, id: \.0) { id, name in option(name, "entertainment", id) }
                            }
                        }
                        Section("搭子与树洞") { option("找搭子", "buddies"); option("匿名树洞", "treehole") }
                    }.navigationTitle("选择分区").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { choosing = false } } }
                }.presentationDetents([.medium, .large])
            }
    }
    private func option(_ label: String, _ category: String, _ topic: String? = nil) -> some View {
        Button {
            draft.category = category; draft.interest = topic
            if category == "treehole" { draft.anonymous = true }
            choosing = false
        } label: {
            HStack {
                Text(label); Spacer()
                if draft.category == category && (draft.interest ?? "") == (topic ?? "") { Image(systemName: "checkmark") }
            }
        }
    }
}
