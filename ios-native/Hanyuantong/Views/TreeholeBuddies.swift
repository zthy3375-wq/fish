import SwiftUI

struct TreeholeBuddyEditor: View {
    @Binding var buddy: TreeholeBuddyDraft
    let remove: () -> Void
    private var date: Binding<Date> { Binding(get: { buddy.date ?? Date().addingTimeInterval(3600) }, set: { buddy.startsAt = ISO8601DateFormatter().string(from: $0) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("一起去做点什么").font(.subheadline.bold()); Spacer(); Button("移除报名", action: remove).font(.caption).frame(minHeight: 44) }
            DatePicker("活动时间", selection: date, displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!).environment(\.locale, Locale(identifier: "zh_CN")).font(.caption)
            Text("北京时间 · 未来 90 天内").font(.caption2).foregroundStyle(.secondary)
            TextField("集合地点，例如东操场入口", text: $buddy.location).textFieldStyle(.roundedBorder).accessibilityLabel("搭子集合地点").onChange(of: buddy.location) { buddy.location = String($0.prefix(60)) }
            Stepper("还招 \(buddy.capacity) 位搭子", value: $buddy.capacity, in: 1...20).font(.subheadline).frame(minHeight: 44)
            Text("人数不含你。活动开始后停止报名；发布后时间、地点和人数固定，你可以随时结束招募。").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
struct TreeholeBuddyCard: View {
    let buddy: TreeholeBuddy
    let mine: Bool, locked: Bool, enabled: Bool, pending: Bool
    let join: (Bool) -> Void, close: (Bool) -> Void, members: () -> Void
    var body: some View { TimelineView(.periodic(from: .now, by: 15)) { context in content(at: context.date) } }
    private func content(at date: Date) -> some View {
        let expired = buddy.ended(at: date)
        let status = buddy.closed ? "已结束招募" : expired ? "活动已开始" : locked ? "暂缓招募" : buddy.count >= buddy.capacity ? "已招满" : "正在找搭子"
        let blocked = buddy.closed || expired || locked || buddy.count >= buddy.capacity
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Label(status, systemImage: "person.2").font(.caption.bold()).foregroundStyle(TreeholeTheme.primary); Spacer(); Text("\(buddy.count) / \(buddy.capacity) 人已报名").font(.caption2).foregroundStyle(.secondary) }
            Label(buddy.timeLabel, systemImage: "clock").font(.caption)
            Label(buddy.location, systemImage: "mappin.and.ellipse").font(.subheadline)
            if mine {
                HStack {
                    Button("查看报名", action: members).frame(maxWidth: .infinity, minHeight: 44).disabled(!enabled || pending)
                    Button(pending ? "处理中…" : buddy.closed ? "重新开放" : "结束招募") { close(!buddy.closed) }.frame(maxWidth: .infinity, minHeight: 44).disabled(!enabled || pending || buddy.closed && (expired || locked))
                }.font(.subheadline).buttonStyle(.bordered)
            } else {
                Button(pending ? "处理中…" : buddy.joined ? "已报名 · 退出" : blocked ? status : "一起去 · 报名") { join(!buddy.joined) }.font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent).disabled(!enabled || pending || !buddy.joined && blocked)
            }
            Text(mine ? "名额不含发起人；报名名单仅你可见。" : buddy.joined ? "已加入，可在「我报名的」回来继续聊。" : "报名后昵称和头像仅发起人可见，可随时退出。").font(.caption2).foregroundStyle(.secondary)
            if !enabled { Text("报名服务暂不可用，请稍后再试。").font(.caption2).foregroundStyle(.secondary) }
        }.padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
struct TreeholeBuddyRoster: View {
    @EnvironmentObject var tree: TreeholeStore
    @Environment(\.dismiss) private var dismiss
    let post: TreeholePost
    @State private var members: [TreeholeBuddyMember] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("仅你作为发起人可见，请尊重同学的隐私。").font(.caption).foregroundStyle(.secondary) }
                if let error { Section { Text(error); Button("重试") { Task { await load() } }.disabled(loading) } }
                if members.isEmpty && !loading && error == nil { Text("还没有同学报名，可以在评论里聊聊具体安排。").font(.subheadline) }
                ForEach(members) { member in HStack(spacing: 10) { TreeholeAvatar(name: member.nickname, avatar: member.avatar, size: 36); Text(member.nickname).font(.subheadline); Spacer(); Text(TreeholePresentation.date(member.joinedAt)).font(.caption2).foregroundStyle(.secondary) } }
                Button(loading ? "正在加载…" : "刷新报名名单") { Task { await load() } }.disabled(loading)
            }.navigationTitle("报名名单").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.task { await load() }.onChange(of: tree.user?.id) { _ in members = []; dismiss() }
    }
    private func load() async {
        guard !loading, post.author.mine, let member = tree.user?.id else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await tree.api.request("buddies.members", ["postId": post.id])
            guard !Task.isCancelled, tree.user?.id == member else { return }
            members = result.participants ?? []; if let buddy = result.post?.buddy { tree.applyBuddy(post.id, buddy: buddy) }
        } catch {
            guard !Task.isCancelled, tree.user?.id == member else { return }
            self.error = error.localizedDescription
            if let failure = error as? TreeholeError, failure.code == "session_expired" { tree.clear() }
        }
    }
}
