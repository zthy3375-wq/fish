import SwiftUI

/// Global iPhone entry corresponding to Android's GlobalCollection.vue.
/// Local awards come from persisted device and account journals.
/// Community awards and the public showcase use the community service.
private enum CommunityAchievementPlaceholders {
    // Synchronized with src/domain/communityAchievementCards.ts. Server-owned,
    // never awarded from the client based on an unverified local counter.
    static let milestones: [CampusAchievement] = [
        CampusAchievement("first-hundred", "开服第一批", "社区", "普通", "community", "flag", "同步社区记录后可查看解锁条件。", "社区历史里的一份珍贵纪念。"),
        CampusAchievement("campus-observer", "今天的邯院", "社区", "普通", "community", "mappin", "同步社区记录后可查看解锁条件。", "每个校园角落都值得被发现。"),
        CampusAchievement("good-company", "这一楼热闹了", "社区", "普通", "community", "bubble.left.and.bubble.right", "同步社区记录后可查看解锁条件。", "从一条回复开始的热闹。"),
        CampusAchievement("answer-guide", "帮上忙了", "社区", "普通", "community", "hand.raised", "同步社区记录后可查看解锁条件。", "帮助别人，也是自己的故事。"),
        CampusAchievement("campus-photographer", "留住邯院的光", "社区", "普通", "community", "camera", "同步社区记录后可查看解锁条件。", "邯院的光被你记录。"),
        CampusAchievement("community-classic", "这帖被记住了", "社区", "普通", "community", "trophy", "同步社区记录后可查看解锁条件。", "一段值得纪念的社区内容。"),
        CampusAchievement("landmark-post", "这帖火了", "社区", "普通", "community", "star", "同步社区记录后可查看解锁条件。", "有人记住了你的表达。"),
        CampusAchievement("hundred-likes", "一百个赞", "社区", "普通", "community", "heart", "同步社区记录后可查看解锁条件。", "一百份来自同学的喜欢。"),
        CampusAchievement("full-page", "写满这一页", "社区", "普通", "community", "books.vertical", "同步社区记录后可查看解锁条件。", "校园这一页，记录了你的故事。")
    ]
    static let hiddenCapacity = 5
}

struct CampusAchievementCollectionView: View {
    @ObservedObject private var deviceAchievements = CampusAchievementStore.shared
    @ObservedObject private var journal = MedalJournal.shared
    @EnvironmentObject private var school: CampusStore
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var tree: TreeholeStore
    let initialCode: String?
    @State private var openedInitial = false

    @State private var group = "全部"
    @State private var selected: CampusAchievement?
    @State private var showSettings = false
    @State private var communityHall: NativeHonorHall?
    @State private var communityCollection: CampusCollectionProfile?
    @State private var communityItems: [CampusHonorItem] = []
    @State private var editingShowcase = false
    @State private var showcaseError: String?
    @State private var loadingCommunity = false
    @State private var communityError: String?
    @State private var honorRoute: CampusHonorRoute?
    @State private var remoteGeneration = 0
    private let columns = [GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]

    private var entries: [CampusAchievement] {
        let known = CampusAchievementCatalog.entries
        let extras: [CampusAchievement] = currentItems.compactMap { item in
            guard CampusAchievementCatalog.byCode[item.code] == nil,
                  item.awardId != nil, item.category != "identity" else { return nil }
            let category = item.archived ? "已停发" : item.category == "hidden" ? "隐藏" : "社区"
            return CampusAchievement(item.code, item.name, category,
                                     ["common": "普通", "fine": "普通", "rare": "稀有",
                                      "epic": "史诗", "legendary": "传奇"][item.rarity] ?? "普通",
                                     "community", "seal", item.criteria ?? "社区荣誉",
                                     item.story ?? item.criteria ?? "已获得的社区荣誉。")
        }
        let confirmed = Dictionary(grouping: extras, by: \.code).compactMap { $0.value.first }
        let confirmedCodes = Set(confirmed.map(\.code))
        let pendingMilestones = CommunityAchievementPlaceholders.milestones.filter { !confirmedCodes.contains($0.code) }
        let revealedHidden = confirmed.filter { $0.hidden }.count
        let hiddenPlaceholders: [CampusAchievement] = (0..<max(0, CommunityAchievementPlaceholders.hiddenCapacity - revealedHidden)).map { i in
            CampusAchievement("community-mystery-" + String(i), "隐藏成就", "隐藏", "稀有",
                              "community", "questionmark", "", "还没有发现的校园秘密。")
        }
        return known + pendingMilestones + confirmed.sorted { $0.name < $1.name } + hiddenPlaceholders
    }
    private var activeEntries: [CampusAchievement] { entries.filter { $0.group != "已停发" } }
    private var active: [CampusAchievement] { group == "全部" ? activeEntries : entries.filter { $0.group == group } }
    private var earnedCount: Int { activeEntries.filter { isEarned($0) }.count }
    private var groups: [String] {
        CampusAchievementCatalog.groups + (entries.contains { $0.group == "已停发" } ? ["已停发"] : [])
    }
    private var privatePins: [String] { journal.pinned(school: school.schoolMedalScope, learning: learning.cache.account) }
    private var publicPins: [String] { tree.user?.showcase ?? communityCollection?.showcase ?? communityHall?.showcase ?? [] }
    private var currentItems: [CampusHonorItem] { communityCollection?.id == tree.user?.id ? communityItems : [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overview
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
                        ForEach(groups, id: \.self) { item in
                            Button { group = item } label: {
                                Text(item).font(.subheadline.weight(group == item ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(group == item ? .white : CampusTheme.text)
                                    .background(group == item ? CampusTheme.primary : CampusTheme.surface, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(group == item ? .isSelected : [])
                        }
                }.accessibilityIdentifier("achievement-filters")
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(active) { item in
                        Button { selected = item } label: { medal(item) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("achievement-" + item.code)
                            .accessibilityLabel((isEarned(item) ? "已解锁 " : "未解锁 ") + visibleName(item))
                    }
                }
                communitySection
                Button { showSettings = true } label: { Label("成就反馈", systemImage: "bell") }
                    .frame(minHeight: 44)
                if let error = deviceAchievements.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.red)
                }
            }.padding(16).frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        }
        .background(CampusTheme.background)
        .navigationTitle("荣誉殿堂")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { item in detail(item) }
        .sheet(item: $honorRoute) { route in CampusHonorCollectionView(tree: tree, route: route) }
        .sheet(isPresented: $showSettings) { MedalSettings() }
        .onAppear {
            guard !openedInitial else { return }
            openedInitial = true
            selected = entries.first { $0.code == initialCode }
        }
        .onChange(of: tree.user?.id) { _ in
            if selected?.source == "community" { selected = nil }
            showcaseError = nil
        }
        .task(id: tree.user?.id) { await loadCommunity() }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("成就收藏馆").font(.title2.bold())
                    Text("本机、教务、学习通与社区荣誉集中展示")
                        .font(.footnote).foregroundStyle(CampusTheme.muted)
                }
                Spacer(minLength: 10)
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(Color(hex: 0x9D77BC))
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(earnedCount)).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("/ \(activeEntries.count) 已解锁").font(.subheadline).foregroundStyle(CampusTheme.muted)
                Spacer()
                Text("\(activeEntries.isEmpty ? 0 : Int(Double(earnedCount) / Double(activeEntries.count) * 100))%")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.primary)
            }
            ProgressView(value: Double(earnedCount), total: Double(max(1, activeEntries.count)))
                .tint(Color(hex: 0xA58BDD))
            Text("未连接的账号显示待连接；不会凭空解锁或合并不同账号的荣誉。")
                .font(.caption2).foregroundStyle(CampusTheme.muted)
        }
        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func medal(_ item: CampusAchievement) -> some View {
        let earned = isEarned(item)
        return VStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(earned ? Color(hex: 0xEEE6FB) : Color(hex: 0xF1EFF3))
                    .frame(width: 49, height: 49)
                Image(systemName: item.hidden && !earned ? "questionmark" : earned ? item.symbol : "lock")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(earned ? Color(hex: 0x714B9A) : Color(hex: 0x92909A))
                    .frame(width: 49, height: 49)
                if earned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(Color(hex: 0x7650AD))
                        .background(Circle().fill(CampusTheme.surface))
                        .offset(x: 4, y: 4)
                }
            }
            Text(visibleName(item)).font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center).lineLimit(2).frame(height: 32)
            Text(state(item)).font(.caption2.weight(.medium))
                .foregroundStyle(earned ? Color(hex: 0x624285) : CampusTheme.muted)
                .padding(.horizontal, 5).padding(.vertical, 4)
                .background(earned ? Color(hex: 0xE5D8F6) : .clear, in: Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: 121)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(earned ? Color(hex: 0xAB8BD0) : CampusTheme.border,
                              style: StrokeStyle(lineWidth: earned ? 1.2 : 1, dash: earned ? [] : [4, 4]))
        }
    }
    private func visibleName(_ item: CampusAchievement) -> String {
        item.hidden && !isEarned(item) ? "隐藏成就" : item.name
    }
    private func isEarned(_ item: CampusAchievement) -> Bool { awardDate(item) != nil }

    private func awardDate(_ item: CampusAchievement) -> String? {
        switch item.source {
        case "device", "school", "learning":
            guard let medal = CampusMedal.byCode[item.code] else { return nil }
            let scope = item.source == "school" ? school.schoolMedalScope : learning.cache.account
            return journal.stamp(medal, scope: scope).map { CampusTheme.date($0, format: "yyyy-MM-dd") }
        case "community":
            let id = tree.user?.id
            if communityHall?.id == id, let date = communityHall?.awards[item.code] { return String(date.prefix(10)) }
            if communityCollection?.id == id, let date = communityCollection?.baseAwards?[item.code] { return String(date.prefix(10)) }
            if let awarded = currentItems.first(where: { $0.code == item.code && $0.awardId != nil }) {
                return awarded.at.map { String($0.prefix(10)) } ?? "社区已确认"
            }
            return nil
        default: return nil
        }
    }
    private func state(_ item: CampusAchievement) -> String {
        if isEarned(item) { return "已解锁" }
        if item.source == "community" { return tree.user == nil ? "待登录" : item.hidden ? "尚未发现" : "待同步 / 未解锁" }
        if item.source == "school" && !school.isConnected { return "待连接" }
        if item.source == "learning" && !learning.connected { return "待连接" }
        return item.hidden ? "尚未发现" : "未解锁"
    }
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("社区身份与荣誉").font(.headline)
                    Text(tree.user.map { "当前账号：\($0.nickname)" } ?? "连接邯院通社区账号后可同步")
                        .font(.footnote).foregroundStyle(CampusTheme.muted)
                }
                Spacer()
                if loadingCommunity { ProgressView() }
                else if tree.user != nil {
                    Button { Task { await loadCommunity(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("同步社区荣誉")
                }
            }
            if let error = communityError { Text(error).font(.footnote).foregroundStyle(CampusTheme.muted) }
            if let user = tree.user, tree.honorCollectionEnabled {
                Button {
                    honorRoute = CampusHonorRoute(memberId: user.id)
                } label: {
                    HStack {
                        Label("查看社区荣誉收藏与佩戴", systemImage: "seal")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(CampusTheme.primary)
            } else {
                Button {
                    tree.accountEntryRequested = true
                    school.selectedTab = .community
                } label: {
                    HStack {
                        Label(tree.user == nil ? "前往社区账号" : "前往社区查看", systemImage: "person.crop.circle")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(CampusTheme.primary)
            }
            Text("本机成就最多展示三枚，只存储在当前 iPhone；社区荣誉由服务器验证与管理。")
                .font(.caption2).foregroundStyle(CampusTheme.muted)
        }
        .padding(16)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func detail(_ item: CampusAchievement) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: isEarned(item) ? item.symbol : item.hidden ? "questionmark" : "lock")
                        .font(.system(size: 38))
                        .foregroundStyle(isEarned(item) ? Color(hex: 0x7755A0) : CampusTheme.muted)
                        .frame(width: 82, height: 82)
                        .background(isEarned(item) ? Color(hex: 0xEEE6FB) : Color(hex: 0xF1EFF3),
                                    in: RoundedRectangle(cornerRadius: 22))
                    Text(visibleName(item)).font(.title2.bold())
                    Text(item.group + " · " + (isEarned(item) ? item.tier : "未解锁"))
                        .font(.subheadline).foregroundStyle(CampusTheme.muted)
                    if !item.hidden || isEarned(item) {
                        Text(item.story).multilineTextAlignment(.center)
                        Divider()
                        LabeledContent("获取条件", value: item.condition)
                    } else {
                        Text("有些校园回忆，会在意想不到的时候出现。")
                            .multilineTextAlignment(.center).foregroundStyle(CampusTheme.muted)
                    }
                    LabeledContent("解锁状态", value: state(item))
                    LabeledContent("收藏归属", value: ["device": "本机", "school": "当前教务连接",
                                                     "learning": "当前学习通账号", "community": "邯院通社区账号"][item.source] ?? "")
                    if let date = awardDate(item) { LabeledContent("获得记录", value: date) }
                    if item.source == "community", isEarned(item) {
                        communityShowcaseButton(item)
                    } else if isEarned(item), let medal = CampusMedal.byCode[item.code] {
                        let pinned = privatePins.contains(item.code)
                        Button {
                            journal.togglePin(medal, school: school.schoolMedalScope, learning: learning.cache.account)
                        } label: {
                            Label(pinned ? "从我的页面取下" : "展示到我的页面",
                                  systemImage: pinned ? "checkmark" : "bookmark")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!pinned && privatePins.count >= 3)
                        Text("本机展示 \(privatePins.count)/3")
                            .font(.footnote).foregroundStyle(CampusTheme.muted)
                    }

                }.padding(24).frame(maxWidth: 450)
            }
            .navigationTitle("成就详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selected = nil } } }
        }
    }

    @ViewBuilder private func communityShowcaseButton(_ item: CampusAchievement) -> some View {
        let award = currentItems.first { $0.code == item.code && $0.awardId != nil }
        let key = award?.awardId ?? item.code
        let pinned = publicPins.contains(key)
        if let award, award.category == "hidden", !award.publicHidden {
            Text("这枚隐藏成就仅自己可见，可在社区荣誉收藏中设置公开。").font(.footnote)
        } else if (communityCollection?.layoutVersion ?? 0) >= 2 || award == nil {
            Button {
                Task { await changeShowcase(key, remove: pinned) }
            } label: {
                Label(pinned ? "从社区主页取下" : "展示到社区主页", systemImage: pinned ? "checkmark" : "bookmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(editingShowcase || (!pinned && publicPins.count >= 3))
            if let showcaseError { Text(showcaseError).font(.footnote).foregroundStyle(.red) }
        }
    }

    @MainActor private func changeShowcase(_ key: String, remove: Bool) async {
        guard !editingShowcase, let owner = tree.user?.id, remove || publicPins.count < 3 else { return }
        let pins = remove ? publicPins.filter { $0 != key } : publicPins + [key]
        editingShowcase = true; showcaseError = nil
        defer { editingShowcase = false }
        do {
            if (communityCollection?.layoutVersion ?? 0) >= 2 {
                let result = try await tree.api.request("collection.showcase", ["items": pins])
                guard tree.user?.id == owner, let identity = result.updatedIdentity, identity.id == owner else { return }
                tree.applyCollectionIdentity(identity)
            } else {
                guard let hall = communityHall, hall.id == owner else { return }
                let result = try await tree.api.request("honors.wear", ["honor": hall.badges.worn?.code as Any? ?? NSNull(), "showcase": pins])
                guard tree.user?.id == owner, let updated = result.hall, updated.id == owner else { return }
                communityHall = updated
                tree.applyIdentity(updated)
            }
        } catch {
            guard tree.user?.id == owner else { return }
            showcaseError = error.localizedDescription
        }
    }

    @MainActor private func loadCommunity(force: Bool = false) async {
        remoteGeneration += 1
        let current = remoteGeneration
        loadingCommunity = true; communityError = nil
        defer { if current == remoteGeneration { loadingCommunity = false } }
        do {
            if tree.user == nil { try await tree.restoreGalleryIdentity() }
            guard let id = tree.user?.id, current == remoteGeneration, !Task.isCancelled else { return }
            if communityHall?.id != id { communityHall = nil; communityCollection = nil; communityItems = [] }
            if let storage = try? ProtectedStorage(),
               let cached = try? storage.read("honors-" + id, as: NativeHonorHall.self), cached.id == id {
                communityHall = cached
            }
            let result = try await tree.api.request("honors.hall")
            guard current == remoteGeneration, tree.user?.id == id, !Task.isCancelled else { return }
            guard let hall = result.hall, hall.id == id else { throw TreeholeError(code: "invalid_response") }
            communityHall = hall
            if let storage = try? ProtectedStorage() { try? storage.write(hall, name: "honors-" + id) }
            guard tree.honorCollectionEnabled || !tree.ready else { return }
            do {
                let first = try await tree.loadHonorCollection(member: id, fresh: force)
                var page = first.items
                var items = Array(page.prefix(40))
                while page.count > 40 {
                    guard current == remoteGeneration, tree.user?.id == id, !Task.isCancelled else { return }
                    page = try await tree.loadHonorCollection(member: id, offset: items.count).items
                    items.append(contentsOf: page.prefix(40))
                }
                guard current == remoteGeneration, tree.user?.id == id, !Task.isCancelled else { return }
                communityCollection = first
                communityItems = items
                if let showcase = first.showcase {
                    tree.applyCollectionIdentity(.init(id: id, badges: first.badges, showcase: showcase, collectionShowcase: nil))
                }
            } catch let error as TreeholeError where ["not_found", "invalid_request"].contains(error.code) {
                // Older service deployments expose only the original hall.
            }
        } catch {
            guard current == remoteGeneration, !Task.isCancelled else { return }
            if (error as? TreeholeError)?.code == "session_expired" { tree.clear() }
            communityError = "社区荣誉暂未同步。本机收藏及教务数据仍可查看。"
        }
    }
}
