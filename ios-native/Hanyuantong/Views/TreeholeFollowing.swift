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
    let continueScope: String
    let select: (String) -> Void
    var body: some View {
        HStack(spacing: 12) {
            tab("广场", "all")
            if tree.followingEnabled { tab("关注", "following") }
            tab("继续聊", continueScope)
        }
    }
    private func tab(_ label: String, _ id: String) -> some View {
        let active = tree.scope == id
        return Button(label) { select(id) }
            .font(.subheadline.weight(active ? .bold : .medium))
            .foregroundStyle(active ? TreeholeTheme.text : TreeholeTheme.muted)
            .fixedSize().frame(minHeight: 44)
            .overlay(alignment: .bottom) {
                if active { Capsule().fill(TreeholeTheme.primary).frame(width: 16, height: 2).padding(.bottom, 5) }
            }.accessibilityAddTraits(active ? .isSelected : [])
    }
}
