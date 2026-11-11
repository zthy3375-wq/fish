import SwiftUI
import UIKit

@MainActor
struct PangguaiWalletView: View {
    @StateObject private var store: PangguaiStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var loginPresented = false
    @State private var scannerPresented = false
    @State private var tab = 0
    @State private var selection = ""
    @State private var method = "2"
    @State private var confirmation: PGConfirmation?
    @State private var awaitingOfficial = false
    @State private var pollFailures = 0
    init() { _store = StateObject(wrappedValue: PangguaiStore()) }
    init(store: PangguaiStore) { _store = StateObject(wrappedValue: store) }
    private var valid: Bool { store.connected && !store.expired }
    private var blocked: Bool { store.busy || !valid }
    private var waterMerchant: PGTicket? { PangguaiWalletMath.waterTicket(store.snapshot.tickets) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("洗衣 · 饮水").font(.caption).foregroundStyle(CampusTheme.primary)
                    Text("胖乖生活").font(.largeTitle.bold())
                    Text("余额、设备和消费记录，一处查看").font(.subheadline).foregroundStyle(CampusTheme.muted)
                }
                if let message = store.message { notice(message) }
                if store.connected { connectedContent }
                else {
                    VStack(spacing: 14) {
                        Image(systemName: "wallet.pass").font(.largeTitle).foregroundStyle(CampusTheme.primary)
                        Text("连接你的胖乖钱包").font(.headline)
                        Text("短信登录后，余额直接显示在这里。").font(.subheadline).foregroundStyle(CampusTheme.muted)
                        Button("连接胖乖生活") { loginPresented = true }.buttonStyle(.borderedProminent).disabled(store.busy)
                    }.frame(maxWidth: .infinity).campusCard()
                }
                Button { confirmation = .official(nil) } label: { Label("打开支付宝胖乖生活", systemImage: "arrow.up.right.square") }.buttonStyle(.bordered)
                Text("充值、支付宝付款、签约和蓝牙设备请在官方端完成。打开或返回官方端不代表支付成功。").font(.caption).foregroundStyle(CampusTheme.muted)
            }.padding(16)
        }.background(CampusTheme.background).navigationTitle("胖乖生活").navigationBarTitleDisplayMode(.inline).tint(CampusTheme.primary)
            .sheet(isPresented: $loginPresented) { PangguaiLoginView(store: store) }
            .sheet(isPresented: $scannerPresented) { PangguaiScannerView { code in Task { await store.readDevice(code) } } }
            .alert(item: $confirmation) { item in alert(item) }
            .onChange(of: store.device?.id) { _ in selection = "" }
            .onChange(of: store.maskedPhone) { _ in selection = ""; confirmation = nil }
            .onChange(of: scenePhase) { phase in
                if phase == .active && awaitingOfficial {
                    awaitingOfficial = false; store.message = "已返回，请核对官方订单和余额，返回不代表支付成功。"
                    if valid { Task { await store.refresh() } }
                }
            }
            .task {
                if valid { await store.refresh() }
                // Foreground-only read-only polling with bounded retries, never a payment trigger.
                var ticks = 0
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
                    ticks += 1
                    guard scenePhase == .active, valid, !store.busy, pollFailures < 3 else { continue }
                    let water = store.snapshot.water
                    let activeWater = ["starting", "using", "ending"].contains(water?.phase ?? "") && water?.orderNo != nil && water?.error != .waterOwnership && confirmation == nil
                    let activeLaundry = store.snapshot.laundry?.terminal == false && ticks % 5 == 0
                    guard activeWater || activeLaundry else { continue }
                    await store.pollSessions()
                    let failed = store.message != nil || (activeWater && store.snapshot.water?.error != nil) || (activeLaundry && store.snapshot.laundry?.error != nil)
                    pollFailures = failed ? pollFailures + 1 : 0
                }
            }
            .onDisappear { store.cancelPending() }
    }
    @ViewBuilder private var connectedContent: some View {
        HStack {
            Text(store.maskedPhone).font(.subheadline).privacySensitive()
            Spacer()
            Button { Task { await store.refresh() } } label: { if store.busy { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(blocked).accessibilityLabel("刷新胖乖余额与记录")
        }
        if store.expired {
            notice("登录已失效，下方保留上次结果。")
            Button("重新连接") { loginPresented = true }.buttonStyle(.borderedProminent)
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("直饮水余额").font(.subheadline).foregroundStyle(CampusTheme.muted)
            Text(PangguaiWalletMath.waterAmount(waterMerchant?.balance).map { "¥" + $0 } ?? "暂未获取").font(.system(size: 38, weight: .semibold)).privacySensitive()
            Text("查询于 " + updated(store.snapshot.ticketsUpdatedAt)).font(.caption).foregroundStyle(CampusTheme.muted)
            Button { scannerPresented = true } label: { Label("扫码识别设备", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(blocked)
        }.campusCard()
        if store.snapshot.issues["tickets"] != nil { notice("直饮水余额未更新，保留上次结果。") }
        if let water = store.snapshot.water { waterSession(water) }
        if let laundry = store.snapshot.laundry { laundrySession(laundry) }
        if let q = store.waterQuote { waterReview(q) }
        else if let q = store.laundryQuote { laundryReview(q) }
        else if let d = store.device { deviceCard(d) }
        if let q = store.settlementQuote { settlementReview(q) }
        Picker("胖乖钱包内容", selection: $tab) { Text("商户钱包").tag(0); Text("最近消费").tag(1) }.pickerStyle(.segmented)
        if tab == 0 { merchantList } else { orderList }
        DisclosureGroup("账户与帮助") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("通用钱包余额", value: "¥" + PangguaiProtocol.amount(store.snapshot.balance)).privacySensitive()
                Text("商户钱包各自独立，不合并金额。退出不会停止设备或撤销扣款；未完成操作的加密防重记录会保留，重新连接相同账户后核对。").font(.caption).foregroundStyle(CampusTheme.muted)
                Button("退出胖乖账户", role: .destructive) { confirmation = .logout }.disabled(store.busy)
            }.padding(.top, 10)
        }.campusCard()
    }
    @ViewBuilder private var merchantList: some View {
        if store.snapshot.tickets.isEmpty { Text(store.snapshot.ticketsUpdatedAt == nil ? "商户钱包尚未取得，请刷新。":"尚未找到商户钱包，请在官方端核对。").font(.subheadline).foregroundStyle(CampusTheme.muted) }
        ForEach(store.snapshot.tickets) { ticket in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(ticket.name).font(.headline)
                    if ticket.id == waterMerchant?.id { Text("为直饮水账户充值").font(.caption).foregroundStyle(CampusTheme.muted) }
                    else {
                        Text(PangguaiProtocol.amount(ticket.balance) + " 点").font(.title2).privacySensitive()
                        Text("本金 \(PangguaiProtocol.amount(ticket.principal)) · 赠送 \(PangguaiProtocol.amount(ticket.gift))").font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                }
                Spacer()
                Button("充值 ↗") { confirmation = .official(ticket.id) }.buttonStyle(.bordered).disabled(blocked)
            }.campusCard()
        }
    }
    @ViewBuilder private var orderList: some View {
        if store.snapshot.issues["orders"] != nil { notice("消费记录未更新，保留上次结果。") }
        if store.snapshot.orders.isEmpty { Text(store.snapshot.ordersUpdatedAt == nil ? "消费记录尚未取得":"暂无消费记录").foregroundStyle(CampusTheme.muted) }
        ForEach(store.snapshot.orders) { order in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) { Text(order.name.isEmpty ? "胖乖消费":order.name).font(.headline); Text(order.time + " · " + order.status).font(.caption).foregroundStyle(CampusTheme.muted) }
                Spacer(); Text("¥" + PangguaiProtocol.amount(order.amount)).font(.headline).privacySensitive()
            }.campusCard()
        }
        Text("最近 20 条 · 金额为现金实付 · " + updated(store.snapshot.ordersUpdatedAt)).font(.caption).foregroundStyle(CampusTheme.muted)
    }
    private func deviceCard(_ d: PGDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(d.name).font(.headline); Spacer(); Button("收起") { store.dismissDevice() }.disabled(store.busy) }
            Text(d.operatorName).font(.caption).foregroundStyle(CampusTheme.muted)
            if !d.issue.isEmpty { notice(d.issue) }
            ForEach(d.skus) { sku in
                Button { selection = sku.id } label: {
                    HStack(alignment: .top) {
                        Image(systemName: selection == sku.id ? "largecircle.fill.circle":"circle")
                        VStack(alignment: .leading, spacing: 5) { Text(sku.name); Text(sku.feature).font(.caption).foregroundStyle(CampusTheme.muted) }
                        Spacer(); Text(sku.price.map { "¥" + PangguaiProtocol.amount($0) } ?? "价格待查询").font(.subheadline)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }.buttonStyle(.plain).disabled(blocked || !sku.available)
            }
            if ["00", "04"].contains(d.category), d.isBluetooth == "0" {
                Button(d.category == "04" ? "核对接水费用":"查看洗衣费用") { Task { if d.category == "04" { await store.prepareWater(skuID: selection) } else { await store.quoteLaundry(skuID: selection) } } }.buttonStyle(.borderedProminent).disabled(blocked || selection.isEmpty)
                Text(d.category == "04" ? "请核对热水／常温水出水口，并先放好杯子。":"请放好衣物、关紧机门，费用以确认页为准。").font(.caption).foregroundStyle(CampusTheme.muted)
            } else { notice("此类设备仅支持识别，请按机身和官方端提示使用。") }
        }.campusCard()
    }
    private func laundryReview(_ q: PGLaundryQuote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("确认洗衣费用").font(.headline); Spacer(); Button("取消") { store.laundryQuote = nil }.disabled(store.busy) }
            Text(q.deviceName + " · " + q.program)
            Text("¥" + PangguaiProtocol.amount(q.amount)).font(.largeTitle.bold())
            Text("胖乖账户 " + store.maskedPhone + " · 一次性付款，不使用广告优惠").font(.caption)
            ForEach(q.channels) { channel in
                Button { method = channel.id } label: {
                    VStack(alignment: .leading, spacing: 4) { Label(channel.name, systemImage: method == channel.id ? "largecircle.fill.circle":"circle"); if !channel.available { Text(channel.reason.isEmpty ? "当前不可用或需开通":channel.reason).font(.caption) } }
                }.disabled(!channel.available || blocked).buttonStyle(.plain)
            }
            Text("确认后将创建或支付这台设备的当前订单。付款和启动分别查询；退款、取消以平台规则及返回结果为准。").font(.caption).foregroundStyle(CampusTheme.muted)
            Button("确认支付 ¥\(PangguaiProtocol.amount(q.amount)) 并洗衣") { Task { await store.startLaundry(confirmedQuoteID: q.id, method: method) } }.buttonStyle(.borderedProminent).disabled(blocked || q.expiresAt < Date() || !q.channels.contains(where: { $0.id == method && $0.available }))
            if q.expiresAt < Date() { notice(PGFailure.quoteExpired.message) }
        }.campusCard()
    }
    private func waterReview(_ q: PGWaterQuote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("确认接水与扣费方式").font(.headline); Spacer(); Button("取消") { store.waterQuote = nil }.disabled(store.busy) }
            Text(q.deviceName + " · " + q.outlet).font(.headline)
            Text(q.feature)
            Text("平台标价 \(PangguaiProtocol.amount(q.price))，不是本次总价；计费单位以设备说明为准。").font(.caption)
            Text("扣费方式：" + q.paymentName)
            Text("胖乖账户 \(store.maskedPhone)。确认后启动本次用水，结束后按实际使用量计费。已开通的免密付款以官方签约为准；本次不使用广告优惠。").font(.subheadline)
            notice(q.remoteEnd ? "支持在此结束接水；若设备未停止，请立即按机身「结算」。":"接完请按机身「结算」，应用会查询状态和账单。")
            if !q.canStart { notice(q.reason) }
            Button("确认开始接水") { Task { await store.startWater(confirmedQuoteID: q.id) } }.buttonStyle(.borderedProminent).disabled(blocked || !q.canStart || q.expiresAt < Date())
            if q.expiresAt < Date() { notice(PGFailure.quoteExpired.message) }
        }.campusCard()
    }
    private func laundrySession(_ s: PGLaundrySession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(s.deviceName + " · " + s.program).font(.caption); Spacer(); queryButton }
            Text(s.title).font(.title3.bold())
            Text("应付 ¥" + PangguaiProtocol.amount(s.amount))
            if s.phase == "running", let end = s.expectedEnd { Text("预计完成 " + updated(end) + "，以设备状态为准。").font(.caption) }
            if s.phase == "completed" { Text("洗衣已完成，记得取衣。").font(.subheadline) }
            if s.phase == "paid" { notice("付款已确认，尚未收到设备启动确认，请看机身提示。") }
            if s.phase == "creating" || s.phase == "checking" { notice("结果尚未确定，请核对原订单。不会重复下单或付款。") }
            if let error = s.error { notice(error.message) }
            if s.phase == "pending", !s.paySent, !s.cancelSent { Button("核对并付款") { Task { await store.quoteLaundry() } }.buttonStyle(.bordered).disabled(blocked) }
            if ["pending", "checking"].contains(s.phase) { Button("取消订单", role: .destructive) { confirmation = .cancelLaundry(s.id) }.disabled(blocked) }
            if let number = s.orderNo { Text("订单 " + number).font(.caption).textSelection(.enabled) }
            Text("查询于 " + updated(s.updatedAt)).font(.caption).foregroundStyle(CampusTheme.muted)
        }.campusCard()
    }
    private func waterSession(_ s: PGWaterSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(s.deviceName + " · " + s.outlet).font(.caption); Spacer(); queryButton }
            Text(s.title).font(.title3.bold())
            if s.phase == "settled" { Text("本次实付 ¥" + PangguaiProtocol.amount(s.amount)).font(.title2) }
            if ["using", "ending"].contains(s.phase) {
                if s.remoteEnd && !s.endSent { Button("结束接水") { confirmation = .endWater(s.id) }.buttonStyle(.borderedProminent).disabled(blocked) }
                notice(s.endSent ? "已请求结束，尚待设备确认；仍在出水请立即按机身「结算」。":"接完请按机身「结算」。暂停请使用机身按钮。")
            }
            if s.phase == "starting" { notice("尚未确认启动，不要重复扫码开水。请查看机身状态。") }
            if let error = s.error { notice(error.message) }
            if s.phase == "closed_unknown" { Text("旧记录已移出，未确认账单仍需在最近消费或官方端核对。").font(.caption) }
            if s.endBasis == "session_closed" { notice("平台不再返回本次会话。若仍在出水，请立即按机身「结算」。") }
            if ["ended", "settling"].contains(s.phase), !s.settleSent { Button("生成并核对结算账单") { Task { await store.prepareWaterSettlement(sessionID: s.id) } }.buttonStyle(.bordered).disabled(blocked) }
            if !s.terminal { Button("已在机身结算，恢复扫码") { confirmation = .physicalWater(s.id) }.disabled(blocked) }
            if let number = s.orderNo { Text("订单 " + number).font(.caption).textSelection(.enabled) }
            Text(s.paymentName + " · 查询于 " + updated(s.updatedAt)).font(.caption).foregroundStyle(CampusTheme.muted)
        }.campusCard()
    }
    private func settlementReview(_ q: PGWaterSettlement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("确认本次用水结算").font(.headline)
            Text(q.deviceName + " · 账户 " + store.maskedPhone)
            Text("¥" + PangguaiProtocol.amount(q.amount)).font(.largeTitle.bold())
            Text("付款方式：" + q.paymentName + "。本次一次性结算，不会再次开水。")
            Button("确认结算 ¥" + PangguaiProtocol.amount(q.amount)) { Task { await store.settleWater(confirmedQuoteID: q.id) } }.buttonStyle(.borderedProminent).disabled(blocked || q.expiresAt < Date())
            Button("取消") { store.settlementQuote = nil }.disabled(store.busy)
        }.campusCard()
    }
    private var queryButton: some View { Button("查询状态") { pollFailures = 0; Task { await store.pollSessions() } }.font(.subheadline).disabled(blocked) }
    private func notice(_ text: String) -> some View { Text(text).font(.subheadline).foregroundStyle(CampusTheme.text).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 12)).accessibilityAddTraits(.isStaticText) }
    private func updated(_ date: Date?) -> String { date.map { CampusTheme.date($0, format:"MM-dd HH:mm") } ?? "尚未更新" }
    private func alert(_ action: PGConfirmation) -> Alert {
        switch action {
        case .logout:
            return Alert(title: Text("退出胖乖账户？"), message: Text("退出不会停止设备或撤销扣款。正在用水时请先按机身结算；未完成操作的加密防重记录会保留。"), primaryButton: .destructive(Text("确认退出")) { store.logout() }, secondaryButton: .cancel())
        case .official(let merchant):
            let name = store.snapshot.tickets.first(where: { $0.id == merchant })?.name ?? "胖乖生活"
            return Alert(title: Text("打开官方 \(name)？"), message: Text("\(store.maskedPhone.isEmpty ? "":("当前账户 " + store.maskedPhone + "。"))将打开支付宝胖乖小程序，请核对官方登录账户、商户和金额后自行确认。此操作不会提交付款。"), primaryButton: .default(Text("打开官方端")) { launchOfficial(merchant: merchant) }, secondaryButton: .cancel())
        case .cancelLaundry(let id): return Alert(title: Text("取消这笔未完成付款的订单？"), message: Text("将重新核对原订单；是否取消成功以平台返回为准。"), primaryButton: .destructive(Text("确认取消订单")) { Task { await store.cancelLaundry(confirmedSessionID: id) } }, secondaryButton: .cancel(Text("保留订单")))
        case .endWater(let id): return Alert(title: Text("结束本次接水？"), message: Text("将对当前设备发送一次结束命令，请确认杯子和机身状态。未停止时立即按机身「结算」。"), primaryButton: .default(Text("确认结束")) { Task { await store.endWater(confirmedSessionID: id) } }, secondaryButton: .cancel())
        case .physicalWater(let id): return Alert(title: Text("已在机身结算并停止出水？"), message: Text("先确认机身已经停止。接下来仅核对设备记录，不发送结束或付款命令；账单仍需核对。"), primaryButton: .default(Text("确认已停止，核对设备")) { Task { await store.confirmPhysicalWaterEnd(sessionID: id) } }, secondaryButton: .cancel())
        }
    }
    private func launchOfficial(merchant: String?) {
        do {
            let url = try store.officialURL(merchantID: merchant)
            openURL(url) { accepted in
                awaitingOfficial = accepted
                store.message = accepted ? "已请求打开官方小程序，请在官方端核对账户和订单。":"未能打开支付宝，请手动进入胖乖生活官方 App 或支付宝胖乖生活小程序。"
            }
        } catch { store.message = PGFailure.mapped(error).message }
    }
}

private enum PGConfirmation: Identifiable, Equatable {
    case logout, official(String?), cancelLaundry(UUID), endWater(UUID), physicalWater(UUID)
    var id: String {
        switch self { case .logout:return "logout"; case .official(let id):return "official-" + (id ?? "home"); case .cancelLaundry(let id):return "cancel-\(id)"; case .endWater(let id):return "end-\(id)"; case .physicalWater(let id):return "physical-\(id)" }
    }
}

enum PangguaiWalletMath {
    static func waterTicket(_ tickets: [PGTicket]) -> PGTicket? {
        let matches = tickets.filter { $0.name.filter { !$0.isWhitespace } == "邯郸学院直饮水机" }
        return matches.count == 1 ? matches[0]:nil
    }
    /// Only this verified merchant uses minor units; unrelated merchant points must never be converted.
    static func waterAmount(_ amount: String?) -> String? {
        guard let amount, let value = PangguaiProtocol.money(.string(amount)), let n = Decimal(string: value) else { return nil }
        let f = NumberFormatter(); f.locale = Locale(identifier: "zh_CN"); f.minimumFractionDigits = 2; f.maximumFractionDigits = 2; f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: n / 100))
    }
}

@MainActor
private struct PangguaiLoginView: View {
    @ObservedObject var store: PangguaiStore
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var consent = false
    var body: some View {
        NavigationStack {
            Form {
                Section("连接胖乖生活") {
                    TextField("胖乖手机号", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).privacySensitive()
                    TextField("短信验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).privacySensitive()
                    Toggle("同意胖乖用户协议与隐私政策", isOn: $consent)
                    Text("未注册手机号可能由平台创建账户。验证码仅发往胖乖官方服务，本机不保存短信验证码。").font(.caption).foregroundStyle(CampusTheme.muted)
                    Link("查看用户协议", destination: URL(string:"https://h5.qiekj.com/user/UserAgreement/UserAgreement")!)
                    Link("查看隐私政策", destination: URL(string:"https://h5.qiekj.com/user/privacyPolicy/privacyPolicy")!)
                }.disabled(store.busy)
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(ceil((store.smsRetryAt ?? .distantPast).timeIntervalSince(context.date))))
                        Button(remaining > 0 ? "\(remaining) 秒后可重发":"获取验证码") { Task { _ = await store.sendCode(phone: phone, consent: consent) } }.disabled(store.busy || !consent || remaining > 0)
                    }
                    Button { Task { if await store.login(phone: phone, code: code, consent: consent) { phone = ""; code = ""; dismiss() } } } label: { HStack { Text("登录"); if store.busy { Spacer(); ProgressView() } } }.disabled(store.busy || !consent)
                }
                if let message = store.message { Section { Text(message).font(.subheadline) } }
                Section { Text("登录遇到验证或风控，请取消后在支付宝胖乖小程序处理。不会自动重发验证码或绕过验证。").font(.caption).foregroundStyle(CampusTheme.muted) }
            }.navigationTitle("连接胖乖生活").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { store.cancelPending(); phone = ""; code = ""; dismiss() } } }
                .onChange(of: phone) { phone = String($0.prefix(11)) }
                .onChange(of: code) { code = String($0.prefix(8)) }
                .onDisappear { store.cancelPending(); phone = ""; code = "" }
        }
    }
}
