import SwiftUI

struct CampusWornBadge: Codable, Equatable, Identifiable {
    let id: String
    let code: String
    let name: String
    let rarity: String
    let title: String?
}

struct CampusHonorItem: Codable, Identifiable, Equatable {
    let id: String, code: String, name: String, category: String, rarity: String
    let year: Int?
    let archived: Bool
    let criteria: String?
    let awardId: String?
    let at: String?
    let story: String?
    let publicHidden: Bool
    let memberId: String?
    let nickname: String?
    var displayKind: String? = nil
    private var definitionCode: String {
        code.replacingOccurrences(of: "-[0-9]{4}$", with: "", options: .regularExpression)
    }
    private static let retired: Set<String> = ["bug-hunter", "architect", "first-feature", "gold-creator", "developer-noticed", "welcome-guide", "graduation-keepsake"]
    private static let achievements: Set<String> = ["first-hundred", "campus-observer", "good-company", "answer-guide", "campus-photographer", "community-classic", "landmark-post", "hundred-likes", "full-page", "archivist", "before-dawn", "world-lines", "crossed-paths", "no-island"]
    var retiredAchievement: Bool { Self.retired.contains(definitionCode) }
    var appearsInAchievementHall: Bool {
        let isAchievement = displayKind.map { $0 == "achievement" } ?? (category == "hidden" || retiredAchievement || Self.achievements.contains(definitionCode))
        return isAchievement && (awardId != nil || (category != "hidden" && !retiredAchievement))
    }
    var archiveId: String { awardId ?? id }
    var earned: Bool { awardId != nil || memberId != nil }
    var caption: String { year.map { String($0) + " · " + name } ?? name }
}

struct CampusCollectionProfile: Codable {
    let id: String, nickname: String
    var items: [CampusHonorItem]
    let badges: MemberBadges
    let identities: [String]
    let customTitle: String?
    let useTitle: Bool
    let total: Int
    let rarities: [String: Int]
    let unseen: [String]
    let layoutVersion: Int?
    let showcase: [String]?
    let baseAwards: [String: String]?
    var legacyCount: Int {
        if let code = badges.official?.code { return Set(identities + [code]).count }
        return identities.count
    }
}

struct CampusIdentityUpdate: Codable {
    let id: String
    let badges: MemberBadges
    let showcase: [String]?
    let collectionShowcase: [CampusHonorItem]?
}

struct CampusHonorRoute: Identifiable {
    let id = UUID()
    let memberId: String?
}

private let campusIdentityNames = ["developer":"开发者","moderator":"管理员","seed":"种子用户","creator":"优质创作者","contributor":"社区贡献者"]
struct CampusHonorOption: Identifiable {
    let id: String, label: String
    init(_ id: String, _ label: String) { self.id = id; self.label = label }
}
let campusHonorCategories: [CampusHonorOption] = [.init("identity","身份"),.init("contribution","贡献"),.init("legend","传奇"),.init("limited","限定"),.init("hidden","隐藏")]
let campusHonorRarities: [CampusHonorOption] = [.init("common","普通"),.init("fine","精良"),.init("rare","稀有"),.init("epic","史诗"),.init("legendary","传说")]

struct CampusHonorByline: View {
    var badges: MemberBadges?
    var body: some View {
        HStack(spacing: 5) {
            if let role = badges?.official, ["developer", "moderator"].contains(role.code), let name = campusIdentityNames[role.code] {
                Label(name, systemImage: role.code == "developer" ? "crown" : "shield")
                    .foregroundStyle(role.code == "developer" ? Color.orange : .blue)
            }
            if let badge = badges?.collection {
                Label(badge.title ?? badge.name, systemImage: badge.rarity == "legendary" ? "sparkles" : "seal")
                    .lineLimit(1).frame(maxWidth: 75, alignment: .leading)
                    .foregroundStyle(badge.rarity == "legendary" || badge.rarity == "epic" ? Color.orange : .purple)
                    .accessibilityLabel(badge.name)
            } else if let worn = badges?.worn, let name = campusIdentityNames[worn.code] {
                let style = HonorByline.style(worn.code)
                Label(style.0, systemImage: style.1).foregroundStyle(style.2).lineLimit(1).accessibilityLabel(name)
            }
        }.font(.system(size: 11, weight: .semibold))
    }
}

private struct CampusMedalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(0.5,0),(0.94,0.18),(0.94,0.68),(0.75,0.88),(0.5,1),(0.25,0.88),(0.06,0.68),(0.06,0.18)]
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: rect.minX + rect.width * point.0, y: rect.minY + rect.height * point.1)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        return path
    }
}

private struct CommunityMedallion: View {
    let item: CampusHonorItem
    var size: CGFloat = 58
    private var tint: Color {
        switch item.rarity {
        case "fine": return Color(red: 0.37, green: 0.56, blue: 0.70)
        case "rare": return Color(red: 0.52, green: 0.39, blue: 0.70)
        case "epic": return Color(red: 0.71, green: 0.51, blue: 0.23)
        case "legendary": return Color(red: 0.71, green: 0.40, blue: 0.24)
        default: return .gray
        }
    }
    private var symbol: String { ["identity":"building.columns","contribution":"leaf","legend":"crown","limited":"seal","hidden":"sparkles"][item.category] ?? "seal" }
    var body: some View {
        let gradient = LinearGradient(colors: [tint, tint.opacity(0.35), tint], startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            CampusMedalShape().fill(gradient)
            CampusMedalShape().fill(tint.opacity(0.17)).padding(4)
            Image(systemName: item.earned ? symbol : "lock")
                .font(.system(size: size * 0.39, weight: .medium)).foregroundStyle(.primary)
        }.frame(width: size, height: size * 1.1)
            .saturation(item.earned ? 1 : 0.1).opacity(item.earned ? 1 : 0.62)
            .accessibilityHidden(true)
    }
}

struct CampusHonorCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var tree: TreeholeStore
    let route: CampusHonorRoute
    @State private var memberId: String?
    @State private var profile: CampusCollectionProfile?
    @State private var items: [CampusHonorItem] = []
    @State private var section = "legend"
    @State private var category = "all"
    @State private var years: [Int] = []
    @State private var year: Int?
    @State private var selected: CampusHonorItem?
    @State private var unlocked: String?
    @State private var rendered: Set<String> = []
    @State private var useTitle = false
    @State private var reveal = false
    @State private var more = false
    @State private var loading = false
    @State private var error: String?
    @State private var revision = 0

    init(tree: TreeholeStore, route: CampusHonorRoute) {
        self.tree = tree; self.route = route; _memberId = State(initialValue: route.memberId)
    }
    private var isArchive: Bool { memberId == nil }
    private var isOwn: Bool { memberId != nil && memberId == tree.user?.id }
    private var filterKey: String { (memberId ?? "archive") + section + String(year ?? 0) }
    private var shown: [CampusHonorItem] { isArchive || category == "all" ? items : items.filter { $0.category == category } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    header
                    if isArchive { archiveFilters } else { collectionFilters }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red); Button("重试") { Task { await load() } } }
                    if loading { ProgressView("正在读取荣誉…") }
                    if shown.isEmpty && !loading && error == nil {
                        Text(category == "hidden" && !isArchive ? "隐藏荣誉会在获得后出现。" : "这里还没有可展示的荣誉。").font(.footnote).foregroundStyle(.secondary)
                    }
                    if isArchive { archiveRows } else { grid }
                    if more && !loading { Button("查看更多") { Task { await load(append: true) } }.frame(minHeight: 44) }
                }.padding(16)
            }
            .navigationTitle(isArchive ? "荣誉殿堂" : "荣誉收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                if !isArchive && route.memberId == nil {
                    ToolbarItem(placement: .navigationBarLeading) { Button("返回殿堂") { memberId = nil } }
                }
            }
            .sheet(item: $selected, onDismiss: finishUnlock) { item in detail(item) }
        }
        .task(id: filterKey) { await load() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isArchive ? "社区荣誉殿堂" : isOwn ? "我的荣誉收藏" : (profile?.nickname ?? "同学") + "的荣誉收藏").font(.title3.weight(.semibold))
            if isArchive { Text("收藏历届荣誉，阅读获奖者留下的校园故事。").font(.footnote).foregroundStyle(Color(red: 0.91, green: 0.82, blue: 0.73)) }
            if let profile, !isArchive {
                Text("已收藏 \(profile.total + profile.legacyCount) 枚").font(.footnote).foregroundStyle(.secondary)
                CampusHonorByline(badges: profile.badges)
                Text(profile.identities.filter { $0 != profile.badges.official?.code }.compactMap { campusIdentityNames[$0] }.joined(separator: " · ")).font(.footnote)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(isArchive ? 22 : 14)
         .foregroundStyle(isArchive ? Color(red: 1, green: 0.95, blue: 0.84) : .primary)
         .background {
             if isArchive {
                 RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [
                    Color(red: 0.17, green: 0.13, blue: 0.24), Color(red: 0.35, green: 0.23, blue: 0.34)
                 ], startPoint: .bottomLeading, endPoint: .topTrailing))
             } else { RoundedRectangle(cornerRadius: 14).fill(.thinMaterial) }
         }
    }
    private var archiveFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("荣誉档案", selection: $section) {
                Text("传奇人物").tag("legend"); Text("历届年度").tag("annual")
                Text("历史贡献").tag("contribution"); Text("绝版收藏").tag("retired")
            }.pickerStyle(.segmented).onChange(of: section) { _ in year = nil }
            if section == "annual" && !years.isEmpty {
                Picker("年份", selection: $year) {
                    Text("全部年份").tag(nil as Int?)
                    ForEach(years, id: \.self) { Text(String($0)).tag(Optional($0)) }
                }
            }
        }
    }
    private var collectionFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let profile {
                HStack { ForEach(campusHonorRarities) { pair in
                    VStack { Text(String((profile.rarities[pair.id] ?? 0) + (pair.id == "common" ? profile.legacyCount : 0))).fontWeight(.semibold); Text(pair.label).font(.caption2) }.frame(maxWidth: .infinity)
                } }
            }
            Picker("荣誉分类", selection: $category) {
                Text("全部").tag("all")
                ForEach(campusHonorCategories) { Text($0.label).tag($0.id) }
            }.pickerStyle(.menu)
        }
    }
    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(shown) { item in
                Button { show(item) } label: {
                    VStack(spacing: 5) {
                        CommunityMedallion(item: item)
                        Text(item.name).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                        Text(item.year.map { String($0) + " · " } ?? "").font(.caption2) +
                        Text(campusHonorRarities.first { $0.id == item.rarity }?.label ?? "").font(.caption2)
                    }.padding(8).frame(maxWidth: .infinity, minHeight: 118)
                     .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain)
            }
        }
    }
    private var archiveRows: some View {
        LazyVStack(spacing: 6) {
            ForEach(shown, id: \.archiveId) { item in
                Button { show(item) } label: {
                    HStack {
                        CommunityMedallion(item: item, size: 39)
                        VStack(alignment: .leading) { Text(item.nickname ?? "").font(.subheadline.weight(.semibold)); Text(item.caption).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }
    private func detail(_ item: CampusHonorItem) -> some View {
        ScrollView {
            VStack(spacing: 11) {
                CommunityMedallion(item: item, size: 91).scaleEffect(reveal ? 1 : 0.77).opacity(reveal ? 1 : 0.2)
                if unlocked == item.awardId && item.awardId != nil { Text("新荣誉已获得").font(.subheadline.weight(.semibold)).foregroundStyle(.orange) }
                Text(item.caption).font(.title2.weight(.semibold))
                if let nickname = item.nickname { Text("授予 " + nickname).font(.subheadline) }
                if let story = item.story ?? item.criteria { Text(story).multilineTextAlignment(.center) }
                if let date = item.at { Text(String(date.prefix(10))).font(.caption).foregroundStyle(.secondary) }
                if item.archived { Text("已绝版").font(.caption).foregroundStyle(.secondary) }
                if isOwn, let id = item.awardId {
                    if item.category == "hidden" { Button(item.publicHidden ? "对他人隐藏" : "公开隐藏荣誉") { Task { await apply("collection.visibility", ["awardId":id,"public":!item.publicHidden]) } } }
                    if item.category != "hidden" || item.publicHidden {
                        Toggle(profile.flatMap { $0.customTitle }.map { "使用称号「\($0)」" } ?? "使用称号", isOn: $useTitle)
                        Button(profile?.badges.collection?.id == id ? "更新佩戴" : "佩戴荣誉") { Task { await apply("collection.wear", ["awardId":id,"useTitle":useTitle]) } }
                    }
                    if profile?.badges.collection?.id == id { Button("取下荣誉") { Task { await apply("collection.wear", ["awardId":NSNull()]) } } }
                }
                if let person = item.memberId { Button("打开荣誉档案") { selected = nil; memberId = person; category = "all" } }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button("完成") { selected = nil }
            }.buttonStyle(.bordered).padding(22).disabled(loading)
        }.presentationDetents([.medium, .large])
         .onAppear {
            if reduceMotion || unlocked == nil { reveal = true }
            else { withAnimation(.spring(response: 0.48, dampingFraction: 0.75)) { reveal = true } }
         }
    }
    private func show(_ item: CampusHonorItem) {
        reveal = reduceMotion || unlocked == nil
        useTitle = profile?.badges.collection?.id == item.awardId && profile?.useTitle == true
        selected = item
    }
    private func finishUnlock() {
        guard let award = unlocked else { return }
        unlocked = nil
        rendered.insert(award)
        Task {
            do { _ = try await tree.api.request("collection.ack", ["awardIds":[award]]); tree.clearHonorCollectionCache() }
            catch { self.error = error.localizedDescription }
        }
    }
    @MainActor private func load(append: Bool = false, showReward: Bool = true) async {
        revision += 1; let request = revision
        let target = memberId
        loading = true; error = nil
        if !append { items = []; more = false }
        defer { if revision == request { loading = false } }
        do {
            if let target {
                let content = try await tree.loadHonorCollection(member: target, offset: append ? items.count : 0, fresh: !showReward)
                guard revision == request else { return }
                profile = content; items += content.items.prefix(40); more = content.items.count > 40
                if showReward, isOwn, selected == nil,
                   let reward = items.first(where: { value in value.awardId.map { content.unseen.contains($0) && !rendered.contains($0) } == true }) {
                    unlocked = reward.awardId; show(reward)
                }
            } else {
                let arguments: [String: Any] = ["section":section,"year":year as Any? ?? NSNull(),"offset":append ? items.count : 0]
                let output = try await tree.api.request("collection.archive", arguments)
                guard revision == request else { return }
                let rows = output.honorArchive ?? []
                years = output.honorYears ?? []; items += rows.prefix(20); more = rows.count > 20
            }
        } catch { if revision == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    @MainActor private func apply(_ action: String, _ body: [String: Any]) async {
        guard !loading else { return }
        loading = true; error = nil
        let prior = selected?.id
        defer { loading = false }
        do {
            let response = try await tree.api.request(action, body)
            if let identity = response.updatedIdentity { tree.applyCollectionIdentity(identity) }
            await load(showReward: false)
            if let updated = items.first(where: { $0.id == prior }) { selected = updated }
        } catch { self.error = error.localizedDescription }
    }
}
