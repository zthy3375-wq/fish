import SwiftUI

struct ContestManagementView: View {
    let api: TreeholeService
    @State var event: NativeContest
    let persisted: Bool
    var backendSchema: Int = 13
    let saved: (String) -> Void
    @State private var busy = false, editing = false, custom = false, automaticTimes = true
    @State private var error: String?, notice: String?
    @State private var reason = "", operation: String?
    @State private var durationDays = 7, reportOffset = 0
    @State private var reportMore = false
    @State private var report = TreeholeEnvelope()
    @State private var requestID = UUID().uuidString, publicationID = UUID().uuidString
    @State private var pendingSave: [String: Any]?
    private let formatter = ISO8601DateFormatter()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(persisted && !editing ? "赛事管理中心" : persisted ? "编辑赛事" : "发起一场校园比赛").font(.title2.bold())
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            if let notice { Text(notice).foregroundStyle(TreeholeTheme.primary).font(.caption) }
            if !persisted || editing { editor }
            else { management }
            if busy { ProgressView("正在确认…") }
        }.task { if persisted { run { try await loadReport() } } else { event.startsAt = formatter.string(from: Date()); duration(7) } }
        .confirmationDialog(operationTitle, isPresented: Binding(get: { operation != nil }, set: { if !$0 { operation = nil } }), titleVisibility: .visible) {
            Button("确认处理", role: operation == "cancel" ? .destructive : nil) { confirmOperation() }
            Button("返回", role: .cancel) { operation = nil }
        } message: { Text("操作将保留审计记录。取消赛事会同步撤销本届奖项，保留作品与历史记录。") }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                TextField("赛事名称", text: $event.title)
                Text("主题与介绍").font(.caption); TextEditor(text: $event.description).frame(minHeight: 100)
                DisclosureGroup("选择赛事封面（可选）") { ContestPostPicker(api: api, imageOnly: true) { post in event.coverPostId = post.id }; if event.coverPostId != nil { Text("已选择封面").font(.caption); Button("移除封面") { event.coverPostId = nil } } }
                if !persisted {
                    Picker("比赛持续时间", selection: $durationDays) { Text("3天").tag(3); Text("7天").tag(7); Text("14天").tag(14); Text("自定义").tag(0) }.pickerStyle(.segmented).onChange(of: durationDays) { days in if days > 0 { duration(days) } }
                    if durationDays == 0 { Stepper("自定义天数 \(customDays)", value: $customDays, in: 1...365).onChange(of: customDays) { duration($0) } }
                }
                ForEach(["text","image","mixed"], id: \.self) { kind in Toggle(["text":"允许文字","image":"允许图片","mixed":"允许图文"][kind]!, isOn: Binding(get: { event.formats.contains(kind) }, set: { enabled in event.formats.removeAll { $0 == kind }; if enabled { event.formats.append(kind) } })) }
                VStack(alignment: .leading, spacing: 7) { Text("日程预览 · 北京时间").font(.headline); Text("投稿截止 · " + display(event.submissionEnds)); Text("投票截止 · " + display(event.votingEnds)); Text("公布时间 · " + display(event.awardAt)) }.font(.caption).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 12))
                DisclosureGroup("高级设置") {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("赛事类型，可自定义", text: $event.type); TextField("届次（可选）", text: $event.edition)
                        TextEditor(text: $event.rules).frame(minHeight: 120).accessibilityLabel("投稿规则")
                        Stepper("每人作品 \(event.maxEntries)", value: $event.maxEntries, in: 1...10)
                        Stepper("每人票数 \(event.votesPerUser)", value: $event.votesPerUser, in: 1...10)
                        Stepper("前三最低作品数 \(event.minEntries)", value: $event.minEntries, in: 1...1000)
                        Stepper("优秀名次数量 \(event.excellence)", value: $event.excellence, in: 0...30)
                        Stepper("投票开始前注册满 \(event.minAccountHours) 小时，0不限制", value: $event.minAccountHours, in: 0...8760)
                        DatePicker("投稿开始", selection: date(\NativeContest.startsAt)); DatePicker("投稿截止", selection: date(\NativeContest.submissionEnds)); DatePicker("投票开始", selection: date(\NativeContest.votingStarts)); DatePicker("投票截止", selection: date(\NativeContest.votingEnds)); DatePicker("公布时间", selection: date(\NativeContest.awardAt))
                        Toggle("到期自动公布，无需手动颁奖", isOn: $event.autoPublish)
                        Toggle("异常票转人工复核", isOn: Binding(get: { event.reviewRisk ?? true }, set: { event.reviewRisk = $0 })).disabled(backendSchema < 14)
                    }.padding(.top, 10)
                }
            }.disabled(busy || pendingSave != nil)
            Button(busy ? "正在确认…" : pendingSave != nil ? "重试并确认" : persisted ? "保存修改" : "发布赛事") { save(publish: !persisted) }.buttonStyle(.borderedProminent).disabled(busy)
            if !persisted { Button("先保存草稿") { save(publish: false) }.disabled(busy) }
            if persisted { Button("返回管理中心") { editing = false }.disabled(busy) }
        }.environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
    }
    @State private var customDays = 7
    private var management: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.title).font(.headline); Text(event.label).foregroundStyle(TreeholeTheme.primary)
            Text("有效作品 \(event.entryCount) · \(report.metrics?["validVotes"] == nil ? "投票记录" : "有效票数") \(report.metrics?["validVotes"] ?? report.metrics?["votes"] ?? 0) · 待处理举报 \(report.metrics?["pendingReports"] ?? report.contestReports?.count ?? 0) · 异常票 \(report.metrics?["pendingRisk"] ?? 0)").font(.caption)
            TextField("处理原因（至少两个字）", text: $reason)
            if event.state == "draft" { action("publish", "发布赛事") }
            if event.state == "reviewing" { action("announce", "审核并公布结果") }
            HStack { Button("编辑日程与规则") { editing = true; automaticTimes = false }; Button("刷新统计") { run { try await loadReport() } } }.disabled(busy)
            DisclosureGroup("待处理举报") {
                ForEach(report.contestReports ?? []) { item in VStack(alignment: .leading, spacing: 8) {
                    Text(item.entry?.title ?? "作品举报").font(.headline); Text(item.reason); if let entry = item.entry { Text(entry.body); ForEach(entry.images) { image in if let url = image.url.flatMap(URL.init(string:)) { Link("查看被举报图片", destination: url) } } }
                    HStack { Button("保留作品并结案") { reviewEntry(item.entry_id, decision: "approve") }; Button("下架作品并结案", role: .destructive) { reviewEntry(item.entry_id, decision: "remove") } }.disabled(busy || reason.count < 2)
                }.padding(.vertical, 8) }
            }
            DisclosureGroup("投票复核与剔除") { ForEach(report.votes ?? []) { vote in VStack(alignment: .leading, spacing: 8) { Text(vote.risk == "vote_burst" ? "反复切票，待复核" : ["young_account","rapid_votes"].contains(vote.risk ?? "") ? "历史风险标记，可复核" : "常规投票"); Text(vote.entry_id).font(.caption2); HStack { Button("确认有效") { review(vote.id, decision: "valid") }; Button("剔除") { review(vote.id, decision: "exclude") } }.disabled(busy || reason.count < 2) }.padding(.vertical, 8) } }
            DisclosureGroup("奖励记录") { ForEach(report.awards ?? []) { award in Text((award.title ?? "主题赛事") + " · " + award.label + (award.revoked_at == nil ? " · 有效" : " · 已撤销")).font(.caption).padding(.vertical, 6) } }
            DisclosureGroup("更多赛事操作") { VStack(alignment: .leading, spacing: 12) { if !["ended","cancelled"].contains(event.state) { action(event.paused ? "resume" : "pause", event.paused ? "恢复比赛" : "暂停比赛") }; if event.state != "cancelled" { action("cancel", "取消比赛并撤销奖项") }; Button("延期：编辑具体阶段时间") { editing = true; automaticTimes = false } } }
            DisclosureGroup("操作审计") { ForEach(report.audit ?? []) { log in VStack(alignment: .leading) { Text(log.action); Text(log.reason); Text(log.created_at).foregroundStyle(.secondary) }.font(.caption).padding(.vertical, 6) } }
            if reportMore { Button("更多管理记录") { run { try await loadReport(append: true) } } }
        }
    }
    private var operationTitle: String { ["publish":"发布这场赛事？","pause":"暂停比赛？","resume":"恢复比赛？","announce":"审核并公布结果？","cancel":"取消赛事并撤销奖项？"][operation ?? ""] ?? "确认管理操作？" }
    private func action(_ action: String, _ label: String) -> some View { Button(label) { operation = action }.disabled(busy || reason.count < 2) }
    private func confirmOperation() { guard let op = operation else { return }; let nonce = UUID().uuidString; run { let r = try await api.request("contests.manage", ["contestId":event.id,"operation":op,"reason":reason,"requestId":nonce]); guard let confirmed = r.contest else { throw TreeholeError(code: "invalid_response") }; event = confirmed; operation = nil; notice = "处理已确认"; do { try await loadReport() } catch { self.error = "处理已成功，统计暂未刷新，请重试刷新。" } } }
    private func save(publish: Bool) { run {
        if pendingSave == nil { if !persisted && automaticTimes { event.startsAt = formatter.string(from: Date()); duration(durationDays == 0 ? customDays : durationDays) }; var payload = event.payload; payload["requestId"] = requestID; payload["publish"] = publish; pendingSave = payload }
        var response = try await api.request("contests.save", pendingSave!)
        if publish && response.contest?.state == "draft" { response = try await api.request("contests.manage", ["contestId":event.id,"operation":"publish","reason":"发布已确认的主题与规则","requestId":publicationID]) }
        guard let confirmed = response.contest else { throw TreeholeError(code: "invalid_response") }; event = confirmed; pendingSave = nil; saved(event.id)
    } }
    private func loadReport(append: Bool = false) async throws { var response = try await api.request("contests.admin", ["contestId":event.id,"offset":append ? reportOffset+20 : 0]); reportMore = (response.votes?.count ?? 0)>20 || (response.audit?.count ?? 0)>20 || (response.awards?.count ?? 0)>20; response.votes = (append ? report.votes ?? [] : []) + Array((response.votes ?? []).prefix(20)); response.audit = (append ? report.audit ?? [] : []) + Array((response.audit ?? []).prefix(20)); response.awards = (append ? report.awards ?? [] : []) + Array((response.awards ?? []).prefix(20)); reportOffset = append ? reportOffset+20 : 0; report = response }
    private func reviewEntry(_ id: String, decision: String) { reviewRequest("entry", id, decision) }
    private func review(_ id: String, decision: String) { reviewRequest("vote", id, decision) }
    private func reviewRequest(_ kind: String, _ id: String, _ decision: String) { run { let response = try await api.request("contests.review", ["contestId":event.id,"kind":kind,"targetId":id,"decision":decision,"reason":reason,"requestId":UUID().uuidString]); if let confirmed = response.contest { event = confirmed }; notice = "审核已确认"; do { try await loadReport() } catch { self.error = "审核已成功，统计暂未刷新，请重试。" } } }
    private func date(_ key: WritableKeyPath<NativeContest,String>) -> Binding<Date> { Binding(get: { NativeContest.date(event[keyPath:key]) ?? Date() }, set: { automaticTimes = false; event[keyPath:key] = formatter.string(from: $0) }) }
    private func duration(_ days: Int) { let start = NativeContest.date(event.startsAt) ?? Date(); event.submissionEnds = formatter.string(from: start.addingTimeInterval(Double(days)*86400*5/7)); event.votingStarts = event.submissionEnds; event.votingEnds = formatter.string(from: start.addingTimeInterval(Double(days)*86400*6/7)); event.awardAt = formatter.string(from: start.addingTimeInterval(Double(days)*86400)); automaticTimes = true }
    private func display(_ value: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier:"zh_CN"); f.timeZone = TimeZone(identifier:"Asia/Shanghai"); f.dateFormat = "M月d日 HH:mm"; return NativeContest.date(value).map(f.string) ?? value }
    private func run(_ work: @escaping () async throws -> Void) { Task { guard !busy else { return }; busy = true; error = nil; defer { busy = false }; do { try await work() } catch { if let e = error as? TreeholeError, ["invalid_request","contest_conflict","contest_rules_locked","contest_closed"].contains(e.code) { pendingSave = nil }; self.error = (error as? TreeholeError)?.errorDescription ?? "操作结果尚未确认，请重试；内容已保留。" } } }
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
    @State private var expanded = false
    private var shownAwards: [NativeContestAward] { if expanded { return result.awards ?? [] }; if let worn = (result.awards ?? []).first(where: { $0.id == result.worn }) { return [worn] }; return Array((result.awards ?? []).prefix(1)) }
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("赛事荣誉", systemImage: "trophy").font(.headline)
            if let stats = result.stats { Text("参赛 \(stats.participations) · 冠军 \(stats.champions) · 前三 \(stats.podiums)").font(.caption) }
            ForEach(shownAwards) { award in
                Button { if let id = award.contest_id { open(id) } } label: {
                    HStack { Image(systemName: "medal"); Text((award.title ?? "主题赛事") + " · " + award.label); if result.worn == award.id { Image(systemName: "checkmark.seal.fill") } }.font(.caption)
                }
            }
            if !expanded { Button("查看赛事荣誉收藏") { expanded = true } }
            if more && expanded { Button("更多赛事荣誉") { Task { await load(append: true) } }.disabled(busy) }
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
