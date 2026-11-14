import SwiftUI
import UIKit

enum NativeDestinations {
    static let taobao = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code")!
    static let pinduoduo = URL(string: "https://mobile.yangkeduo.com/")!
    static let community = "434217654"
}
struct ParcelShortcutsView: View {
    @State private var message: String?
    var body: some View {
        List {
            Section {
                Text("取快递").font(.title2.bold())
                Text("打开官方入口后，由你在对应平台查看出库码。邯院通不会读取快递账号或出库码。")
            }
            Section {
                Button { open(NativeDestinations.taobao) } label: { Label("淘宝出库码官方页面", systemImage: "shippingbox") }
                Button { open(NativeDestinations.pinduoduo) } label: { Label("拼多多官方入口", systemImage: "shippingbox.fill") }
                Text("拼多多当前仅使用经核验的官网入口，进入 App 后需自行打开多多买菜/快递出库码。Android 专用跳转不作为 iPhone 支持承诺。是否打开 App 由 iOS 与平台配置决定。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("取快递").navigationBarTitleDisplayMode(.inline)
            .alert("打开官方入口", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好", role: .cancel) {} } message: { Text(message ?? "") }
    }
    private func open(_ url: URL) {
        UIApplication.shared.open(url) { success in
            if !success { message = "当前无法打开，请稍后重试或在官方 App 中查看。" }
        }
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
struct NativeHelpView: View {
    @EnvironmentObject var store: CampusStore
    @State private var copied = false
    var body: some View {
        List {
            Section("邯院通交流群") {
                Text("QQ 群：\(NativeDestinations.community)").textSelection(.enabled)
                Button("复制群号") { UIPasteboard.general.string = NativeDestinations.community; copied = true }
                Text("请在 QQ 中搜索群号加入；不会自动入群或发送消息。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("同步问题反馈") {
                ShareLink(item: diagnostic) { Label("分享脱敏状态", systemImage: "square.and.arrow.up") }
                Text("仅包含版本、平台、教务连接状态和记录数量，不包含账号、密码、会话、课程名称或待办内容。请在系统分享面板选择接收方。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("使用说明") {
                Text("学校登录在学校官方网页完成。登录失效时请重新连接；部分模块失败时保留上次成功记录。")
                Text("iPhone 开发版不使用 Android 的安装包或在线更新配置。尚需真实账号、真机与第三方官方 App 联调验收。")
            }
        }.navigationTitle("帮助与反馈").navigationBarTitleDisplayMode(.inline)
            .alert("群号已复制", isPresented: $copied) { Button("好", role: .cancel) {} }
    }
    private var diagnostic: String {
        "邯院通 iPhone 原生版\n版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知")\n教务已连接：\(store.isConnected ? "是" : "否")\n课程条数：\(store.courses.count)\n成绩条数：\(store.grades.count)\n考试条数：\(store.exams.count)\n未包含账号、课程名称或凭证。"
    }
}
