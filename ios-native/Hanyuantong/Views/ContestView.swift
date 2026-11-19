import SwiftUI
import Combine

struct ContestView: View {
    let api: TreeholeService
    let user: TreeholeMember
    var initialId: String? = nil
    var initialPage: String = "events"
    var backendSchema: Int = 13
    var onMember: ((String) -> Void)? = nil
    var onPost: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = Date()
    @State private var events: [NativeContest] = []
    @State private var selected: NativeContest?
    @State private var selectedWork: NativeContestEntry?
    @State private var entries: [NativeContestEntry] = [], mine: [NativeContestEntry] = []
    @State private var page = "events", typeFilter = ""
    @State private var operationTask: Task<Void, Never>?
    @State private var busy = false, more = false, editor = false, administration = false, winnersOnly = false
    @State private var error: String?, notice: String?
    @State private var serverOffset: TimeInterval = 0
    @State private var votesUsed = 0
    @State private var seed = UUID().uuidString
    @State private var editing: NativeContestEntry?
    @State private var draftEvent: NativeContest?
    @State private var summaryOffset = 0, summaryMore = false
    @State private var summary = TreeholeEnvelope()
    @State private var theme = "", reason = "", mergeTarget = "", requestID = UUID().uuidString
    @State private var reportTarget: String?, withdrawTarget: NativeContestEntry?
    @State private var gallery: TreeholeGallerySelection?
    @State private var year = Calendar(identifier: .gregorian).component(.year, from: Date())
    private var admin: Bool { user.badges?.official?.code == "developer" }
    private var now: Date { clock.addingTimeInterval(serverOffset) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { Text(error).font(.caption).foregroundStyle(.red); Button("重试加载") { run { try await refresh() } } }
            if let notice { Text(notice).font(.caption).foregroundStyle(TreeholeTheme.primary).accessibilityAddTraits(.updatesFrequently) }
            if busy { ProgressView("正在确认…") }
            if editor, let event = selected {
                ContestSubmissionView(api: api, memberID: user.id, event: event, entry: editing, submitted: didSubmit, close: { editor = false })
            } else if administration, let event = draftEvent {
                Button("返回比赛") { administration = false }.disabled(busy)
                ContestManagementView(api: api, event: event, persisted: event.state != "draft" || events.contains(where: { $0.id == event.id }), backendSchema: backendSchema, saved: { id in administration = false; run { try await open(id) } })
            } else if let event = selected, let entry = selectedWork {
                Button("返回作品墙") { selectedWork = nil; notice = nil }.disabled(busy)
                work(entry, event: event)
            } else {
                header
                if let event = selected { detail(event) }
                else if page == "honors" { honors }
                else if page == "themes" { themes }
                else if page == "year" { annual }
                else if page == "archive" || page == "champions" { archive }
                else if !busy { Text("下一场精彩，很快相遇").font(.title2.bold()); Text("新赛事发布后会出现在这里，先看看历届故事吧。").foregroundStyle(.secondary) }
                if page == "events" {
                    Divider()
                    Button { destination("archive") } label: { Label("历届赛事", systemImage: "trophy") }
                    Button("下一期主题征集") { destination("themes") }
                }
            }
        }.sheet(item: $gallery) { selection in ContestGallery(selection: selection, api: api, contestId: selected?.id ?? "") }
        .confirmationDialog("撤回这件作品？", isPresented: Binding(get: { withdrawTarget != nil }, set: { if !$0 { withdrawTarget = nil } }), titleVisibility: .visible) {
            Button("撤回作品", role: .destructive) { if let entry = withdrawTarget { run { _ = try await api.request("contests.withdraw", ["contestId":entry.contestId, "entryId":entry.id]); mine.removeAll { $0.id == entry.id }; entries.removeAll { $0.id == entry.id }; selectedWork = nil; notice = "作品已撤回，截止前可以重新投稿。" } } }
            Button("继续参赛", role: .cancel) {}
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { clock = $0 }
        .task { await perform { page = initialPage; if let initialId { try await open(initialId) } else { try await load() } } }
        .onDisappear { operationTask?.cancel() }
    }
    private var header: some View {
        HStack {
            if page != "events" || (initialId != nil && selected != nil) { Button("返回赛事") { page = "events"; selected = nil; run { try await load() } }.disabled(busy) }
            Text(["events":"主题赛事","archive":"历届赛事","champions":"冠军档案馆","year":"年度榜单","themes":"主题征集","honors":"赛事荣誉"][page] ?? "主题赛事").font(.title2.bold())
            Spacer()
            Button { run { try await refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新赛事").disabled(busy)
            if admin { Button { draftEvent = .draft(); administration = true } label: { Image(systemName: "plus") }.accessibilityLabel("创建赛事").disabled(busy) }
        }
    }
    @ViewBuilder private func detail(_ event: NativeContest) -> some View {
        if page != "events" { Button("返回档案列表") { selected = nil }.disabled(busy) }
        if let cover = event.cover { AsyncImage(url: cover.url.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.white }.frame(height: 175).clipped().clipShape(RoundedRectangle(cornerRadius: 16)) }
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(event.type).font(.caption); Spacer(); Text(event.label(at: now)).font(.caption.weight(.semibold)) }
            Text(event.title).font(.title.bold()); Text(event.description).font(.subheadline)
            Text(event.remaining(now: now) + " · \(event.participantCount)人 · \(event.entryCount)件作品").font(.caption).foregroundStyle(.secondary)
            Button(primaryLabel(event)) { if event.phase(at: now) == "submitting" { if let own = mine.first { selectedWork = own } else { compose() } } else { notice = event.phase(at: now) == "reviewing" ? "结果统计与审核中，公布后会保留全部作品与荣誉。" : "在下方作品墙选择作品，点开查看完整内容。" } }.buttonStyle(.borderedProminent).disabled(busy || event.paused)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 18))
        DisclosureGroup("比赛规则、日程与奖励") {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.rules)
                Text("每人\(event.maxEntries)件作品、\(event.votesPerUser)票。禁止自投，同票并列。满\(event.minEntries)件有效作品且有有效票时颁发前三，其他有效作品保留纪念。")
                Text(event.minAccountHours > 0 ? "投票开始前需注册满\(event.minAccountHours)小时" : "普通社区账号均可参与，异常票可复核")
                ForEach([("投稿截止",event.submissionEnds),("投票开始",event.votingStarts),("投票截止",event.votingEnds),("公布时间",event.awardAt)], id: \.0) { label, value in Text(label + " · " + displayTime(value)) }
                Text("以上日程均为北京时间")
            }.font(.caption).padding(.vertical, 8)
        }
        if event.state == "ended" {
            ContestResultCeremony().id(event.id)
            Picker("作品筛选", selection: $winnersOnly) { Text("全部作品").tag(false); Text("获奖作品").tag(true) }.pickerStyle(.segmented).onChange(of: winnersOnly) { _ in run { try await wall() } }
        }
        HStack { Text(event.state == "ended" ? "作品与获奖记录" : "参赛作品").font(.headline); Spacer(); if event.phase(at: now) == "voting" { Text("还可投\(max(0,event.votesPerUser-votesUsed))票").font(.caption) } }
        LazyVGrid(columns: event.formats == ["text"] ? [GridItem(.flexible())] : [GridItem(.flexible()),GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(entries) { entry in teaser(entry) }
        }
        if entries.isEmpty && !busy { Text(winnersOnly ? "暂无获奖作品，可查看全部作品。" : "第一件作品，也许来自你。").foregroundStyle(.secondary).padding(.vertical, 20) }
        if more { Button("查看更多作品") { run { try await wall(more: true) } }.disabled(busy) }
        if admin { Button("管理这场比赛") { draftEvent = event; administration = true } }
    }
    private func teaser(_ entry: NativeContestEntry) -> some View {
        Button { selectedWork = entry } label: {
            VStack(alignment: .leading, spacing: 9) {
                if let image = entry.images.first { AsyncImage(url: image.url.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "photo") }.frame(height: 160).frame(maxWidth: .infinity).clipped() }
                if let award = entry.awards.first(where: { $0.kind != "participation" }) { Label(award.label, systemImage: "trophy").font(.caption).foregroundStyle(TreeholeTheme.primary) }
                Text(entry.title).font(.headline).foregroundStyle(.primary)
                if entry.images.isEmpty { Text(entry.body).font(.subheadline).lineLimit(3).foregroundStyle(.secondary) }
                HStack { Text(entry.author + (entry.mine ? " · 我" : "")).font(.caption).foregroundStyle(.secondary); Spacer(); if entry.voted { Image(systemName: "checkmark.circle.fill").foregroundStyle(TreeholeTheme.primary) } }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(TreeholeTheme.tint))
        }.buttonStyle(.plain).accessibilityLabel("查看作品：" + entry.title).disabled(busy)
    }
    private func work(_ entry: NativeContestEntry, event: NativeContest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(entry.awards) { award in Label(award.label, systemImage: "trophy.fill").foregroundStyle(TreeholeTheme.primary) }
            ForEach(Array(entry.images.enumerated()), id: \.element.id) { index, image in Button { gallery = TreeholeGallerySelection(postId: entry.id, images: entry.images, index: index) } label: { AsyncImage(url: image.url.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: { Label("点开重试图片", systemImage: "photo") }.frame(maxHeight: 360) }.buttonStyle(.plain) }
            Text(entry.title).font(.title.bold()); Button(entry.author) { onMember?(entry.memberId) }.font(.caption); Text(entry.body).textSelection(.enabled)
            if let votes = entry.votes { Text("最终 \(votes) 票").font(.caption) }
            if event.phase(at: now) == "voting" && !event.paused && !entry.mine {
                Text("还可投 \(max(0,event.votesPerUser-votesUsed)) / \(event.votesPerUser) 票").font(.subheadline)
                Button { vote(entry, event: event) } label: { Label(entry.voted ? "已投票 · 撤回" : "投一票", systemImage: entry.voted ? "checkmark.circle.fill" : "hand.thumbsup") }.buttonStyle(.borderedProminent).disabled(busy || (!entry.voted && votesUsed >= event.votesPerUser)).scaleEffect(entry.voted ? 1.02 : 1).animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: entry.voted)
                Text("投票截止前可撤回，实时票数不公开。").font(.caption).foregroundStyle(.secondary)
            }
            if entry.mine && event.phase(at: now) == "submitting" && !event.paused { HStack { Button("编辑作品") { compose(entry) }; Button("撤回作品", role: .destructive) { withdrawTarget = entry } }.disabled(busy) }
            if let id = entry.postId { Button("查看原帖") { onPost?(id) } }
            if !entry.mine { DisclosureGroup("举报作品") { TextField("请说明不符合规则的地方", text: $reason); Button("提交举报") { run { _ = try await api.request("contests.report", ["contestId":event.id,"entryId":entry.id,"reason":reason]); reason = ""; notice = "举报已提交" } }.disabled(busy || reason.count < 2) } }
        }
    }
    private var archive: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Button("历史赛事") { destination("archive") }; Button("冠军档案") { destination("champions") }; Button("年度榜单") { destination("year") } }
            Stepper("\(year) 年", value: $year, in: 2020...9999).onChange(of: year) { _ in run { try await load() } }
            TextField("所有类型", text: $typeFilter).onSubmit { run { try await load() } }
            ForEach(events.filter { ["ended","cancelled"].contains($0.state) }) { event in Button { run { try await open(event.id); if page == "champions" { winnersOnly = true; try await wall() } } } label: { HStack { Image(systemName: "trophy"); VStack(alignment: .leading) { Text(event.title).font(.headline); Text(event.type + " · " + event.label).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") } }.buttonStyle(.plain).padding(.vertical, 10) }
            if events.isEmpty && !busy { Text("本次筛选下暂无往期赛事").foregroundStyle(.secondary) }
            if more { Button("更多历史赛事") { run { try await load(more: true) } } }
        }
    }
    private var annual: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("\(year) 年", value: $year, in: 2020...9999).onChange(of: year) { _ in run { try await load() } }
            Text("冠军5分、亚军3分、季军2分、优秀作品1分，同分并列。").font(.caption)
            ForEach(summary.leaders ?? []) { leader in HStack { Text(leader.nickname); Spacer(); Text("\(leader.score)分") } }
            if summaryMore { Button("更多年度排名") { run { try await load(more: true) } } }
        }
    }
    private var honors: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats = summary.stats { Text("参赛 \(stats.participations) · 冠军 \(stats.champions) · 前三 \(stats.podiums)").font(.headline)
                if stats.champions >= 1 { Text("初露锋芒") }; if stats.champions >= 5 { Text("常胜将军") }; if stats.champions >= 20 { Text("不败传说") }; if stats.participations >= 100 { Text("百战老兵") }; if stats.podiums >= 10 { Text("民间艺术家") }
            }
            ForEach(summary.annual ?? [], id: \.self) { year in Text("\(year) 年度赛事之王") }
            if summaryMore { Button("更多赛事荣誉") { run { try await load(more: true) } } }
            ForEach(summary.awards ?? []) { award in VStack(alignment: .leading) { Button((award.title ?? "主题赛事") + " · " + award.label) { if let id = award.contest_id { run { try await open(id) } } }; Button(summary.worn == award.id ? "取消佩戴" : "佩戴") { run { _ = try await api.request("contests.wear", ["awardId":summary.worn == award.id ? NSNull() : award.id as Any]); try await load() } }.font(.caption) } }
        }
    }
    private var themes: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summary.solicitation == true {
                TextField("提议下一场主题", text: $theme)
                Button("提交提议") { run {
                    _ = try await api.request("contests.suggest", ["title":theme, "requestId":requestID])
                    requestID = UUID().uuidString; theme = ""; try await load()
                } }.disabled(theme.count < 3)
            }
            if admin {
                TextField("审核／合并理由", text: $reason)
                Picker("合并到已通过的主题", selection: $mergeTarget) {
                    Text("选择主题").tag("")
                    ForEach((summary.themes ?? []).filter { $0.status == "approved" }) { item in Text(item.title).tag(item.id) }
                }
            }
            ForEach(summary.themes ?? []) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.title); Spacer(); Text("\(item.votes)")
                        if item.status == "approved" && summary.solicitation == true {
                            Button(item.voted ? "已支持" : "支持") { run {
                                _ = try await api.request("contests.themevote", ["themeId":item.id, "enabled":!item.voted])
                                try await load()
                            } }
                        }
                    }
                    if admin {
                        HStack {
                            Button("通过") { reviewTheme(item.id, kind: "theme", decision: "approve") }
                            Button("移除") { reviewTheme(item.id, kind: "theme", decision: "remove") }
                            Button("合并") { reviewTheme(item.id, kind: "merge", decision: "approve") }.disabled(mergeTarget.isEmpty || mergeTarget == item.id)
                        }.disabled(reason.count < 2)
                    }
                }
            }
            if summaryMore { Button("更多候选主题") { run { try await load(more: true) } } }
        }
    }
    private func reviewTheme(_ id: String, kind: String, decision: String) {
        run {
            _ = try await api.request("contests.review", ["contestId":NSNull(), "kind":kind, "targetId":id, "decision":decision, "reason":reason, "mergeId":mergeTarget.isEmpty ? NSNull() : mergeTarget as Any])
            mergeTarget = ""; try await load()
        }
    }
    private func primaryLabel(_ event: NativeContest) -> String { if event.paused { return "比赛已暂停" }; if event.phase(at: now) == "submitting" { return mine.isEmpty ? "我要参赛" : "查看我的作品" }; return ["upcoming":"查看预告","waiting":"查看作品","voting":"参与投票","reviewing":"等待结果","ended":"查看结果","cancelled":"查看作品"][event.phase(at: now)] ?? "查看比赛" }
    private func displayTime(_ value: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.timeZone = TimeZone(identifier: "Asia/Shanghai"); f.dateFormat = "M月d日 HH:mm"; return NativeContest.date(value).map(f.string) ?? value }
    private func compose(_ entry: NativeContestEntry? = nil) { editing = entry; editor = true }
    private func didSubmit(_ entry: NativeContestEntry) { mine.removeAll { $0.id == entry.id }; mine.insert(entry, at: 0); entries.removeAll { $0.id == entry.id }; entries.insert(entry, at: 0); selectedWork = entry; editor = false; notice = "作品已保存，参赛成功" }
    private func vote(_ entry: NativeContestEntry, event: NativeContest) { run { let enabled = !entry.voted; let r = try await api.request("contests.vote", ["contestId":event.id,"entryId":entry.id,"enabled":enabled]); let confirmed = NativeContestVoteConfirmation.apply(entry, enabled: enabled, used: votesUsed, response: r); votesUsed = confirmed.used; entries = entries.map { $0.id == entry.id ? confirmed.entry : $0 }; selectedWork = confirmed.entry; notice = confirmed.entry.voted ? "这一票，已送达" : "已撤回，可以重新选择" } }
    private func destination(_ value: String) { guard !busy else { return }; page = value; selected = nil; selectedWork = nil; entries = []; notice = nil; run { try await load() } }
    private func run(_ work: @escaping () async throws -> Void) { guard !busy else { return }; operationTask = Task { await perform(work) } }
    @MainActor private func perform(_ work: () async throws -> Void) async { guard !busy else { return }; busy = true; error = nil; defer { busy = false }; do { try await work() } catch is CancellationError {} catch { self.error = (error as? TreeholeError)?.errorDescription ?? "连接失败，请重试，已填写内容会保留。" } }
    private func refresh() async throws { if let selected { try await open(selected.id, fresh: true) } else { try await load(fresh: true) } }
    private func load(more: Bool = false, fresh: Bool = false) async throws {
        if ["honors","themes","year"].contains(page) {
            let action = ["honors":"contests.profile","themes":"contests.themes","year":"contests.year"][page]!
            let r = try await api.request(action, ["year":year,"offset":more ? summaryOffset+20 : 0,"_fresh":fresh]); try Task.checkCancellation()
            var next = r; summaryOffset = more ? summaryOffset+20 : 0
            if page == "honors" { summaryMore = (r.awards?.count ?? 0)>20; next.awards = (more ? summary.awards ?? [] : []) + Array((r.awards ?? []).prefix(20)) }
            if page == "themes" { summaryMore = (r.themes?.count ?? 0)>20; next.themes = (more ? summary.themes ?? [] : []) + Array((r.themes ?? []).prefix(20)) }
            if page == "year" { summaryMore = (r.leaders?.count ?? 0)>20; next.leaders = (more ? summary.leaders ?? [] : []) + Array((r.leaders ?? []).prefix(20)) }
            summary = next; return
        }
        let archived = ["archive","champions"].contains(page)
        let r = try await api.request("contests.list", ["offset":more ? events.count : 0,"year":archived ? year : 0,"type":archived ? typeFilter : "","_fresh":fresh]); try Task.checkCancellation()
        if let time = r.serverTime.flatMap(NativeContest.date) { serverOffset = time.timeIntervalSinceNow }; self.more = (r.contests?.count ?? 0)>20
        events = (more ? events : []) + Array((r.contests ?? []).prefix(20))
        if page == "events", let event = events.first(where: { !["ended","cancelled","draft"].contains($0.state) }) ?? events.first(where: { $0.state == "ended" }) { try await open(event.id, fresh: fresh) }
    }
    private func open(_ id: String, fresh: Bool = false) async throws { let r = try await api.request("contests.get", ["contestId":id,"_fresh":fresh]); try Task.checkCancellation(); selected = r.contest; selectedWork = nil; winnersOnly = false; if let time = r.serverTime.flatMap(NativeContest.date) { serverOffset = time.timeIntervalSinceNow }; votesUsed = r.votesUsed ?? 0; mine = r.myEntries ?? []; try await wall(fresh: fresh); if r.myEntries == nil && selected?.phase(at: now) == "submitting" { mine = try await api.request("contests.entries", ["contestId":id,"seed":seed,"mine":true]).entries?.filter { $0.status == "approved" } ?? [] } }
    private func wall(more: Bool = false, fresh: Bool = false) async throws { guard let selected else { return }; let r = try await api.request("contests.entries", ["contestId":selected.id,"seed":seed,"offset":0,"afterId":more ? entries.last?.id as Any? ?? NSNull() : NSNull(),"winnersOnly":winnersOnly,"_fresh":fresh]); try Task.checkCancellation(); self.more = (r.entries?.count ?? 0)>20; entries = (more ? entries : []) + Array((r.entries ?? []).prefix(20)) }
}

private struct ContestResultCeremony: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "trophy.fill").font(.system(size: 30, weight: .medium)).foregroundStyle(TreeholeTheme.primary)
                .frame(width: 64, height: 64).background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text("本届结果已公布").font(.headline)
                Text("获奖作品与赛事荣誉已归档").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(18).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 20))
            .opacity(appeared ? 1 : 0).scaleEffect(appeared ? 1 : 0.96)
            .accessibilityElement(children: .combine)
            .onAppear {
                if reduceMotion { appeared = true }
                else { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
            }
            .onChange(of: reduceMotion) { enabled in if enabled { appeared = true } }
    }
}
