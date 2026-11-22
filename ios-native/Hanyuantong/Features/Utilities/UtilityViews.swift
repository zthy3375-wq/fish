import SwiftUI
import UIKit

enum NativeDestinations {
    static let community = "434217654"
    static let communityCard = URL(string: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=\(community)&card_type=group&source=qrcode")!
}
struct ParcelShortcutsView: View {
    @State private var opening: ParcelProvider?
    @State private var message: String?
    var body: some View {
        List {
            Section("打开官方取件码") {
                ForEach(ParcelProvider.allCases) { provider in
                    Button {
                        guard opening == nil else { return }
                        opening = provider
                        Task { @MainActor in
                            defer { opening = nil }
                            let opened = await provider.openPickupCode { await UIApplication.shared.open($0) }
                            if !opened { message = "无法打开\(provider.title)取件码。请稍后重试，或在官方 App 中查看。" }
                        }
                    } label: {
                        Label(provider == .taobao ? "淘宝取件码" : "拼多多取件码", systemImage: "shippingbox")
                    }
                }.disabled(opening != nil)
            }
            Section {
                NavigationLink("本机取件记录") { ParcelCenterView() }
            }
        }.navigationTitle("取快递").navigationBarTitleDisplayMode(.inline)
            .alert("打开取件码", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好", role: .cancel) {} } message: { Text(message ?? "") }
    }
}
struct NativeReminderSettingsView: View {
    @ObservedObject var reminders: NativeReminders
    @EnvironmentObject var store: CampusStore
    var body: some View {
        Form {
            Section("个人课程") {
                Toggle("开启上课提醒", isOn: Binding(get: { reminders.preferences.courses }, set: { value in change { $0.courses = value } }))
                Picker("提前时间", selection: Binding(get: { reminders.preferences.courseMinutes }, set: { value in change { $0.courseMinutes = value } })) {
                    ForEach([5,10,15,30,60], id: \.self) { Text("\($0) 分钟").tag($0) }
                }
            }
            Section("个人待办") {
                Toggle("开启待办提醒", isOn: Binding(get: { reminders.preferences.tasks }, set: { value in change { $0.tasks = value } }))
                Picker("提前时间", selection: Binding(get: { reminders.preferences.taskMinutes }, set: { value in change { $0.taskMinutes = value } })) {
                    ForEach([0,5,10,30,60,1440], id: \.self) { Text($0 == 0 ? "计划时间" : "提前 \($0) 分钟").tag($0) }
                }
            }
            Section {
                Text(reminders.status)
                Text("开启后，个人课程/待办标题可能显示在锁屏通知中。学校与学习通数据不会自动安排提醒。最多续排最近60条（其中待办最多30条）；专注模式、系统权限或长时间不打开 App 可能影响送达。").font(.footnote).foregroundStyle(.secondary)
                Button("检查并重新安排") { store.refreshReminders() }
                Button("打开 iPhone 通知设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        }.disabled(reminders.busy).navigationTitle("系统提醒").navigationBarTitleDisplayMode(.inline)
    }
    private func change(_ update: (inout ReminderPreferences) -> Void) {
        var value = reminders.preferences; update(&value)
        Task { await reminders.update(value); store.refreshReminders() }
    }
}
struct CommunityGroupSection: View {
    @Environment(\.openURL) private var openURL
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openURL(NativeDestinations.communityCard) { opened in
                    status = opened ? "已请求打开 QQ。如未显示群资料，可复制群号搜索。" : "当前无法打开 QQ，可复制群号后在 QQ 搜索。"
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2").foregroundStyle(CampusTheme.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("加入 QQ 交流群").font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.text)
                        Text("交流使用体验 · 反馈问题与建议").font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(CampusTheme.primary)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(CampusPressStyle())
            .accessibilityLabel("加入 QQ 交流群")
            .accessibilityHint("交流使用体验，反馈问题与建议")
            Divider()
            HStack {
                Text("群号").font(.caption).foregroundStyle(CampusTheme.muted)
                Text(NativeDestinations.community).font(.caption.weight(.semibold)).monospacedDigit()
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = NativeDestinations.community
                    status = "群号已复制"
                } label: {
                    Label("复制群号", systemImage: "doc.on.doc")
                        .font(.caption)
                        .frame(minHeight: 44)
                }
                .buttonStyle(CampusPressStyle())
                .foregroundStyle(CampusTheme.primary)
            }
            if let status {
                Text(status).font(.footnote).foregroundStyle(CampusTheme.muted).padding(.bottom, 8)
            }
        }
    }
}
struct NativeHelpView: View {
    @EnvironmentObject var store: CampusStore
    var body: some View {
        List {
            Section("同步问题反馈") {
                CampusShareLink(item: diagnostic) { Label("分享脱敏状态", systemImage: "square.and.arrow.up") }
                Text("仅包含版本、平台、教务连接状态和记录数量，不包含账号、密码、会话、课程名称或待办内容。请在系统分享面板选择接收方。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("使用说明") {
                Text("学校登录在学校官方网页完成。登录失效时请重新连接；部分模块失败时保留上次成功记录。")
                Text("iPhone 开发版不使用 Android 的安装包或在线更新配置。尚需真实账号、真机与第三方官方 App 联调验收。")
            }
        }.navigationTitle("帮助与反馈").navigationBarTitleDisplayMode(.inline)
    }
    private var diagnostic: String {
        "邯院通 iPhone 原生版\n版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知")\n教务已连接：\(store.isConnected ? "是" : "否")\n课程条数：\(store.courses.count)\n成绩条数：\(store.grades.count)\n考试条数：\(store.exams.count)\n未包含账号、课程名称或凭证。"
    }
}

/// Previous Android release notes are shown as historical app milestones, not as a
/// claim that those Android APK builds were shipped on iPhone.
struct NativeReleaseHistoryView: View {
    private let entries: [(version: String, note: String)] = [
        ("1.3.0", "校园社区上线，支持发帖、评论和私信。在「我的」可以查看荣誉收藏，也可以直接加入 QQ 交流群。"),
        ("1.3.0-test.30", "在「我的」和社区主页翻看荣誉展柜，点开徽章可以看看它的来历。"),
        ("1.3.0-test.29", "昵称旁的身份标识变小了。校园各处多了几段可以收入收藏馆的小插曲。"),
        ("1.3.0-test.28", "在「我的」进入荣誉殿堂，可以分类翻看全局成就，也可以挑出喜欢的收藏。"),
        ("1.3.0-test.26", "社区加入官方身份、荣誉称号和成就展示。"),
        ("1.2.4", "学校课程可以按周调整时间和地点，支持确认冲突和恢复原安排。"),
        ("1.2.1", "改善学习通作业读取与单课程刷新，修复部分旧接水记录影响扫码的问题。"),
        ("1.2", "加入桌面课表小组件和洗澡码，校园地图改为东、西校区平面图。"),
        ("1.1", "调整课程管理入口，作业、考试更好找了。首页迎来了校园小鱼。"),
        ("1.0.1", "可以在应用内查看新版说明，下载并校验安装包。"),
        ("1.0.0", "邯院通有了自己的名字和图标。")
    ]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("邯院通 Android 历史版本记录")
                    .font(.footnote).foregroundStyle(CampusTheme.muted)
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.version).font(.headline)
                        Text(entry.note).font(.subheadline)
                            .foregroundStyle(CampusTheme.text).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11)
                    Divider()
                }
                Button {
                    MedalJournal.shared.unlock("lastline")
                } label: {
                    Text("— 小金鱼，记于邯院")
                        .font(.caption).foregroundStyle(CampusTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("release-history-colophon")
            }.padding(18).frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }.background(CampusTheme.background).navigationTitle("更新日志")
            .navigationBarTitleDisplayMode(.inline)
    }
}
