import SwiftUI

struct AnonymousAnalyticsSettingsView: View {
    @ObservedObject var store: AnonymousAnalyticsStore
    @State private var confirmingDelete = false
    var body: some View {
        List {
            Section("使用统计") {
                LabeledContent("参与状态", value: store.state.choice == .on ? "已开启" : store.state.choice == .off ? "已关闭" : "尚未选择")
                Text("仅统计活跃安装、应用版本和预设功能使用次数。随机安装标识仅用于统计，不读取硬件标识，不上传学号、密码、课程、余额或订单。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
                if let reason = store.unavailableReason {
                    Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(CampusTheme.muted)
                        .accessibilityIdentifier("analytics-unavailable")
                }
                Toggle("参与匿名统计", isOn: Binding(get: { store.state.choice == .on }, set: { store.setEnabled($0) }))
                    .disabled(!store.canEnable && store.state.choice != .on)
                    .accessibilityIdentifier("analytics-consent")
                if store.state.choice == .unset {
                    Button("暂不参与") { store.setEnabled(false) }.accessibilityIdentifier("analytics-decline")
                }
                Text("统计默认关闭，不影响校园功能。开启后按北京时间每日汇总；每项每天最多 1000 次，进入饮水或洗衣流程不代表付款或使用成功。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Section("关闭与删除") {
                Text("关闭后停止新采集和上报，已经发出的请求仍可能完成。删除会同时关闭统计；联网删除未确认前会保留本机加密凭证，下次打开 App 或手动重试时继续处理。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
                Text("服务端每日明细保留近 90 天，过期数据随后续上报清理；安装记录保留至删除。网络服务会接收连接地址，统计数据库使用每日加盐摘要防滥用，托管网络日志另由服务提供方管理。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
                if store.state.deletePending {
                    Label(store.state.deletionUncertain ? "已关闭，删除结果待确认" : "已关闭，等待删除确认", systemImage: "clock")
                        .accessibilityIdentifier("analytics-delete-pending")
                    Button("重试删除") { store.deleteData() }.disabled(store.isSending)
                } else {
                    Button("删除已上报记录", role: .destructive) { confirmingDelete = true }
                        .disabled(!store.state.hasIdentity).accessibilityIdentifier("analytics-delete")
                }
                if let last = store.state.lastSent {
                    LabeledContent("上次上报", value: CampusTheme.date(last, format: "M月d日 HH:mm")).font(.caption)
                }
                if store.state.choice == .on {
                    Button("重试上报") { store.flush(force: true) }.disabled(store.isSending)
                }
                if store.isSending { ProgressView("正在处理统计请求") }
            }
            if let error = store.error { Section { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("analytics-error") } }
        }.navigationTitle("匿名使用统计").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(CampusTheme.background)
            .confirmationDialog("同时关闭统计并删除该安装已上报的记录？未确认删除时会保留凭证供重试。", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) { store.deleteData() }
                Button("取消", role: .cancel) { }
            }
    }
}
