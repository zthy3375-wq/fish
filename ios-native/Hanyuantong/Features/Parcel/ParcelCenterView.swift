import SwiftUI
import UIKit
import WebKit

struct ParcelCenterView: View {
    @StateObject private var store = ParcelStore()
    @State private var identityMode = false
    @State private var enlarged: ParcelDisplayItem?
    @State private var clearing: ParcelProvider?
    @State private var showTaken = false
    @State private var hidden = false
    var body: some View {
        List {
            Section {
                Text("取件码").font(.title2.bold())
                Text("在官方页登录并读取当前待取页，取件码会保存为本机卡片。身份码仍由官方页显示，打不开时可用系统入口。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(ParcelProvider.allCases) { provider in
                Section(provider.title) {
                    HStack {
                        Button { identityMode = false; store.open(provider) } label: { Label("查看 / 读取取件码", systemImage: "shippingbox") }
                        Spacer()
                        Button("身份码") { identityMode = true; store.open(provider) }
                    }.buttonStyle(.borderless)
                    if let notice = store.notices[provider] { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                    if let time = store.caches[provider]?.lastReadAt {
                        Text("上次读取 \(CampusTheme.date(time, format: "MM-dd HH:mm")) · 仅当前页").font(.caption).foregroundStyle(.secondary)
                    }
                    if hidden { Text("取件信息已隐藏").foregroundStyle(.secondary) }
                    else {
                        let values = (store.caches[provider]?.items ?? []).filter { showTaken ? $0.locallyTakenAt != nil : $0.locallyTakenAt == nil }
                        ForEach(values.sorted { a, b in a.station == b.station ? a.code < b.code : a.station < b.station }) { item in
                            VStack(alignment: .leading, spacing: 9) {
                                Button { enlarged = ParcelDisplayItem(provider: provider, item: item) } label: {
                                    Text(item.code).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(CampusTheme.text)
                                        .lineLimit(2).minimumScaleFactor(0.65).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).accessibilityLabel("取件码 \(item.code)，点按放大")
                                Text(item.station.isEmpty ? "驿站待核对" : item.station).font(.subheadline)
                                Text("\(CampusTheme.date(item.observedAt, format: "MM-dd HH:mm")) 读取 · 请核对是否仍有效").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("复制取件码") { copy(item.code) }
                                    Spacer()
                                    Button(item.locallyTakenAt == nil ? "我已取件" : "撤销本机标记") { store.mark(item, provider: provider, taken: item.locallyTakenAt == nil) }
                                }.font(.footnote).buttonStyle(.borderless)
                            }.padding(.vertical, 8)
                        }
                        if values.isEmpty { Text(showTaken ? "没有本机已取记录" : "暂无已读取取件码，请在官方页查看。未读取不等于没有包裹。").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Menu("更多") {
                        Button("系统打开官方入口") { UIApplication.shared.open(provider.fallbackURL) { success in if !success { store.message = "当前无法打开，请使用对应官方 App。" } } }
                        Button("清除本机登录与记录", role: .destructive) { clearing = provider }
                    }
                }
            }
            Section {
                Toggle("查看本机已取记录", isOn: $showTaken)
                Text("“我已取件”只是本机标记，不会确认收货。读取不到字段时不会猜测取件码；失败、部分和空页面不会删除历史码。缓存为加密的本人记录，不进入个人备份或统计。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("拼多多网页登录可能影响官方 App 会话。iPhone 页面兼容、非空取件码和现场扫码仍需实际验证；系统备用入口为官网，不能保证直达出库码。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .privacySensitive()
        .navigationTitle("取快递").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $store.activeSession, onDismiss: { store.close() }) { session in
            ParcelOfficialPage(session: session, cookies: store.cookies(for: session.provider), identity: identityMode, close: store.close)
        }
        .sheet(item: $enlarged) { value in
            NavigationStack {
                VStack(spacing: 24) {
                    Text(value.provider.title).font(.headline)
                    Text(value.item.station.isEmpty ? "驿站待核对" : value.item.station)
                    Text(value.item.code).font(.system(size: 58, weight: .bold, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(2)
                    Text("读取于 \(CampusTheme.date(value.item.observedAt, format: "MM-dd HH:mm"))\n历史码可能失效，请与官方页核对。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("复制取件码") { copy(value.item.code) }.buttonStyle(.borderedProminent)
                }.padding(24).privacySensitive().navigationTitle("取件码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { enlarged = nil } } }
            }
        }
        .confirmationDialog("清除本机登录与取件记录？", isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } }), titleVisibility: .visible) {
            if let provider = clearing { Button("清除\(provider.title)", role: .destructive) { store.logout(provider); clearing = nil } }
            Button("取消", role: .cancel) { clearing = nil }
        } message: { Text("只清除邯院通中该平台的登录与记录，不退出官方 App，也不修改平台包裹状态。") }
        .alert("取件中心", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("好", role: .cancel) {} } message: { Text(store.message ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in hidden = true; enlarged = nil; store.close() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in hidden = false }
        .onDisappear { enlarged = nil; store.close() }
    }
    private func copy(_ code: String) {
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        store.message = "已复制取件码，剪贴板保留 1 分钟且不跨设备同步。"
    }
}
private struct ParcelDisplayItem: Identifiable {
    let provider: ParcelProvider
    let item: ParcelPickup
    var id: String { provider.rawValue + ":" + item.id }
}
private struct ParcelOfficialPage: View {
    @ObservedObject var session: ParcelSession
    let cookies: [HTTPCookie]
    let identity: Bool
    let close: () -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button("待取包裹") { session.open(identity: false) }
                    Spacer()
                    Button("官方身份码") { session.open(identity: true) }
                    Spacer()
                    if session.isLoading || session.isReading { Button("停止") { session.stop() } }
                    else { Button("刷新") { session.refresh() } }
                }.font(.subheadline).padding(.horizontal).padding(.vertical, 10)
                Text(session.status).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.bottom, 8)
                if let web = session.web { ParcelWebView(web: web) }
                else { Spacer(); ProgressView(); Spacer() }
                Button { session.readCurrent() } label: {
                    Label(session.isReading ? "正在读取…" : "读取当前页取件码", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).padding().disabled(!session.canRead || session.isLoading || session.isReading)
            }
            .privacySensitive().navigationTitle(session.provider.title + "官方页面").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { close() } } }
            .task { await session.prepare(cookies: cookies, identity: identity) }
        }
    }
}
private struct ParcelWebView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
