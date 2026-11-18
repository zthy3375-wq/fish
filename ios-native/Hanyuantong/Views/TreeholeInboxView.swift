import SwiftUI

struct TreeholeInboxView: View {
    @ObservedObject var tree: TreeholeStore
    let open: (TreeholeNotification) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("每一份回应，都在这里").font(.subheadline.weight(.semibold))
                    Text(tree.unreadCount > 0 ? "\(tree.unreadCount) 条未读互动" : "看看之前的交流，也可以继续聊聊").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await tree.loadInbox() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("刷新互动消息")
            }.padding(.vertical, 16)
            HStack(spacing: 24) {
                ForEach([("all", "全部"), ("replies", "回复与招募"), ("likes", "赞与回应")], id: \.0) { id, label in
                    Button { tree.inboxFilter = id; tree.notifications = []; tree.inboxNext = nil; Task { await tree.loadInbox() } } label: {
                        Text(label).font(.subheadline.weight(tree.inboxFilter == id ? .semibold : .regular)).frame(minHeight: 44)
                    }.foregroundStyle(tree.inboxFilter == id ? TreeholeTheme.text : TreeholeTheme.muted)
                }
                Spacer(minLength: 0)
                Button { tree.perform { try await tree.readNotifications(tree.notifications.filter { $0.readAt == nil }.map(\.id)) } } label: { Image(systemName: "checkmark.circle").frame(width: 44, height: 44) }.accessibilityLabel("将当前消息标为已读").disabled(!tree.notifications.contains { $0.readAt == nil })
            }.disabled(tree.inboxLoading)
            Divider()
            if let error = tree.inboxError { HStack { Text(error).font(.caption); Spacer(); Button("重试") { Task { await tree.loadInbox(more: !tree.notifications.isEmpty && tree.inboxNext != nil) } } }.padding(.vertical, 16) }
            if tree.inboxLoading && tree.notifications.isEmpty { ProgressView("正在加载互动消息…").frame(maxWidth: .infinity).padding(30) }
            else if tree.notifications.isEmpty && tree.inboxError == nil { CampusEmpty(title: "回应会来到这里", detail: "有人回复你、点赞，或关注的讨论有新回复时，就能在这里找到。", symbol: "bell") }
            LazyVStack(spacing: 0) {
                ForEach(tree.notifications) { item in
                    Button { open(item) } label: { row(item) }.buttonStyle(.plain).disabled(tree.busy)
                    Divider()
                }
            }
            if tree.inboxNext != nil { Button(tree.inboxLoading ? "正在加载…" : "更早的互动") { Task { await tree.loadInbox(more: true) } }.frame(maxWidth: .infinity, minHeight: 48).disabled(tree.inboxLoading) }
        }
    }
    private func row(_ item: TreeholeNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.hasSuffix("like") ? "hand.thumbsup" : "bubble.left").font(.system(size: 18)).frame(width: 40, height: 40).background(TreeholeTheme.tint, in: Circle()).foregroundStyle(TreeholeTheme.primary)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.actor.name).font(.subheadline.weight(.semibold)).foregroundStyle(TreeholeTheme.text)
                    Spacer(minLength: 4)
                    Text(TreeholePresentation.date(item.createdAt)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.label).font(.caption).foregroundStyle(.secondary)
                if !item.kind.hasSuffix("like") { Text(item.excerpt).font(.body).lineSpacing(4).lineLimit(3).foregroundStyle(TreeholeTheme.text) }
                Text(item.postTitle.isEmpty ? "图片分享" : item.postTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 7))
            }
            if item.readAt == nil { Circle().fill(TreeholeTheme.primary).frame(width: 7, height: 7).padding(.top, 6).accessibilityLabel("未读") }
        }.padding(.vertical, 18).padding(.horizontal, 8).background(item.readAt == nil ? TreeholeTheme.tint.opacity(0.5) : TreeholeTheme.surface).multilineTextAlignment(.leading)
    }
}
