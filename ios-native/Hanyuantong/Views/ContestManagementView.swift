import SwiftUI

struct ContestManagementView: View {
    let api: TreeholeService
    @State var event: NativeContest
    let persisted: Bool
    let saved: (String) -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var reason = ""
    @State private var reportOffset = 0
    @State private var reportMore = false
    @State private var report = TreeholeEnvelope()
    private let formatter = ISO8601DateFormatter()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("赛事管理").font(.title2.bold())
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            TextField("名称", text: $event.title); TextField("类型，可自定义", text: $event.type); TextField("届次", text: $event.edition)
            Text("主题描述").font(.caption); TextEditor(text: $event.description).frame(height: 90)
            Text("投稿规则").font(.caption); TextEditor(text: $event.rules).frame(height: 120)
            ContestPostPicker(api: api, imageOnly: true) { post in event.coverPostId = post.id }
            TextField("封面原帖 ID（选填）", text: Binding(get: { event.coverPostId ?? "" }, set: { event.coverPostId = $0.isEmpty ? nil : $0 }))
            Menu("设置赛事周期") { ForEach([1,3,7,14,30], id: \.self) { days in Button("\(days) 天") { duration(days) } } }
            DatePicker("投稿开始", selection: date(\NativeContest.startsAt))
            DatePicker("投稿截止", selection: date(\NativeContest.submissionEnds))
            DatePicker("投票开始", selection: date(\NativeContest.votingStarts))
            DatePicker("投票截止", selection: date(\NativeContest.votingEnds))
            DatePicker("公布时间", selection: date(\NativeContest.awardAt))
            ForEach(["text", "image", "mixed"], id: \.self) { kind in Toggle(["text":"允许文字", "image":"允许图片", "mixed":"允许图文"][kind]!, isOn: Binding(get: { event.formats.contains(kind) }, set: { value in event.formats.removeAll { $0 == kind }; if value { event.formats.append(kind) } })) }
            Stepper("每人作品 \(event.maxEntries)", value: $event.maxEntries, in: 1...10)
            Stepper("每人票数 \(event.votesPerUser)", value: $event.votesPerUser, in: 1...10)
            Stepper("前三最低作品数 \(event.minEntries)", value: $event.minEntries, in: 1...1000)
            Stepper("优秀名次数量 \(event.excellence)", value: $event.excellence, in: 0...30)
            Stepper("投票开始前注册满 \(event.minAccountHours) 小时", value: $event.minAccountHours, in: 0...8760)
            Toggle("到期自动结算，异常票转人工复核", isOn: $event.autoPublish)
            Button("保存赛事") { run { _ = try await api.request("contests.save", event.payload); saved(event.id) } }.buttonStyle(.borderedProminent)
            if persisted {
                TextField("管理操作理由", text: $reason)
                ForEach(["publish", "pause", "resume", "announce", "cancel"], id: \.self) { action in Button(["publish":"发布赛事", "pause":"暂停", "resume":"恢复", "announce":"审核并公布", "cancel":"取消赛事"][action]!) { run { _ = try await api.request("contests.manage", ["contestId":event.id, "operation":action, "reason":reason]); saved(event.id) } }.disabled(reason.count < 2) }
                Button("开启主题征集") { manageThemes(true) }.disabled(reason.count < 2)
                Button("结束主题征集") { manageThemes(false) }.disabled(reason.count < 2)
                Button("刷新数据与风险票") { run { try await loadReport() } }
                ForEach((report.metrics ?? [:]).keys.sorted(), id: \.self) { key in Text("\(["votes":"投票记录", "entries":"投稿记录", "images":"图片资源", "pendingRisk":"待复核票"][key] ?? key) · \(report.metrics?[key] ?? 0)").font(.caption) }
                ForEach(report.contestReports ?? []) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("作品举报").font(.headline); Text(item.reason)
                        if let entry = item.entry { Text(entry.title).font(.headline); Text(entry.body); ForEach(entry.images) { image in if let url = image.url.flatMap(URL.init(string:)) { Link("查看被举报图片", destination: url) } } }
                        HStack { Button("保留作品并结案") { reviewEntry(item.entry_id, decision: "approve") }; Button("下架作品并结案") { reviewEntry(item.entry_id, decision: "remove") } }.disabled(reason.count < 2)
                    }
                }
                ForEach(report.awards ?? []) { award in VStack(alignment: .leading) { Text((award.title ?? "主题赛事") + " · " + award.label); Text(award.revoked_at == nil ? "有效" : "已撤销").font(.caption) } }
                ForEach(report.votes ?? []) { vote in VStack(alignment: .leading, spacing: 7) { Text(vote.risk == nil ? "常规投票" : "疑似异常票，请复核"); Text(vote.entry_id).font(.caption2); HStack { Button("确认有效") { review(vote.id, decision: "valid") }; Button("剔除") { review(vote.id, decision: "exclude") } }.disabled(reason.count < 2) } }
                ForEach(report.audit ?? []) { log in VStack(alignment: .leading) { Text(log.action); Text(log.reason).font(.caption); Text(log.created_at).font(.caption2).foregroundStyle(.secondary) } }
                if reportMore { Button("更多投票与记录") { run { try await loadReport(append: true) } } }
            }
        }.disabled(busy)
    }
    private func loadReport(append: Bool = false) async throws {
        var response = try await api.request("contests.admin", ["contestId":event.id, "offset":append ? reportOffset + 20 : 0])
        reportMore = (response.votes?.count ?? 0)>20 || (response.audit?.count ?? 0)>20 || (response.awards?.count ?? 0)>20
        response.votes = (append ? report.votes ?? [] : []) + Array((response.votes ?? []).prefix(20))
        response.audit = (append ? report.audit ?? [] : []) + Array((response.audit ?? []).prefix(20))
        response.awards = (append ? report.awards ?? [] : []) + Array((response.awards ?? []).prefix(20))
        reportOffset = append ? reportOffset + 20 : 0; report = response
    }
    private func reviewEntry(_ id: String, decision: String) { run {
        _ = try await api.request("contests.review", ["contestId":event.id, "kind":"entry", "targetId":id, "decision":decision, "reason":reason]); try await loadReport()
    } }
    private func date(_ key: WritableKeyPath<NativeContest, String>) -> Binding<Date> {
        Binding(get: { NativeContest.date(event[keyPath: key]) ?? Date() }, set: { event[keyPath: key] = formatter.string(from: $0) })
    }
    private func duration(_ days: Int) {
        let start = NativeContest.date(event.startsAt) ?? Date()
        event.submissionEnds = formatter.string(from: start.addingTimeInterval(Double(days) * 86400 * 5 / 7))
        event.votingStarts = event.submissionEnds
        event.votingEnds = formatter.string(from: start.addingTimeInterval(Double(days) * 86400 * 6 / 7))
        event.awardAt = formatter.string(from: start.addingTimeInterval(Double(days) * 86400))
    }
    private func manageThemes(_ enabled: Bool) { run { _ = try await api.request("contests.manage", ["contestId":event.id, "operation":"solicitation", "enabled":enabled, "reason":reason]) } }
    private func review(_ id: String, decision: String) { run { _ = try await api.request("contests.review", ["contestId":event.id, "kind":"vote", "targetId":id, "decision":decision, "reason":reason]); try await loadReport() } }
    private func run(_ work: @escaping () async throws -> Void) {
        Task { guard !busy else { return }; busy = true; error = nil; defer { busy = false }; do { try await work() } catch { self.error = (error as? TreeholeError)?.errorDescription ?? "操作失败，请重试" } }
    }
}

struct ContestEntryLink: View {
    let api: TreeholeService
    let open: () -> Void
    @State private var event: NativeContest?
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) { Image(systemName: "trophy").font(.title2).foregroundStyle(TreeholeTheme.primary)
                VStack(alignment: .leading, spacing: 4) { Text("主题赛事" + (event.map { " · " + $0.label } ?? "")).font(.caption).foregroundStyle(.secondary); Text(event?.title ?? "历届作品与冠军档案").font(.subheadline.weight(.semibold)); if let event { Text("\(event.participantCount) 人 · \(event.entryCount) 件作品").font(.caption2).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "chevron.right").font(.caption)
            }.padding(14).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).task { event = try? await api.request("contests.list").contests?.first }
    }
}

struct ContestProfileHonors: View {
    let api: TreeholeService
    let memberId: String
    let open: (String) -> Void
    @State private var result = TreeholeEnvelope()
    @State private var error: String?
    @State private var more = false
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("赛事荣誉", systemImage: "trophy").font(.headline)
            if let stats = result.stats { Text("参赛 \(stats.participations) · 冠军 \(stats.champions) · 前三 \(stats.podiums)").font(.caption) }
            ForEach(result.awards ?? []) { award in
                Button { if let id = award.contest_id { open(id) } } label: {
                    HStack { Image(systemName: "medal"); Text((award.title ?? "主题赛事") + " · " + award.label); if result.worn == award.id { Image(systemName: "checkmark.seal.fill") } }.font(.caption)
                }
            }
            if more { Button("更多赛事荣誉") { Task { await load(append: true) } }.disabled(busy) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary); Button("重试") { Task { await load() } }.disabled(busy) }
        }.padding(.vertical, 12).task(id: memberId) { result = TreeholeEnvelope(); await load() }
    }
    @MainActor private func load(append: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            var response = try await api.request("contests.profile", ["memberId":memberId, "offset":append ? result.awards?.count ?? 0 : 0])
            try Task.checkCancellation()
            more = (response.awards?.count ?? 0) > 20
            response.awards = (append ? result.awards ?? [] : []) + Array((response.awards ?? []).prefix(20))
            result = response
        } catch is CancellationError { } catch { self.error = "赛事荣誉暂未加载" }
    }
}

struct ContestGallery: View {
    let selection: TreeholeGallerySelection
    let api: TreeholeService
    let contestId: String
    @Environment(\.dismiss) private var dismiss
    @State private var urls: [String: URL] = [:]
    @State private var error = false
    @State private var scale: CGFloat = 1
    @State private var index = 0
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(selection.images.enumerated()), id: \.element.id) { offset, image in
                    AsyncImage(url: urls[image.id] ?? image.url.flatMap(URL.init(string:))) { loaded in loaded.resizable().scaledToFit().scaleEffect(scale).gesture(MagnificationGesture().onChanged { scale = min(4, max(1, $0)) }) } placeholder: { ProgressView().tint(.white) }.tag(offset)
                }
            }.tabViewStyle(.page).task { index = selection.index; await renew() }
            VStack { Button("关闭") { dismiss() }; if error { Button("重试") { Task { await renew() } } } }.padding(20).foregroundStyle(.white)
        }
    }
    private func renew() async {
        error = false
        do {
            for image in selection.images {
                let response = try await api.request("contests.image", ["contestId":contestId, "entryId":selection.postId, "imageId":image.id])
                if let value = response.image?.url, let url = URL(string: value) { urls[image.id] = url }
            }
        } catch { self.error = true }
    }
}
