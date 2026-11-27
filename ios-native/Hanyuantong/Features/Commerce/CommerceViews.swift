import SwiftUI
import CoreImage.CIFilterBuiltins

private struct CommerceSignInKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var commerceSignIn: () -> Void {
        get { self[CommerceSignInKey.self] }
        set { self[CommerceSignInKey.self] = newValue }
    }
}

struct CommerceDestination: Hashable, Identifiable {
    enum Kind: Hashable { case catalog, shop(String), report(String, String?, String) }
    let kind: Kind
    var id: Self { self }

    @ViewBuilder var content: some View {
        switch kind {
        case .catalog: CommerceCatalogView()
        case .shop(let shop): CommerceShopView(shopId: shop)
        case .report(let shop, let ad, let subject): CommerceReportView(shopId: shop, adId: ad, subject: subject)
        }
    }
}

struct HomeCommercePlacement: View {
    let onOpen: (CommerceDestination.Kind) -> Void
    @State private var placements: CommercePlacements?

    var body: some View {
        Group {
            if let placements, !placements.ads.isEmpty {
                CommerceAdDeck(ads: placements.ads, images: placements.media ?? [:], rotate: true, onOpen: onOpen)
            }
        }.task {
            placements = try? await CommerceAPI.shared.request("home")
        }
    }
}

private struct CommerceAdDeck: View {
    let ads: [CommerceAd]
    let images: [String: URL]
    let rotate: Bool
    let onOpen: (CommerceDestination.Kind) -> Void
    @State private var index = 0
    @State private var clock = Date()
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let live = ads.filter { $0.displayUntil > clock }
        Group {
            if !live.isEmpty {
                let shown = rotate ? [live[index % live.count]] : live
                VStack(spacing: 6) {
                    ForEach(shown) { ad in
                        HStack(spacing: 8) {
                            Button { onOpen(.shop(ad.shopId)) } label: {
                                HStack(spacing: 9) {
                                    CommercePhoto(url: images[ad.image], width: 64, height: 52)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("广告").font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(CampusTheme.border) }
                                        Text(ad.title).font(.subheadline.weight(.semibold))
                                        if !ad.subtitle.isEmpty { Text(ad.subtitle).font(.caption).foregroundStyle(CampusTheme.muted) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                            }.foregroundStyle(CampusTheme.text)
                            Button { onOpen(.report(ad.shopId, ad.id, ad.title)) } label: {
                                Image(systemName: "flag").frame(width: 44, height: 44)
                            }.accessibilityLabel("举报广告").foregroundStyle(CampusTheme.muted)
                        }
                        .padding(.leading, 10).padding(.vertical, 6)
                        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(CampusTheme.border).allowsHitTesting(false) }
                        .background {
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .global)
                                let inFrame = phase == .active && frame.height > 0 && frame.intersection(UIScreen.main.bounds).height >= frame.height / 2
                                Color.clear.onAppear { if inFrame { CommerceMetrics.shared.add("impression", ad.id) } }
                                    .onChange(of: inFrame) { if $0 { CommerceMetrics.shared.add("impression", ad.id) } }
                            }
                        }
                    }
                    if rotate && live.count > 1 {
                        HStack(spacing: 4) {
                            Spacer()
                            Button { index = (index + live.count - 1) % live.count } label: {
                                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            }.accessibilityLabel("上一张广告")
                            Text("\(index % live.count + 1) / \(live.count)").font(.caption.monospacedDigit()).foregroundStyle(CampusTheme.muted)
                            Button { index = (index + 1) % live.count } label: {
                                Image(systemName: "chevron.right").frame(width: 44, height: 44)
                            }.accessibilityLabel("下一张广告")
                        }
                    }
                }.buttonStyle(.plain)
            }
        }.onAppear { visible = true }.onDisappear { visible = false }
            .task(id: ads.map(\.endsAt)) {
                clock = Date()
                let deadlines = Set(ads.map(\.displayUntil)).filter { $0 > clock }.sorted()
                for date in deadlines {
                    let nanoseconds = UInt64(max(0, date.timeIntervalSinceNow) * 1_000_000_000) + 5_000_000
                    do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
                    clock = Date()
                }
            }
            .task(id: rotate && !reduceMotion && !voiceOver && visible && phase == .active && live.count > 1) {
                guard rotate && !reduceMotion && !voiceOver && visible && phase == .active && live.count > 1 else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 6_500_000_000) } catch { return }
                    index += 1
                }
            }
    }
}

private struct CommercePhoto: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        if let url {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(CampusTheme.border.opacity(0.4))
            }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
        }
    }
}

private struct CommerceFeedback: View {
    let text: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).foregroundStyle(CampusTheme.muted)
            if let retry { Button("重新加载", action: retry).buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CommerceCatalogView: View {
    @State private var categories: [CommerceCategory] = []
    @State private var items: [CommerceShop] = []
    @State private var ads: [CommerceAd] = []
    @State private var media: [String: URL] = [:]
    @State private var next: String?
    @State private var category = ""
    @State private var query = ""
    @State private var searched = ""
    @State private var error: String?
    @State private var busy = true
    @State private var destination: CommerceDestination?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack {
                    NavigationLink { CommerceFavoritesView() } label: { Label("收藏", systemImage: "heart") }
                    NavigationLink { CommerceWalletView() } label: { Label("我的优惠券", systemImage: "ticket") }
                }.buttonStyle(.bordered)
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button("全部") { category = "" }.tint(category.isEmpty ? CampusTheme.primary : CampusTheme.muted)
                            ForEach(categories) { option in
                                Button(option.name) { category = option.id }.tint(category == option.id ? CampusTheme.primary : CampusTheme.muted)
                            }
                        }.buttonStyle(.bordered).padding(2)
                    }
                }
                CommerceAdDeck(ads: ads, images: media, rotate: category.isEmpty) { destination = CommerceDestination(kind: $0) }
                if let error { CommerceFeedback(text: error) { Task { await load() } } }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                if items.isEmpty && !busy && error == nil { CommerceFeedback(text: searched.isEmpty ? "这个分类暂时没有门店" : "没有找到相关门店") }
                ForEach(items) { shop in
                    NavigationLink { CommerceShopView(shopId: shop.id) } label: { CommerceShopRow(shop: shop, media: media) }
                        .buttonStyle(.plain)
                }
                if next != nil { Button("加载更多") { Task { await load(append: true) } }.buttonStyle(.bordered).disabled(busy) }
            }.padding()
        }
        .background(CampusTheme.background).navigationTitle("校园周边").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索门店或地址")
        .onSubmit(of: .search) { searched = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)) }
        .onChange(of: query) { if $0.isEmpty { searched = "" } }
        .task(id: category + "|" + searched) { await load() }
        .refreshable { await load() }
        .sheet(item: $destination) { value in
            NavigationStack { value.content.toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { destination = nil } } } }
        }
    }
    @MainActor private func load(append: Bool = false) async {
        if append && busy { return }
        busy = true; error = nil
        if !append { items = []; ads = []; next = nil }
        var body: [String: Any] = ["category": category, "query": searched]
        if append, let next { body["next"] = next }
        defer { if !Task.isCancelled { busy = false } }
        do {
            let result: CommerceCatalog = try await CommerceAPI.shared.request("catalog", body)
            guard !Task.isCancelled else { return }
            items += result.items
            categories = result.categories
            next = result.next
            if !append { ads = result.ads }
            media = (append ? media : [:]).merging(result.media ?? [:]) { _, fresh in fresh }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct CommerceShopRow: View {
    let shop: CommerceShop
    let media: [String: URL]
    var body: some View {
        HStack(spacing: 10) {
            CommercePhoto(url: shop.images.first.flatMap { media[$0] }, width: 62, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(shop.name).font(.headline)
                Text(shop.address).font(.caption).foregroundStyle(CampusTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(CampusTheme.muted)
        }.foregroundStyle(CampusTheme.text)
            .padding(10).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CommerceShopView: View {
    let shopId: String
    @Environment(\.commerceSignIn) private var signIn
    @State private var detail: CommerceDetail?
    @State private var favorited = false
    @State private var error: String?
    @State private var errorCode = ""
    @State private var status: String?
    @State private var verification: CommerceProfile?
    @State private var claimedId: String?
    @State private var busy = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error { CommerceFeedback(text: error, retry: detail == nil ? { Task { await load() } } : nil) }
                if let status { CommerceFeedback(text: status) }
                if errorCode == "session_expired" {
                    Button("登录邯院通") { signIn() }.buttonStyle(.borderedProminent)
                }
                if errorCode == "student_verification_required", let verification {
                    Text("请向运营管理员出示学生证和此账号标识，核验后可领券。").foregroundStyle(CampusTheme.muted)
                    Text(verification.memberId).font(.caption.monospaced()).textSelection(.enabled)
                }
                if let detail {
                    if !detail.shop.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(detail.shop.images, id: \.self) { CommercePhoto(url: detail.media?[$0], width: 238, height: 143) } }
                        }
                    }
                    HStack {
                        Button { Task { await favorite() } } label: { Label(favorited ? "已收藏" : "收藏门店", systemImage: favorited ? "heart.fill" : "heart") }.disabled(busy)
                        NavigationLink { CommerceReportView(shopId: shopId, adId: nil, subject: detail.shop.name) } label: { Label("举报", systemImage: "flag") }
                    }.buttonStyle(.bordered)
                    Text(detail.shop.description)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(detail.shop.hours, systemImage: "clock")
                        if let url = detail.shop.phoneURL { Link(destination: url) { Label(detail.shop.phone, systemImage: "phone") } }
                        if let url = detail.shop.mapURL { Link(destination: url) { Label(detail.shop.address + " · 导航", systemImage: "mappin.and.ellipse") } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    Text("学生专属优惠").font(.headline)
                    if detail.offers.isEmpty { CommerceFeedback(text: "这家门店暂时没有优惠。") }
                    ForEach(detail.offers) { offer in
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(offer.title).font(.subheadline.weight(.semibold))
                                Text(offer.terms).font(.subheadline)
                                Text(CommerceAPI.label(offer.endsAt) + " 截止").font(.caption).foregroundStyle(CampusTheme.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(offer.soldOut ? "已领完" : "领取") { Task { await claim(offer.id) } }
                                .buttonStyle(.borderedProminent).disabled(busy || offer.soldOut)
                        }.padding(12).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let claimedId { NavigationLink("查看刚领取的优惠券") { CommerceCouponView(couponId: claimedId) }.buttonStyle(.bordered) }
                }
                if busy { ProgressView().frame(maxWidth: .infinity) }
            }.padding()
        }.background(CampusTheme.background).navigationTitle(detail?.shop.name ?? "门店详情").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @MainActor private func load() async {
        busy = true; error = nil; errorCode = ""
        defer { busy = false }
        do {
            detail = try await CommerceAPI.shared.request("shop", ["shopId": shopId])
            CommerceMetrics.shared.add("visit", shopId)
            let favorite: CommerceFavorite? = try? await CommerceAPI.shared.request("shop.status", ["shopId": shopId])
            favorited = favorite?.favorited ?? false
        } catch { show(error) }
    }
    @MainActor private func favorite() async {
        busy = true; error = nil; errorCode = ""; status = nil
        defer { busy = false }
        do {
            let _: CommerceEmpty = try await CommerceAPI.shared.request("favorite", ["shopId": shopId, "enabled": !favorited])
            favorited.toggle(); status = favorited ? "已收藏" : "已取消收藏"
        } catch { show(error) }
    }
    @MainActor private func claim(_ id: String) async {
        busy = true; error = nil; errorCode = ""; status = nil
        defer { busy = false }
        do {
            let result: CommerceClaim = try await CommerceAPI.shared.request("claim", ["id": id])
            claimedId = result.id; status = "优惠券已放入「我的优惠券」"
        } catch {
            show(error)
            if errorCode == "student_verification_required" { verification = try? await CommerceAPI.shared.request("access") }
        }
    }
    private func show(_ cause: Error) {
        error = cause.localizedDescription
        errorCode = (cause as? CommerceFailure)?.code ?? ""
    }
}

private struct CommerceFavoritesView: View {
    @Environment(\.commerceSignIn) private var signIn
    @State private var items: [CommerceShop] = []
    @State private var media: [String: URL] = [:]
    @State private var next: String?
    @State private var error: String?
    @State private var needsAccount = false
    @State private var busy = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let error { CommerceFeedback(text: error, retry: needsAccount ? nil : { Task { await load() } }) }
                if needsAccount { Button("登录邯院通") { signIn() }.buttonStyle(.borderedProminent) }
                if busy { ProgressView() }
                if !busy && error == nil && items.isEmpty { CommerceFeedback(text: "还没有收藏门店") }
                ForEach(items) { shop in NavigationLink { CommerceShopView(shopId: shop.id) } label: { CommerceShopRow(shop: shop, media: media) }.buttonStyle(.plain) }
                if next != nil { Button("加载更多") { Task { await load(append: true) } }.buttonStyle(.bordered).disabled(busy) }
            }.padding()
        }.background(CampusTheme.background).navigationTitle("收藏的门店").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load(append: Bool = false) async {
        busy = true; error = nil; needsAccount = false
        defer { busy = false }
        do {
            let result: CommercePage<CommerceShop> = try await CommerceAPI.shared.request("favorites", append ? ["next": next ?? ""] : [:])
            items = (append ? items : []) + result.items
            media.merge(result.media ?? [:]) { _, fresh in fresh }; next = result.next
        } catch { self.error = error.localizedDescription; needsAccount = (error as? CommerceFailure)?.code == "session_expired" }
    }
}

private struct CommerceWalletView: View {
    @Environment(\.commerceSignIn) private var signIn
    @State private var items: [CommerceCoupon] = []
    @State private var next: String?
    @State private var error: String?
    @State private var needsAccount = false
    @State private var busy = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let error { CommerceFeedback(text: error, retry: needsAccount ? nil : { Task { await load() } }) }
                if needsAccount { Button("登录邯院通") { signIn() }.buttonStyle(.borderedProminent) }
                if busy { ProgressView() }
                if !busy && error == nil && items.isEmpty { CommerceFeedback(text: "还没有领取优惠券") }
                ForEach(items) { item in
                    NavigationLink { CommerceCouponView(couponId: item.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(item.title).font(.headline); Text(item.shopName).font(.caption) }
                            Spacer()
                            Text(item.stateLabel).font(.caption.weight(.semibold)).foregroundStyle(CampusTheme.primary)
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(CampusTheme.text).padding(12).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if next != nil { Button("加载更多") { Task { await load(append: true) } }.buttonStyle(.bordered).disabled(busy) }
            }.padding()
        }.background(CampusTheme.background).navigationTitle("我的优惠券").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load(append: Bool = false) async {
        busy = true; error = nil; needsAccount = false
        defer { busy = false }
        do {
            let result: CommercePage<CommerceCoupon> = try await CommerceAPI.shared.request("wallet", append ? ["next": next ?? ""] : [:])
            items = (append ? items : []) + result.items; next = result.next
        } catch { self.error = error.localizedDescription; needsAccount = (error as? CommerceFailure)?.code == "session_expired" }
    }
}

private struct CommerceCouponView: View {
    let couponId: String
    @State private var coupon: CommerceCoupon?
    @State private var error: String?
    @State private var busy = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if busy { ProgressView() }
                if let error { CommerceFeedback(text: error) { Task { await load() } } }
                if let coupon {
                    Text(coupon.title).font(.title2.weight(.semibold)); Text(coupon.shopName); Text(coupon.terms)
                    Text("领取于 " + CommerceAPI.label(coupon.claimedAt) + " · " + CommerceAPI.label(coupon.endsAt) + " 截止")
                        .font(.caption).foregroundStyle(CampusTheme.muted)
                    if let code = coupon.code {
                        if let qr = Self.qr(code) {
                            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 184, height: 184)
                                .padding(12).background(.white).accessibilityLabel("到店核销二维码")
                        }
                        Text(code.enumerated().map { $0.offset > 0 && $0.offset % 4 == 0 ? " " + String($0.element) : String($0.element) }.joined()).font(.title3.monospacedDigit().weight(.bold)).textSelection(.enabled)
                        Text("到店出示给店员，优惠券仅可使用一次").font(.caption).foregroundStyle(CampusTheme.muted)
                    } else {
                        Text(coupon.stateLabel + (coupon.usedAt.map { " · " + CommerceAPI.label($0) } ?? "")).font(.headline)
                    }
                }
            }.padding().frame(maxWidth: .infinity)
        }.background(CampusTheme.background).navigationTitle("优惠券详情").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let result: CommerceCouponDetail = try await CommerceAPI.shared.request("coupon", ["id": couponId])
            coupon = result.coupon
        } catch { self.error = error.localizedDescription }
    }
    private static func qr(_ code: String) -> UIImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(("HYT1:" + code).utf8)
        generator.correctionLevel = "M"
        guard let image = generator.outputImage?.transformed(by: .init(scaleX: 8, y: 8)),
              let pixels = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: pixels)
    }
}

private struct CommerceReportView: View {
    let shopId: String
    let adId: String?
    let subject: String
    @State private var reason = ""
    @State private var status: String?
    @State private var sent = false
    @State private var busy = false

    var body: some View {
        Form {
            if adId != nil { Section("展示依据") { Text("这张广告按所在页面和门店分类投放。") } }
            Section(subject) {
                if !sent {
                    TextEditor(text: $reason).frame(minHeight: 95).accessibilityLabel("举报原因")
                    Text("请说明遇到的问题，避免填写个人信息").font(.caption).foregroundStyle(CampusTheme.muted)
                    Button("提交举报") { Task { await submit() } }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || reason.count > 500)
                }
                if let status { Text(status) }
            }
        }.navigationTitle(adId == nil ? "举报门店" : "举报广告").navigationBarTitleDisplayMode(.inline)
    }
    @MainActor private func submit() async {
        busy = true
        defer { busy = false }
        var body = ["shopId": shopId, "reason": reason]
        if let adId { body["id"] = adId }
        do {
            let _: CommerceEmpty = try await CommerceAPI.shared.request("report", body)
            status = "举报已提交"; sent = true
        } catch { status = error.localizedDescription }
    }
}
