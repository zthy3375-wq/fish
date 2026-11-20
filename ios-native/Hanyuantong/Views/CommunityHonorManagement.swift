import SwiftUI

struct CampusHonorDefinition: Decodable, Identifiable {
    let id: String, code: String, name: String, category: String, rarity: String, mode: String
    let criteria: String?, defaultStory: String?
    let year: Int?, capacity: Int?
    let archived: Bool
    let issued: Int
    var caption: String { year.map { String($0) + " · " + name } ?? name }
}

struct CampusHonorRecipient: Decodable, Identifiable {
    let id: String, nickname: String
    let customTitle: String?
}

struct CampusHonorGrant: Decodable, Identifiable {
    let id: String, name: String, at: String
    let year: Int?, revoked: String?, evidence: String?
}

struct CampusHonorAudit: Decodable, Identifiable {
    let id: String, operation: String, outcome: String, at: String
    let nickname: String?, reason: String?, evidence: String?

    var label: String {
        ["save":"保存定义", "archive":"封存年度", "title":"设置称号", "grant":"授予荣誉",
         "auto_grant":"自动发放", "revoke":"撤销荣誉"][operation] ?? operation
    }
}

private struct HonorDefinitionDraft: Identifiable {
    let id = UUID()
    let definition: CampusHonorDefinition?
    var code: String, name: String, category: String, rarity: String, criteria: String, story: String
    var year: Int
    var capacity: String
    var reason = ""

    init(_ source: CampusHonorDefinition? = nil) {
        definition = source?.mode == "review" ? source : nil
        code = source?.code ?? ""
        name = source?.name ?? ""
        category = source?.category ?? "contribution"
        rarity = source?.rarity ?? "rare"
        criteria = source?.criteria ?? ""
        story = source?.defaultStory ?? ""
        year = source?.year ?? Calendar.current.component(.year, from: .now)
        capacity = source.flatMap { $0.capacity }.map { String($0) } ?? ""
    }

    var payload: [String: Any] {
        var values: [String: Any] = ["operation":"save", "name":name, "criteria":criteria, "story":story, "reason":reason]
        if let limit = Int(capacity), limit > 0 { values["capacity"] = limit }
        if let definition { values["definitionId"] = definition.id }
        else {
            values["code"] = category == "limited" && !code.hasSuffix("-\(year)") ? code + "-\(year)" : code
            values["category"] = category
            values["rarity"] = rarity
            if category == "limited" { values["year"] = year }
        }
        return values
    }
}

struct CampusHonorManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tree: TreeholeStore
    @State private var segment = "definitions"
    @State private var definitions: [CampusHonorDefinition] = []
    @State private var recipients: [CampusHonorRecipient] = []
    @State private var grants: [CampusHonorGrant] = []
    @State private var audit: [CampusHonorAudit] = []
    @State private var recipient: CampusHonorRecipient?
    @State private var query = ""
    @State private var title = ""
    @State private var definitionId = ""
    @State private var evidence = ""
    @State private var story = ""
    @State private var reason = ""
    @State private var exceptions = false
    @State private var definitionOffset = 0
    @State private var grantOffset = 0
    @State private var auditOffset = 0
    @State private var editing: HonorDefinitionDraft?
    @State private var draftSubmission: [String: Any]?
    @State private var pending: [String: Any]?
    @State private var confirm = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("荣誉管理", selection: $segment) {
                    Text("荣誉与年度").tag("definitions")
                    Text("授予与称号").tag("grants")
                    Text("发放记录").tag("audit")
                }.pickerStyle(.segmented)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button(pending == nil ? "刷新" : "重试上次提交") {
                        if pending == nil { Task { await load() } } else { confirm = true }
                    }
                }
                if let notice { Text(notice).font(.footnote) }
                if busy { ProgressView() }
                switch segment {
                case "grants": recipientSections
                case "audit": auditSection
                default: definitionSection
                }
            }
            .disabled(busy)
            .navigationTitle("社区荣誉管理").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing, onDismiss: finishEditing) { draft in
                CampusHonorDefinitionForm(draft: draft) { body in
                    draftSubmission = body
                    editing = nil
                }
            }
            .confirmationDialog("确认保存荣誉操作？", isPresented: $confirm, titleVisibility: .visible) {
                Button("确认执行") { Task { await submit() } }
                Button("取消", role: .cancel) { pending = nil }
            }
        }.task { await load() }
    }

    private var definitionSection: some View {
        Section {
            Button("创建荣誉") { editing = HonorDefinitionDraft() }
            ForEach(definitions.prefix(100)) { definition in
                VStack(alignment: .leading, spacing: 5) {
                    Text(definition.caption).font(.headline)
                    Text(definition.archived ? "已绝版" : "已发 \(definition.issued)")
                        .font(.caption).foregroundStyle(.secondary)
                    if definition.mode == "template" {
                        Button("创建年度版本") { editing = HonorDefinitionDraft(definition) }
                    } else if definition.mode == "review" && !definition.archived {
                        Button("编辑") { editing = HonorDefinitionDraft(definition) }
                    }
                    if definition.year != nil && !definition.archived {
                        Button("封存", role: .destructive) {
                            queue(["operation":"archive","definitionId":definition.id,"reason":"确认封存年度版本"])
                        }
                    }
                }.buttonStyle(.borderless)
            }
            if definitionOffset > 0 { Button("上一页定义") { definitionOffset -= 100; Task { await load() } } }
            if definitions.count > 100 { Button("下一页定义") { definitionOffset += 100; Task { await load() } } }
        }
    }

    @ViewBuilder private var recipientSections: some View {
        Section("查找成员") {
            TextField("完整昵称或成员 ID", text: $query)
            Button("搜索") { Task { await load() } }
            ForEach(recipients) { person in
                Button(person.nickname + " · " + String(person.id.prefix(8))) {
                    recipient = person; title = person.customTitle ?? ""; grantOffset = 0
                    Task { await load() }
                }
            }
        }
        if let recipient {
            Section(recipient.nickname) {
                Picker("待授荣誉", selection: $definitionId) {
                    Text("选择荣誉").tag("")
                    ForEach(definitions.filter { $0.mode == "review" && !$0.archived }) { entry in
                        Text(entry.caption).tag(entry.id)
                    }
                }
                TextField("审核依据，仅开发者可见", text: $evidence, axis: .vertical)
                TextField("公开事迹", text: $story, axis: .vertical)
                TextField("管理原因", text: $reason)
                Button("授予荣誉") {
                    queue(["operation":"grant","definitionId":definitionId,"memberId":recipient.id,
                           "evidence":evidence,"story":story,"reason":reason])
                }.disabled(definitionId.isEmpty || evidence.isEmpty || story.isEmpty || reason.isEmpty)
                TextField("专属称号（留空清除）", text: $title)
                Button("保存称号") {
                    queue(["operation":"title","reason":"管理专属称号","memberId":recipient.id,"title":title])
                }
            }
            Section("授予记录") {
                ForEach(grants.prefix(50)) { grant in
                    VStack(alignment: .leading) {
                        Text(grant.year.map { String($0) + " · " + grant.name } ?? grant.name).font(.headline)
                        Text(String(grant.at.prefix(10)) + (grant.revoked == nil ? " · 有效" : " · 已撤销")).font(.caption)
                        if let evidence = grant.evidence { Text(evidence).font(.footnote) }
                        if grant.revoked == nil {
                            Button("撤销", role: .destructive) {
                                queue(["operation":"revoke","awardId":grant.id,"reason":"开发者复核后撤销"])
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                if grantOffset > 0 { Button("上一页授予") { grantOffset -= 50; Task { await load() } } }
                if grants.count > 50 { Button("下一页授予") { grantOffset += 50; Task { await load() } } }
            }
        }
    }

    private var auditSection: some View {
        Section {
            Toggle("只查看异常发放", isOn: $exceptions).onChange(of: exceptions) { _ in auditOffset = 0; Task { await load() } }
            ForEach(audit.prefix(20)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    let result = item.outcome == "ok" ? "成功" : (TreeholeError(code: item.outcome).errorDescription ?? item.outcome)
                    Text(item.label + " · " + result).font(.headline)
                    Text([String(item.at.prefix(10)), item.nickname ?? "", item.reason ?? ""].joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let evidence = item.evidence { Text(evidence).font(.footnote) }
                }
            }
            if auditOffset > 0 { Button("上一页记录") { auditOffset -= 20; Task { await load() } } }
            if audit.count > 20 { Button("下一页记录") { auditOffset += 20; Task { await load() } } }
        }
    }

    private func fetch() async throws {
        var filters: [String: Any] = ["query":query, "exceptions":exceptions,"offset":auditOffset,
                                      "definitionOffset":definitionOffset,"grantOffset":grantOffset]
        if let recipient { filters["memberId"] = recipient.id }
        let response = try await tree.api.request("collection.admin", filters)
        definitions = response.honorDefinitions ?? []
        recipients = response.honorMembers ?? []
        grants = response.honorGrants ?? []
        audit = response.honorAudit ?? []
    }

    private func load() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await fetch() }
        catch { self.error = error.localizedDescription }
    }

    private func finishEditing() {
        guard let draftSubmission else { return }
        self.draftSubmission = nil
        queue(draftSubmission)
    }

    private func queue(_ action: [String: Any]) {
        pending = action.merging(["requestId": UUID().uuidString.lowercased()]) { old, _ in old }
        confirm = true
    }

    private func submit() async {
        guard !busy, let pending else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do {
            _ = try await tree.api.request("collection.change", pending)
            self.pending = nil
            tree.clearHonorCollectionCache()
            notice = "操作已保存"
            try await fetch()
        } catch { self.error = error.localizedDescription }
    }
}

private struct CampusHonorDefinitionForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: HonorDefinitionDraft
    let save: ([String: Any]) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("编号（英文、数字或短横线）", text: $draft.code).textInputAutocapitalization(.never)
                    .disabled(draft.definition != nil)
                TextField("名称", text: $draft.name)
                Picker("分类", selection: $draft.category) {
                    ForEach(campusHonorCategories) { Text($0.label).tag($0.id) }
                }.disabled(draft.definition != nil)
                Picker("稀有度", selection: $draft.rarity) {
                    ForEach(campusHonorRarities) { Text($0.label).tag($0.id) }
                }.disabled(draft.definition != nil)
                if draft.category == "limited" {
                    Stepper("年份 \(String(draft.year))", value: $draft.year, in: 2020...(Calendar.current.component(.year, from: .now) + 1))
                        .disabled(draft.definition != nil)
                }
                TextField("发放数量（留空为不限）", text: $draft.capacity).keyboardType(.numberPad)
                TextField("获取条件", text: $draft.criteria, axis: .vertical)
                TextField("默认事迹", text: $draft.story, axis: .vertical)
                TextField("管理原因", text: $draft.reason, axis: .vertical)
            }
            .navigationTitle("荣誉定义").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("核对并保存") { save(draft.payload) }
                        .disabled([draft.code,draft.name,draft.criteria,draft.story,draft.reason].contains(where: \.isEmpty))
                }
            }
        }
    }
}
