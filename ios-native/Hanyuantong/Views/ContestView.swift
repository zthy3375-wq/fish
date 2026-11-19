import SwiftUI
import PhotosUI

struct ContestView: View {
    let api: TreeholeService
    let user: TreeholeMember
    var initialId: String? = nil
    var initialPage: String = "events"
    var onMember: ((String) -> Void)? = nil
    var onPost: ((String) -> Void)? = nil
    @State private var events: [NativeContest] = []
    @State private var selected: NativeContest?
    @State private var entries: [NativeContestEntry] = []
    @State private var page = "events"
    @State private var busy = false
    @State private var error: String?
    @State private var serverOffset: TimeInterval = 0
    @State private var votesUsed = 0
    @State private var more = false
    @State private var seed = UUID().uuidString
    @State private var editor = false
    @State private var administration = false
    @State private var draftEvent: NativeContest?
    @State private var title = ""
    @State private var bodyText = ""
    @State private var postID = ""
    @State private var editingID: String?
    @State private var attached: [String] = []
    @State private var photos: [TreeholeDraftPhoto] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var agreed = false
    @State private var requestID = UUID().uuidString
    @State private var summary = TreeholeEnvelope()
    @State private var theme = ""
    @State private var reason = ""
    @State private var reviewingEntry = false
    @State private var restoreEntry = false
    @State private var mergeTarget = ""
    @State private var reportTarget: String?
    @State private var gallery: TreeholeGallerySelection?
    @State private var typeFilter = ""
    @State private var year = Calendar.current.component(.year, from: Date())
    private var admin: Bool { user.badges?.official?.code == "developer" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("主题赛事").font(.largeTitle.bold()); Spacer(); Button { run { try await load() } } label: { Image(systemName: "arrow.clockwise") }; if admin { Button { draftEvent = .draft(); administration = true } label: { Image(systemName: "plus") } } }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if busy { ProgressView("正在加载…") }
            if administration, let event = draftEvent {
                ContestManagementView(api: api, event: event) { id in administration = false; run { try await open(id) } }
            } else {
                Picker("赛事栏目", selection: $page) { Text("赛事").tag("events"); Text("历届").tag("archive"); Text("年度").tag("year"); Text("征集").tag("themes"); Text("荣誉").tag("honors") }.pickerStyle(.segmented).onChange(of: page) { _ in selected = nil; run { try await load() } }
                if let event = selected { detail(event) }
                else if page == "honors" { honors }
                else if page == "themes" { themes }
                else if page == "year" {
                    Stepper("\(year) 年", value: $year, in: 2020...9999).onChange(of: year) { _ in run { try await load() } }
                    Text("冠军5分、亚军3分、季军2分、优秀作品1分，同分并列。").font(.caption).foregroundStyle(.secondary)
                    ForEach(summary.leaders ?? []) { leader in HStack { Text(leader.nickname); Spacer(); Text("\(leader.score) 分") }.padding(.vertical, 8) }
                } else {
                    if page == "archive" {
                        Stepper("\(year) 年", value: $year, in: 2020...9999).onChange(of: year) { _ in run { try await load() } }
                        TextField("筛选赛事类型", text: $typeFilter).onSubmit { run { try await load() } }
                    }
                    if events.isEmpty && !busy { Text("赛事发布后会出现在这里").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24) }
                    ForEach(events) { event in Button { run { try await open(event.id) } } label: { HStack(spacing: 14) { Image(systemName: "trophy").font(.title2); VStack(alignment: .leading, spacing: 5) { Text(event.title).font(.headline); Text("\(event.label) · \(event.participantCount) 人 · \(event.entryCount) 件作品").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.padding(.vertical, 14) }.buttonStyle(.plain) }
                    if more { Button("更多赛事") { run { try await load(more: true) } } }
                }
            }
        }.sheet(item: $gallery) { selection in ContestGallery(selection: selection, api: api, contestId: selected?.id ?? "") }
        .disabled(busy).task { await perform { page = initialPage; if let initialId { try await open(initialId) } else { try await load() } } }
    }
    @ViewBuilder private func detail(_ event: NativeContest) -> some View {
        Button("返回赛事列表") { selected = nil }
        if let image = event.cover { TreeholeImageGrid(postId: event.coverPostId ?? "", images: [image], full: false, api: api) { _ in } .allowsHitTesting(false) }
        VStack(alignment: .leading, spacing: 10) { Text(event.type + " · " + event.edition).font(.caption); Text(event.title).font(.title.bold()); Text(event.label).font(.caption.weight(.semibold)); TimelineView(.periodic(from: .now, by: 60)) { context in Text(event.remaining(now: context.date.addingTimeInterval(serverOffset))).font(.caption).foregroundStyle(.secondary) }; Text(event.description).font(.body) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 16))
        DisclosureGroup("规则、日程与奖励") {
            VStack(alignment: .leading, spacing: 10) { Text(event.rules); Text("每人最多 \(event.maxEntries) 件作品、\(event.votesPerUser) 票。投票前账号注册满 \(event.minAccountHours) 小时。有效作品满 \(event.minEntries) 件，得票作品参与前三评选。同票并列，下一名次连续排列。所有有效参赛者保留纪念。"); Text("投稿截止 " + event.submissionEnds); Text("投票 " + event.votingStarts + " 至 " + event.votingEnds); Text("公布 " + event.awardAt) }.font(.caption).padding(.vertical, 8)
        }
        if event.state == "submitting" && !event.paused { Button("我要参赛") { compose() }.buttonStyle(.borderedProminent) }
        if event.state == "voting" { Text("已用 \(votesUsed) / \(event.votesPerUser) 票").font(.subheadline) }
        if event.state == "reviewing" { Label("结果统计与审核中", systemImage: "clock").font(.subheadline) }
        if event.state == "ended" { Label("获奖作品已归档", systemImage: "trophy.fill").font(.headline).foregroundStyle(TreeholeTheme.primary) }
        if admin { Button("管理本场赛事") { draftEvent = event; administration = true } }
        if editor { submission(event) }
        ForEach(entries) { entry in work(entry, event: event) }
        if more { Button("更多作品") { run { try await wall(more: true) } } }
        if reportTarget != nil {
            TextField(reviewingEntry ? "填写审核原因" : "填写举报原因", text: $reason)
            if reviewingEntry { Toggle("恢复／通过作品", isOn: $restoreEntry) }
            Button("确认提交") { run {
                if reviewingEntry { _ = try await api.request("contests.review", ["contestId":event.id, "kind":"entry", "targetId":reportTarget!, "decision":restoreEntry ? "approve" : "remove", "reason":reason]) }
                else { _ = try await api.request("contests.report", ["contestId":event.id, "entryId":reportTarget!, "reason":reason]) }
                reportTarget = nil; reason = ""; try await open(event.id)
            } }.disabled(reason.count < 2)
        }
    }
    private func work(_ entry: NativeContestEntry, event: NativeContest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entry.awards.filter { $0.kind != "participation" }) { award in Label(award.label, systemImage: "trophy.fill").font(.headline).foregroundStyle(TreeholeTheme.primary) }
            ForEach(Array(entry.images.enumerated()), id: \.element.id) { index, image in Button { gallery = TreeholeGallerySelection(postId: entry.id, images: entry.images, index: index) } label: { AsyncImage(url: image.url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFit() } placeholder: { Text("点开重试图片").font(.caption) }.frame(maxHeight: 300) }.buttonStyle(.plain) }
            Text(entry.title).font(.title3.bold()); Text(entry.body).font(.body); Button(entry.author) { onMember?(entry.memberId) }.font(.caption).foregroundStyle(.secondary)
            HStack {
                if event.state == "voting" && !event.paused && !entry.mine { Button(entry.voted ? "已投票 · 撤回" : "投一票") { run { _ = try await api.request("contests.vote", ["contestId":event.id, "entryId":entry.id, "enabled":!entry.voted]); try await open(event.id) } }.buttonStyle(.bordered) }
                if let votes = entry.votes { Text("\(votes) 票").font(.caption) }
                if entry.mine && event.state == "submitting" { Button("编辑") { compose(entry) }; Button("撤回") { run { _ = try await api.request("contests.withdraw", ["contestId":event.id, "entryId":entry.id]); try await open(event.id) } } }
                if let post = entry.postId { Button("原帖") { onPost?(post) } }; Spacer(); if admin { Button("审核") { reviewingEntry = true; restoreEntry = entry.status != "approved"; reportTarget = entry.id } } else { Button("举报") { reviewingEntry = false; reportTarget = entry.id } }
            }.font(.caption)
        }.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(TreeholeTheme.tint))
    }
    private func submission(_ event: NativeContest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("作品名称", text: $title); TextEditor(text: $bodyText).frame(minHeight: 120)
            TextField("关联自己的非匿名原帖 ID（选填）", text: $postID)
            PhotosPicker(selection: $picked, maxSelectionCount: max(1, 3 - photos.count - attached.count), matching: .images) { Label("添加图片 · 最多3张", systemImage: "photo") }.disabled(photos.count + attached.count >= 3).onChange(of: picked) { items in run { for item in items { if let bytes = try await item.loadTransferable(type: Data.self) { photos.append(try TreeholeDraftStore.prepare(bytes)) } }; picked = [] } }
            ForEach(photos) { photo in HStack { Text("已选图片"); Spacer(); Button("移除") { photos.removeAll { $0.id == photo.id } } }.font(.caption) }
            ForEach(attached, id: \.self) { image in Button("移除已附图片") { attached.removeAll { $0 == image } } }
            Toggle("我已阅读规则，拥有作品发布权", isOn: $agreed).font(.caption)
            Button("提交作品") { run {
                for photo in photos where photo.remote == nil {
                    guard let image = try await api.request("media.upload", ["data":photo.data.base64EncodedString(), "requestId":photo.id]).image, let index = photos.firstIndex(where: { $0.id == photo.id }) else { throw TreeholeError(code: "image_unavailable") }
                    photos[index].remote = image
                }
                _ = try await api.request("contests.submit", ["contestId":event.id, "entryId":editingID as Any? ?? NSNull(), "requestId":requestID, "title":title, "body":bodyText, "images":attached + photos.compactMap { $0.remote?.id }, "postId":postID.isEmpty ? NSNull() : postID as Any, "agreed":agreed]); editor = false; try await open(event.id)
            } }.disabled(!agreed || title.isEmpty).buttonStyle(.borderedProminent)
            Button("收起编辑") { editor = false }
        }.padding(16).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private var honors: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats = summary.stats { Text("参赛 \(stats.participations) · 冠军 \(stats.champions) · 前三 \(stats.podiums)").font(.headline)
                if stats.champions >= 1 { Text("初露锋芒") }; if stats.champions >= 5 { Text("常胜将军") }; if stats.champions >= 20 { Text("不败传说") }; if stats.participations >= 100 { Text("百战老兵") }; if stats.podiums >= 10 { Text("民间艺术家") }
            }
            ForEach(summary.annual ?? [], id: \.self) { year in Text("\(year) 年度赛事之王") }
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
                TextField("合并目标主题 ID（选填）", text: $mergeTarget)
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
                            Button("合并") { reviewTheme(item.id, kind: "merge", decision: "approve") }.disabled(mergeTarget.isEmpty)
                        }.disabled(reason.count < 2)
                    }
                }
            }
        }
    }
    private func reviewTheme(_ id: String, kind: String, decision: String) {
        run {
            _ = try await api.request("contests.review", ["contestId":events.first?.id as Any? ?? NSNull(), "kind":kind, "targetId":id, "decision":decision, "reason":reason, "mergeId":mergeTarget.isEmpty ? NSNull() : mergeTarget as Any])
            try await load()
        }
    }
    private func compose(_ entry: NativeContestEntry? = nil) {
        editingID = entry?.id; title = entry?.title ?? ""; bodyText = entry?.body ?? ""; postID = entry?.postId ?? ""; photos = []; attached = entry?.images.map(\.id) ?? []; agreed = false; requestID = UUID().uuidString; editor = true
    }
    private func run(_ work: @escaping () async throws -> Void) { Task { await perform(work) } }
    @MainActor private func perform(_ work: () async throws -> Void) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { try await work() } catch is CancellationError { } catch { self.error = (error as? TreeholeError)?.errorDescription ?? "连接失败，请稍后重试" }
    }
    private func load(more: Bool = false) async throws {
        if page == "honors" { summary = try await api.request("contests.profile"); return }
        if page == "themes" { summary = try await api.request("contests.themes"); return }
        if page == "year" { summary = try await api.request("contests.year", ["year":year]); return }
        let r = try await api.request("contests.list", ["offset":more ? events.count : 0, "year":page == "archive" ? year : 0, "type":typeFilter]); self.more = (r.contests?.count ?? 0) > 20
        events = more ? events + Array((r.contests ?? []).prefix(20)) : Array((r.contests ?? []).prefix(20))
    }
    private func open(_ id: String) async throws { let r = try await api.request("contests.get", ["contestId":id]); selected = r.contest; if let time = r.serverTime.flatMap(NativeContest.date) { serverOffset = time.timeIntervalSinceNow }; votesUsed = r.votesUsed ?? 0; try await wall() }
    private func wall(more: Bool = false) async throws {
        guard let selected else { return }; let r = try await api.request("contests.entries", ["contestId":selected.id, "seed":seed, "offset":more ? entries.count : 0]); self.more = (r.entries?.count ?? 0) > 20
        entries = more ? entries + Array((r.entries ?? []).prefix(20)) : Array((r.entries ?? []).prefix(20))
    }
}
