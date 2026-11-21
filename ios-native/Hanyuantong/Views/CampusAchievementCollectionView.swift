import SwiftUI

/// Global iPhone entry corresponding to Android's GlobalCollection.vue.
/// School and Learning evidence comes from the current authenticated native stores;
/// private device awards use the encrypted journal, and community awards are read-only
/// projections of the server's actual award records.
struct CampusAchievementCollectionView: View {
    @EnvironmentObject private var achievements: CampusAchievementStore
    @EnvironmentObject private var school: CampusStore
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var tree: TreeholeStore
    @EnvironmentObject private var display: DisplayPreferencesStore

    @State private var group = "全部"
    @State private var selected: CampusAchievement?
    @State private var communityHall: NativeCommunityAchievementHall?
    @State private var communityCollection: CampusCollectionProfile?
    @State private var loadingCommunity = false
    @State private var communityError: String?
    @State private var honorRoute: CampusHonorRoute?
    @State private var remoteGeneration = 0
    private let columns = [GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]

    private var entries: [CampusAchievement] {
        let known = CampusAchievementCatalog.entries
        let extras: [CampusAchievement] = (communityCollection?.items ?? []).compactMap { item in
            guard CampusAchievementCatalog.byCode[item.code] == nil,
                  item.awardId != nil, item.category != "identity" else { return nil }
            let category = item.category == "hidden" ? "隐藏" : "社区"
            return CampusAchievement(item.code, item.name, category,
                                     ["common": "普通", "fine": "普通", "rare": "稀有",
                                      "epic": "史诗", "legendary": "传奇"][item.rarity] ?? "普通",
                                     "community", "seal", item.criteria ?? "社区荣誉",
                                     item.story ?? item.criteria ?? "已获得的社区荣誉。")
        }
        let deduplicated = Dictionary(grouping: extras, by: \.code).compactMap { $0.value.first }
        return known + deduplicated.sorted { $0.name < $1.name }
    }
    private var active: [CampusAchievement] { entries.filter { group == "全部" || $0.group == group } }
    private var earnedCount: Int { entries.filter { isEarned($0) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overview
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CampusAchievementCatalog.groups, id: \.self) { item in
                            Button { group = item } label: {
                                Text(item).font(.subheadline.weight(group == item ? .semibold : .regular))
                                    .padding(.horizontal, 15).frame(minHeight: 38)
                                    .foregroundStyle(group == item ? .white : CampusTheme.text)
                                    .background(group == item ? CampusTheme.primary : CampusTheme.surface, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(group == item ? .isSelected : [])
                        }
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
                if let error = achievements.error {
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
        .onAppear {
            achievements.record("welcome")
            if display.preferences.name != "同学", !display.preferences.major.isEmpty {
                achievements.record("profile")
            }
            if school.tasks.contains(where: { $0.completed && $0.steps.filter(\.completed).count >= 2 }) {
                achievements.record("tasks")
            }
        }
        .task(id: tree.user?.id) { await loadCommunity() }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("你的校园纪念册").font(.title2.bold())
                    Text("本机、教务、学习通与社区荣誉集中展示")
                        .font(.footnote).foregroundStyle(CampusTheme.muted)
                }
                Spacer(minLength: 10)
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(Color(hex: 0x9D77BC))
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(earnedCount)).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("/ \(entries.count) 已解锁").font(.subheadline).foregroundStyle(CampusTheme.muted)
                Spacer()
                Text("\(entries.isEmpty ? 0 : Int(Double(earnedCount) / Double(entries.count) * 100))%")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.primary)
            }
            ProgressView(value: Double(earnedCount), total: Double(max(1, entries.count)))
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
        case "device":
            return achievements.date(for: item.code).map { CampusTheme.date($0, format: "yyyy-MM-dd") }
        case "school":
            guard school.isConnected else { return nil }
            switch item.code {
            case "identity": return school.lastSynced.map { CampusTheme.date($0, format: "yyyy-MM-dd") } ?? "当前连接"
            case "schedule":
                return school.courses.contains(where: { $0.source == "school" }) && school.lastSynced != nil
                    ? CampusTheme.date(school.lastSynced!, format: "yyyy-MM-dd") : nil
            case "grade": return school.grades.isEmpty ? nil : "当前教务连接"
            case "exam":
                return school.exams.isEmpty || !school.seenExamRecords ? nil : "当前教务连接"
            case "offline":
                return school.usedOfflineAcademicSchedule ? "当前教务连接" : nil
            default: return nil
            }
        case "learning":
            return learning.cache.session == "valid" && !learning.cache.courses.isEmpty &&
                   learning.cache.issues["courses"] == nil ? "当前学习通账号" : nil
        case "community":
            if let date = communityHall?.awards[item.code] { return String(date.prefix(10)) }
            if let awarded = communityCollection?.items.first(where: { $0.code == item.code && $0.awardId != nil }) {
                return awarded.at.map { String($0.prefix(10)) } ?? "社区已确认"
            }
            return nil
        default: return nil
        }
    }
    private func state(_ item: CampusAchievement) -> String {
        if isEarned(item) { return "已解锁" }
        if item.source == "community" { return tree.user == nil ? "待登录" : "待同步 / 未解锁" }
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
                    Button { Task { await loadCommunity() } } label: { Image(systemName: "arrow.clockwise") }
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
                    if item.source == "device", isEarned(item) {
                        Button {
                            achievements.togglePin(item.code)
                        } label: {
                            Label(achievements.journal.pins.contains(item.code) ? "从我的页面取下" : "展示到我的页面",
                                  systemImage: achievements.journal.pins.contains(item.code) ? "checkmark" : "bookmark")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!achievements.journal.pins.contains(item.code) && achievements.journal.pins.count >= 3)
                        Text("本机展示 \(achievements.journal.pins.count)/3")
                            .font(.footnote).foregroundStyle(CampusTheme.muted)
                    }
                }.padding(24).frame(maxWidth: 450)
            }
            .navigationTitle("成就详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selected = nil } } }
        }
    }

    @MainActor private func loadCommunity() async {
        remoteGeneration += 1
        let current = remoteGeneration
        communityHall = nil; communityCollection = nil
        guard let id = tree.user?.id else { communityError = nil; return }
        loadingCommunity = true; communityError = nil
        defer { if current == remoteGeneration { loadingCommunity = false } }
        do {
            // The legacy hall is a read-only, user-scoped endpoint; it must not issue awards.
            let result = try await tree.api.request("honors.hall")
            guard current == remoteGeneration, tree.user?.id == id else { return }
            if result.hall?.id == id { communityHall = result.hall }
            if tree.honorCollectionEnabled {
                let profile = try await tree.loadHonorCollection(member: id)
                guard current == remoteGeneration, tree.user?.id == id else { return }
                if profile.id == id { communityCollection = profile }
            }
        } catch {
            guard current == remoteGeneration, tree.user?.id == id else { return }
            communityError = "社区荣誉暂未同步。本机收藏及教务数据仍可查看。"
        }
    }
}