import SwiftUI

struct AnonymousAnalyticsSettingsView: View {
    @ObservedObject var store: AnonymousAnalyticsStore
    @State private var confirmingDelete = false
    var body: some View {
        List {
            Section("旧版统计记录") {
                Text("应用已停止收集使用数据。可以删除此设备在旧版中上报的记录。")
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
                if store.isSending { ProgressView("正在处理统计请求") }
            }
            if let error = store.error { Section { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("analytics-error") } }
        }.navigationTitle("旧版统计记录").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(CampusTheme.background)
            .confirmationDialog("同时关闭统计并删除该安装已上报的记录？未确认删除时会保留凭证供重试。", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) { store.deleteData() }
                Button("取消", role: .cancel) { }
            }
    }
}
