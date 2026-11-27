#if DEBUG
import SwiftUI
import UIKit

struct ParcelDirectoryView: View {
    @StateObject private var directory = ParcelDirectory()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var confirming = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                if directory.busy { ProgressView("正在连接…") }
                else { Text(message).foregroundStyle(.secondary) }
                if let code = directory.userCode {
                    Text(code).font(.title2.monospaced().bold()).privacySensitive()
                    if let url = directory.verificationURL { Button("打开授权网页") { openURL(url) } }
                    Button("取消授权", role: .cancel) { Task { await directory.disconnect() } }
                } else if directory.connected {
                    Button("同步待取包裹") { Task { await directory.refresh(force: true) } }
                } else if directory.state != .unconfigured {
                    Button("授权查询包裹") { Task { await directory.begin() } }
                }
            }.disabled(directory.busy)
            if phase == .active, let snapshot = directory.snapshot, ![.expired, .rejected, .forbidden].contains(directory.state) {
                Section {
                    ForEach(snapshot.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            if let station = item.station { Text(station).font(.subheadline) }
                            if let code = item.pickupCode {
                                Text(code).font(.title.monospaced().bold())
                            } else {
                                Text("数据源暂未返回取件码").font(.subheadline)
                            }
                            Text(item.trackingNumber).font(.caption).foregroundStyle(.secondary)
                            if let code = item.pickupCode {
                                Button("复制取件码") {
                                    UIPasteboard.general.setItems([["public.utf8-plain-text": code]],
                                                                 options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                                    copied = true
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .privacySensitive()
                    }
                } header: {
                    Text("最近成功同步 " + snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if directory.connected {
                Button("断开连接", role: .destructive) { confirming = true }.disabled(directory.busy)
            }
        }
        .navigationTitle("待取包裹 · 联调")
        .navigationBarTitleDisplayMode(.inline)
        .alert("断开连接", isPresented: $confirming) {
            Button("断开", role: .destructive) { Task { await directory.disconnect() } }
            Button("取消", role: .cancel) {}
        } message: { Text("会清除本机的授权和包裹缓存。") }
        .alert("已复制取件码", isPresented: $copied) { Button("好", role: .cancel) {} }
        .task(id: phase) {
            if phase == .active && directory.userCode == nil { await directory.refresh() }
        }
        .task(id: phase == .active ? directory.userCode : nil) {
            while !Task.isCancelled && phase == .active && directory.userCode != nil {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
                await directory.poll()
            }
        }
    }

    private var message: String {
        switch directory.state {
        case .unconfigured: return "本测试包尚未配置获准提供待取列表的数据源。"
        case .disconnected: return "连接包裹数据源后可在此同步待取包裹。"
        case .pending: return "请在授权网页完成验证，返回后自动检查。"
        case .waiting: return "授权已保存，等待首次同步。"
        case .empty: return "暂无待取包裹。"
        case .ready: return "已同步待取包裹。"
        case .denied: return "你取消了本次授权。"
        case .expired, .rejected: return directory.connected ? "授权已过期，请断开连接后重新授权。" : "本次授权已过期，请重试。"
        case .rateLimited: return "服务限制请求频率，请稍后重试。"
        case .forbidden: return "此账号没有包裹查询权限。"
        case .incomplete: return "服务没有返回完整列表。"
        case .unavailable: return "暂时无法同步，请稍后重试。"
        }
    }
}
#endif
