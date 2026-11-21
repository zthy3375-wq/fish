import SwiftUI

struct NativeRegisteredMember: Decodable, Identifiable {
    let id: String
    let username: String
    let nickname: String
}

struct NativeMemberDirectory: View {
    @EnvironmentObject private var tree: TreeholeStore
    let viewer: String
    @State private var input = ""
    @State private var query = ""
    @State private var members: [NativeRegisteredMember] = []
    @State private var next: [String: String]?
    @State private var count: Int?
    @State private var loading = false
    @State private var issue: String?
    @State private var retryingPage = false

    var body: some View {
        List {
            if tree.user?.id == viewer {
                Section("注册用户总数") {
                    if let count { Text(count.formatted()).font(.title2.monospacedDigit()) }
                    Text("不含已注销账号").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    TextField("搜索账号或昵称", text: $input).submitLabel(.search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(search)
                    Button("搜索", action: search).disabled(loading)
                }
                Section("注册成员") {
                    ForEach(members) { member in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.nickname)
                            Text(member.username).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if loading { ProgressView("正在读取成员…") }
                    else if let issue {
                        Text(issue).foregroundStyle(.secondary)
                        Button("重试") { Task { await load(append: retryingPage) } }
                    } else if members.isEmpty { Text(query.isEmpty ? "还没有注册成员" : "没有找到匹配的成员") }
                    else if next != nil { Button("加载更多") { Task { await load(append: true) } } }
                }
            }
        }
        .navigationTitle("注册成员列表").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: tree.user?.id) { _ in members = []; count = nil; next = nil }
    }

    private func search() {
        guard !loading else { return }
        query = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        Task { await load() }
    }

    @MainActor private func load(append: Bool = false) async {
        guard !loading, tree.user?.id == viewer, !append || next != nil else { return }
        loading = true; issue = nil; retryingPage = append
        defer { loading = false }
        if !append { members = []; next = nil }
        var fields = append ? next ?? [:] : [:]
        fields["query"] = query
        do {
            let result = try await tree.api.request("admin.members", fields)
            guard !Task.isCancelled, tree.user?.id == viewer else { return }
            guard let page = result.registeredMembers else { throw TreeholeError(code: "invalid_response") }
            var seen = Set(members.map(\.id))
            members += page.filter { seen.insert($0.id).inserted }
            next = result.next
            if let total = result.registeredMemberCount { count = total }
        } catch {
            guard !Task.isCancelled, tree.user?.id == viewer else { return }
            let code = (error as? TreeholeError)?.code
            if code == "session_expired" { tree.clear(); return }
            if code == "forbidden" { members = []; count = nil; next = nil }
            issue = code == "not_found" ? "当前社区后台尚未启用注册成员列表。" : error.localizedDescription
        }
    }
}
