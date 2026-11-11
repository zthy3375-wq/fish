import SwiftUI

struct QuzhiWalletView: View {
    @ObservedObject var store: QuzhiStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var month = QuzhiProtocol.currentMonth()
    @State private var showLogin = false
    @State private var showRecharge = false
    @State private var showLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("校园生活", systemImage: "drop.fill").font(.caption).foregroundStyle(CampusTheme.primary)
                Text("洗澡码、余额、账单与充值").foregroundStyle(CampusTheme.muted)
                if !store.error.isEmpty { notice(store.error) }
                if store.cleanupRequired {
                    Button("重试清除趣智本机数据", role: .destructive) { _ = store.logout() }
                } else if !store.ready {
                    Button("重新读取本机趣智账户") { store.restore() }.buttonStyle(.bordered)
                } else if !store.connected {
                    disconnected
                } else {
                    connected
                }
            }.padding(20)
        }
        .background(CampusTheme.background)
        .navigationTitle("趣智校园").navigationBarTitleDisplayMode(.inline)
        .tint(CampusTheme.primary)
        .refreshable { if store.valid { _ = await store.refresh(month: month) } }
        .task {
            store.restore()
            if store.valid { _ = await store.refresh(month: month) }
        }
        .onDisappear { store.cancel() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await store.resumeAfterRecharge(month: month) } }
            else { store.suspend() }
        }
        .sheet(isPresented: $showLogin) { QuzhiLoginView(store: store, month: month) }
        .alert("前往支付宝的趣智充值页", isPresented: $showRecharge) {
            Button("取消", role: .cancel) {}
            Button("打开充值页") {
                guard let url = store.beginRechargeHandoff() else { return }
                openURL(url) { store.finishRechargeHandoff(opened: $0) }
            }
        } message: {
            Text("当前连接：\(store.phone) · \(store.snapshot.school.isEmpty ? "学校待核对" : store.snapshot.school)。支付宝可能登录了另一个账户，请在付款前核对学校、手机号、金额及退款规则。本操作只打开页面，不创建充值订单或付款。")
        }
        .alert("退出并清除趣智缓存？", isPresented: $showLogout) {
            Button("取消", role: .cancel) {}
            Button("确认退出", role: .destructive) { _ = store.logout() }
        } message: { Text("清除此账户在本机保存的余额、账单和会话，保留教务、其他生活服务与个人事项。") }
    }
    private var disconnected: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.pass").font(.largeTitle).foregroundStyle(CampusTheme.primary)
            Text("把洗澡钱包放在这里").font(.headline)
            Text("连接已有趣智账户，直接查余额和账单。充值可前往支付宝中的趣智充值页。")
                .font(.subheadline).foregroundStyle(CampusTheme.muted).multilineTextAlignment(.center)
            Button("连接趣智校园") { store.concealBathCode(); showLogin = true }
                .buttonStyle(.borderedProminent).foregroundStyle(CampusTheme.onPrimary).disabled(store.busy)
            Text("手机号、密码或验证码仅在原生登录窗口填写。会话加密留在本机，不保存密码或验证码。")
                .font(.caption).foregroundStyle(CampusTheme.muted)
        }.frame(maxWidth: .infinity).campusCard()
    }
    @ViewBuilder private var connected: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.snapshot.school.isEmpty ? "学校信息尚未取得" : store.snapshot.school).font(.headline)
                Text(store.phone).font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Spacer()
            Button { Task { _ = await store.refresh(month: month) } } label: {
                if store.busy { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }.frame(minWidth: 44, minHeight: 44).disabled(store.busy || !store.valid)
                .accessibilityLabel("刷新趣智余额与账单")
        }
        if store.expired {
            VStack(alignment: .leading, spacing: 10) {
                Text("登录已失效，下方为上次查询结果。")
                Button("重新连接") { store.concealBathCode(); showLogin = true }.disabled(store.busy)
            }.font(.subheadline).campusCard()
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("账户总余额").font(.subheadline).foregroundStyle(CampusTheme.muted)
            Text("¥ " + store.balanceText).font(.system(size: 36, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(store.busy ? "正在更新…" : "查询于 " + timestamp(store.snapshot.walletUpdatedAt))
                .font(.caption).foregroundStyle(CampusTheme.muted)
            Button { showRecharge = true } label: { Label("充值 · 支付宝", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).foregroundStyle(CampusTheme.onPrimary).disabled(store.busy || !store.valid)
        }.campusCard()
        if let issue = store.snapshot.issues["wallet"] { notice("余额未更新：" + issue.localizedDescription) }
        if let issue = store.snapshot.issues["school"] { notice("学校信息未更新：" + issue.localizedDescription) }
        if store.returnedFromRecharge { notice("已从充值页面返回，请核对余额；实际到账以平台余额和支付订单为准。") }
        bathCard
        billsCard
        DisclosureGroup("账户管理") {
            VStack(alignment: .leading, spacing: 12) {
                Text("退出只清除本机趣智会话、余额与账单。").font(.caption).foregroundStyle(CampusTheme.muted)
                Button("退出趣智账户", role: .destructive) { store.concealBathCode(); showLogout = true }
            }.padding(.top, 10)
        }.campusCard()
    }
    private var bathCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("洗澡码", systemImage: "key.fill").font(.headline)
                Spacer()
                if store.bathCode != nil { Button("收起") { store.concealBathCode() }.font(.caption) }
            }
            if let code = store.bathCode, scenePhase == .active {
                if code.enabled, let digits = code.code {
                    Text(digits).font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .tracking(3).frame(maxWidth: .infinity).privacySensitive().accessibilityLabel("当前洗澡码 " + digits.map(String.init).joined(separator: " "))
                    Text("已开启 · 在支持使用码的设备上输入").font(.caption).foregroundStyle(CampusTheme.muted)
                } else { Text("洗澡码尚未开启，请在趣智校园开启后刷新。").font(.caption).foregroundStyle(CampusTheme.muted) }
                Text("查询于 " + timestamp(code.queriedAt)).font(.caption2).foregroundStyle(CampusTheme.muted)
            } else { Text("查看当前账户的设备使用码").font(.caption).foregroundStyle(CampusTheme.muted) }
            Button(store.bathCode == nil ? "查看洗澡码" : "刷新洗澡码") { Task { _ = await store.revealBathCode() } }
                .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(store.busy || !store.valid || scenePhase != .active)
        }.campusCard()
    }
    private var billsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("消费账单").font(.headline)
                Spacer()
                Picker("月份", selection: $month) { ForEach(months, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.menu).disabled(store.busy || !store.valid)
                    .onChange(of: month) { value in Task { _ = await store.refresh(month: value) } }
            }
            if let issue = store.snapshot.issues["bills"] { notice("账单未更新：" + issue.localizedDescription) }
            if let cached = store.snapshot.billsMonth, cached != month {
                Text("\(month) 尚未取得，下方保留 \(cached) 的账单。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            if store.snapshot.billsUpdatedAt == nil {
                Text("尚未取得消费记录，点击右上角刷新。").font(.caption).foregroundStyle(CampusTheme.muted)
            } else if store.snapshot.bills.isEmpty {
                Text("\(store.snapshot.billsMonth ?? month) 暂无消费记录。").font(.caption).foregroundStyle(CampusTheme.muted)
            } else {
                ForEach(Array(store.snapshot.bills.enumerated()), id: \.offset) { _, bill in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(bill.description).font(.subheadline)
                            Text(bill.date.isEmpty ? "时间未提供" : bill.date).font(.caption2).foregroundStyle(CampusTheme.muted)
                        }
                        Spacer()
                        Text("¥" + QuzhiProtocol.money(bill.amount)).font(.subheadline).monospacedDigit()
                    }
                    Divider()
                }
            }
            if store.snapshot.billsTruncated { notice("仅展示平台返回的前 200 条，未显示完整月份。") }
            if let date = store.snapshot.billsUpdatedAt {
                Text("账单查询于 \(timestamp(date)) · 当前展示消费记录，不含充值流水")
                    .font(.caption2).foregroundStyle(CampusTheme.muted)
            }
        }.campusCard()
    }
    private var months: [String] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date(), year = calendar.component(.year, from: now)
        return (0..<max(1, (year - 2020) * 12 + calendar.component(.month, from: now)))
            .compactMap { calendar.date(byAdding: .month, value: -$0, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!) }
            .map { QuzhiProtocol.currentMonth($0) }
    }
    private func timestamp(_ date: Date?) -> String {
        guard let date else { return "尚未查询" }
        return CampusTheme.date(date, format: "MM-dd HH:mm")
    }
    private func notice(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(CampusTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct QuzhiLoginView: View {
    @ObservedObject var store: QuzhiStore
    let month: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var phone = ""
    @State private var secret = ""
    @State private var mode: QuzhiLoginMode = .password
    @State private var smsConsent = false
    @State private var completed = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("密码登录已有趣智校园账户。短信登录可能由平台创建新账户，请先阅读并确认提示。密码与验证码不保存。")
                        .font(.footnote).foregroundStyle(CampusTheme.muted)
                    TextField("趣智校园手机号", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .onChange(of: phone) { phone = String($0.prefix(11)) }.privacySensitive()
                    Picker("登录方式", selection: $mode) { ForEach(QuzhiLoginMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    SecureField(mode == .sms ? "短信验证码" : "趣智校园密码", text: $secret)
                        .textContentType(mode == .sms ? .oneTimeCode : .password)
                        .keyboardType(mode == .sms ? .numberPad : .default)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .onChange(of: secret) { secret = String($0.prefix(mode == .sms ? 8 : 128)) }
                    if mode == .sms {
                        Toggle("若手机号未注册，趣智平台可能创建账户。我确认使用短信方式。", isOn: $smsConsent).font(.footnote)
                        Button("发送验证码") { Task { _ = await store.sendSMS(phone: phone, consent: smsConsent) } }.disabled(!smsConsent)
                    }
                }.disabled(store.busy || scenePhase != .active)
                if !store.loginMessage.isEmpty { Text(store.loginMessage).font(.footnote) }
                if !store.error.isEmpty { Text(store.error).font(.footnote).foregroundStyle(.red) }
                Section {
                    Button {
                        let value = secret, number = phone, method = mode, consent = smsConsent; secret = ""
                        Task {
                            if await store.login(phone: number, secret: value, mode: method, consent: consent) {
                                completed = true
                                _ = await store.refresh(month: month)
                                phone = ""; dismiss()
                            }
                        }
                    } label: {
                        HStack { Text(store.busy ? "正在验证账户与余额…" : "登录"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(store.busy || phone.isEmpty || secret.isEmpty || (mode == .sms && !smsConsent) || scenePhase != .active)
                }
            }
            .navigationTitle("连接趣智校园").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { store.cancel(); secret = ""; phone = ""; dismiss() } } }
            .onChange(of: mode) { _ in secret = ""; smsConsent = false }
            .onChange(of: scenePhase) { phase in if phase != .active { secret = ""; store.cancel() } }
            .onDisappear { secret = ""; phone = ""; if !completed { store.cancel() } }
            .tint(CampusTheme.primary)
        }
    }
}
