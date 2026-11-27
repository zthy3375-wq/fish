import SwiftUI

struct NativeConversation: Decodable, Identifiable {
    struct Peer: Decodable { let id,nickname:String; let avatar:TreeholeImage? }
    let id,lastSeq,updatedAt:String
    let member:Peer
    let lastMessage:String?
    let unreadCount:Int
}
struct NativeMessage: Decodable, Identifiable {
    let id,seq,body,createdAt:String
    let mine:Bool
    let requestId:String?
}
struct NativeMessages: View {
    @EnvironmentObject var tree:TreeholeStore
    let viewer:String
    var member:String? = nil
    @State private var rows:[NativeConversation]=[]
    @State private var next:[String:String]?
    @State private var peerThread:NativeConversation?
    @State private var busy=false
    @State private var error:String?
    var body: some View {
        Group {
            if let peerThread { NativeConversationView(viewer:viewer,thread:peerThread) }
            else { List {
                if busy { ProgressView() }
                if let error { Text(error); Button("重试") { Task { await load() } } }
                if rows.isEmpty && !busy && error == nil && member == nil { Text("还没有私信，可以从同学的公开主页发起对话。").foregroundStyle(.secondary) }
                ForEach(rows) { c in
                    NavigationLink { NativeConversationView(viewer:viewer,thread:c) } label: {
                        HStack { TreeholeAvatar(name:c.member.nickname,avatar:c.member.avatar,size:40)
                            VStack(alignment:.leading) { Text(c.member.nickname).font(.headline); Text(c.lastMessage ?? "开始对话").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer(); if c.unreadCount > 0 { Text("\(c.unreadCount)").font(.caption).foregroundStyle(CampusTheme.primary) }
                        }
                    }
                }
                if next != nil { Button("更早的会话") { Task { await load(more:true) } }.disabled(busy) }
            }.refreshable { await load() }.navigationTitle("私信") }
        }.task(id:viewer) { await load() }
    }
    @MainActor private func load(more:Bool=false) async {
        guard !busy, tree.user?.id == viewer else { return }; busy=true; error=nil
        defer { busy=false }
        do {
            if let member {
                let r=try await tree.api.request("messages.open",["memberId":member])
                guard !Task.isCancelled,tree.user?.id == viewer else { return }
                guard let c=r.conversation,c.member.id == member else { throw TreeholeError(code:"invalid_response") }
                peerThread=c
            } else {
                let r=try await tree.api.request("messages.inbox",more ? next ?? [:] : [:])
                guard !Task.isCancelled,tree.user?.id == viewer else { return }
                let fresh=r.conversations ?? []
                rows=more ? rows + fresh.filter { item in !rows.contains(where:{$0.id == item.id}) } : fresh; next=r.next
            }
        } catch { if tree.user?.id == viewer { self.error=error.localizedDescription } }
    }
}
private struct NativeConversationView: View {
    @EnvironmentObject var tree:TreeholeStore
    let viewer:String
    let thread:NativeConversation
    @State private var messages:[NativeMessage]=[]
    @State private var next:[String:String]?
    @State private var draft=""
    @State private var requestID=UUID()
    @State private var busy=false
    @State private var error:String?
    @State private var blocked=false
    @State private var confirmBlock=false
    var body: some View {
        List {
            if next != nil { Button("更早的私信") { Task { await load(more:true) } }.disabled(busy) }
            ForEach(messages) { m in
                HStack { if m.mine { Spacer(minLength:30) }; VStack(alignment:m.mine ? .trailing : .leading,spacing:4) {
                    Text(m.body).textSelection(.enabled)
                    Text(TreeholePresentation.date(m.createdAt)).font(.caption2).foregroundStyle(.secondary)
                }.padding(10).background(m.mine ? CampusTheme.tint : Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                    if !m.mine { Spacer(minLength:30) }
                }.listRowSeparator(.hidden)
            }
            if messages.isEmpty && !busy && error == nil { Text("发出第一条私信").foregroundStyle(.secondary) }
            if busy { ProgressView() }
            if let error { Text(error).font(.caption); Button("重新读取") { Task { await load() } } }
        }.refreshable { await load() }.navigationTitle(thread.member.nickname)
        .safeAreaInset(edge:.bottom) { HStack {
            TextField(blocked ? "已屏蔽" : "写私信",text:$draft).textFieldStyle(.roundedBorder).disabled(busy || blocked)
                .onChange(of:draft) { _ in requestID=UUID() }
            Button("发送") { Task { await send() } }.disabled(busy || blocked || draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.count>1000)
        }.padding(10).background(.regularMaterial) }
        .toolbar { Button { confirmBlock=true } label: { Image(systemName:"hand.raised") }.accessibilityLabel("屏蔽此人").disabled(busy || blocked) }
        .confirmationDialog("屏蔽此人并停止私信？",isPresented:$confirmBlock) {
            Button("屏蔽",role:.destructive) { Task { do { _=try await tree.api.request("members.block",["memberId":thread.member.id]); blocked=true; messages=[]; draft=""; tree.didBlockPublicAuthor(thread.member.id) } catch { self.error=error.localizedDescription } } }
        }.task(id:thread.id) { await load() }
    }
    @MainActor private func load(more:Bool=false) async {
        guard !busy,tree.user?.id == viewer else { return }; busy=true; error=nil
        defer {busy=false}
        do {
            var body=more ? next ?? [:] : [:]; body["conversationId"]=thread.id
            let r=try await tree.api.request("messages.list",body)
            guard !Task.isCancelled,tree.user?.id == viewer else { return }
            let fresh=r.messages ?? []
            let existing=more ? messages : []
            messages=fresh.filter { m in !existing.contains(where:{$0.id == m.id}) } + existing; next=r.next
            if !more, let last=fresh.last, (r.conversation?.unreadCount ?? thread.unreadCount)>0 { _=try await tree.api.request("messages.read",["conversationId":thread.id,"throughSeq":last.seq]) }
        } catch { if tree.user?.id == viewer { self.error=error.localizedDescription } }
    }
    @MainActor private func send() async {
        guard !busy,tree.user?.id == viewer else { return }; busy=true; error=nil
        defer {busy=false}
        do {
            let r=try await tree.api.request("messages.send",["conversationId":thread.id,"requestId":requestID.uuidString,"body":draft.trimmingCharacters(in:.whitespacesAndNewlines)])
            guard tree.user?.id == viewer else { return }
            guard let m=r.message else { throw TreeholeError(code:"invalid_response") }
            if !messages.contains(where:{$0.id == m.id}) { messages.append(m) }; draft=""
        } catch { self.error=error.localizedDescription }
    }
}
