import SwiftUI

struct TreeholeFollowingView: View {
    @ObservedObject var tree: TreeholeStore
    let open: (String) -> Void
    let browse: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("关注名单仅自己可见，关注动态只展示公开帖子。").font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
            ForEach(tree.following) { person in
                HStack(spacing: 12) {
                    Button { open(person.id) } label: {
                        HStack(spacing: 12) {
                            TreeholeAvatar(name: person.nickname, avatar: person.avatar, size: 42)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(person.nickname).font(.subheadline.weight(.semibold)).foregroundStyle(TreeholeTheme.text)
                                Text(person.bio.isEmpty ? "去看看 TA 的公开分享" : person.bio).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("查看 \(person.nickname) 的主页")
                    Button { Task { await tree.setFollow(person.id, enabled: false) } } label: {
                        Text(tree.pendingFollows.contains(person.id) ? "处理中…" : "已关注").font(.caption).frame(minWidth: 70, minHeight: 44).background(TreeholeTheme.background, in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(tree.pendingFollows.contains(person.id)).accessibilityLabel("取消关注 \(person.nickname)")
                }.padding(.vertical, 14)
                Divider()
            }
            if tree.followingLoading { ProgressView("正在加载关注名单…").frame(maxWidth: .infinity).padding(24) }
            else if let error = tree.followingError {
                Text(error + "，已有名单已保留。").font(.caption).foregroundStyle(.secondary).padding(.top, 20)
                Button("重试加载") { Task { await tree.loadFollowing(more: tree.followingRetryMore) } }.frame(maxWidth: .infinity, minHeight: 44)
            } else if tree.following.isEmpty {
                CampusEmpty(title: "还没有关注同学", detail: "遇到喜欢的分享，点开头像，在主页关注 TA。", symbol: "person.crop.circle.badge.plus")
                Button("去广场看看", action: browse).frame(maxWidth: .infinity, minHeight: 44)
            } else if tree.followingNext != nil {
                Button("加载更多同学") { Task { await tree.loadFollowing(more: true) } }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }.disabled(tree.busy)
    }
}

struct TreeholeFeedScopes: View {
    @ObservedObject var tree: TreeholeStore
    let select: (String) -> Void
    private var items: [(String, String)] { [("all", "广场")] + (tree.followingEnabled ? [("following", "关注动态")] : []) + [("participated", "我参与的"), ("watching", "关注的讨论")] }
    var body: some View {
        CampusAdaptiveRow { HStack(spacing: 12) { buttons } } fallback: { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 18) { buttons } } }.padding(.bottom, 8).disabled(tree.busy)
    }
    private var buttons: some View {
        ForEach(items, id: \.0) { id, label in
            Button { select(id) } label: {
                VStack(spacing: 4) {
                    Text(label).font(.system(size: 13, weight: tree.scope == id ? .semibold : .regular)).fixedSize()
                    Capsule().fill(tree.scope == id ? TreeholeTheme.text : .clear).frame(height: 3)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(tree.scope == id ? TreeholeTheme.text : TreeholeTheme.muted).accessibilityAddTraits(tree.scope == id ? .isSelected : [])
        }
    }
}
