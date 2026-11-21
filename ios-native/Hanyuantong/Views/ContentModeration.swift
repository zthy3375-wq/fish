import SwiftUI

struct ContentModeration:View {
    let postID:String
    let commentID:String?
    let locked:Bool
    let viewer:String
    let finished:()->Void
    @EnvironmentObject var tree:TreeholeStore
    @Environment(\.dismiss) var dismiss
    @State private var decision="remove"
    @State private var reason=""
    @State private var requestID=UUID()
    @State private var confirm=false
    @State private var busy=false
    @State private var error:String?
    var body:some View {
        CampusNavigation {
            Form {
                Picker("处理方式",selection:$decision) {
                    Text(commentID == nil ? "移除帖子" : "移除评论").tag("remove")
                    if commentID == nil { Text(locked ? "恢复回复" : "暂停回复").tag(locked ? "unlock" : "lock") }
                }
                TextField("处理原因（2 至 300 字）",text:$reason)
                if let error { Text(error).font(.footnote) }
                Button("核对处理",role:.destructive) { confirm=true }.disabled(reason.trimmingCharacters(in:.whitespacesAndNewlines).count < 2 || reason.count>300)
            }.navigationTitle("内容管理").disabled(busy).interactiveDismissDisabled(busy)
            .toolbar { Button("取消") { dismiss() }.disabled(busy) }
            .onChange(of:decision) { _ in requestID=UUID() }.onChange(of:reason) { _ in requestID=UUID() }
            .confirmationDialog("提交本次处理并写入审计记录？",isPresented:$confirm) { Button("确认处理",role:.destructive) { Task { await apply() } } }
        }
    }
    @MainActor private func apply() async {
        guard !busy,let me=tree.user,me.id == viewer,me.permits("content") else { return }
        busy=true; defer { busy=false }
        var body:[String:Any]=["postId":postID,"decision":decision,"reason":reason,"requestId":requestID.uuidString]
        if let commentID { body["commentId"]=commentID }
        do { _=try await tree.api.request("admin.action",body)
            guard tree.user?.id == viewer else { return }; tree.feedNeedsRefresh=true; dismiss(); finished()
        } catch { self.error=error.localizedDescription }
    }
}

struct ModerationRecord:Decodable,Identifiable {
    let id,action,reason,createdAt:String
    let postId,commentId:String?
}
struct ModerationBrowser:View {
    @EnvironmentObject var tree:TreeholeStore
    let viewer:String
    @State private var tab=0
    @State private var query=""
    @State private var posts:[TreeholePost]=[]
    @State private var events:[ModerationRecord]=[]
    @State private var next:[String:String]?
    @State private var busy=false
    @State private var error:String?
    @State private var context:TreeholePost?
    @State private var contextComments:[TreeholeComment]=[]
    @State private var revision=0
    var body:some View {
        List {
            Picker("管理范围",selection:$tab) { Text("内容").tag(0); Text("操作记录").tag(1) }.pickerStyle(.segmented)
            if tab == 0 { HStack { TextField("搜索帖子",text:$query);Button("搜索") { Task{await load()} }.disabled(busy) } }
            if busy { ProgressView() }
            if let error { Text(error);Button("重试"){Task{await load()}} }
            if tab == 0 {
                ForEach(posts){p in Button { Task{await read(p.id)} } label:{
                    VStack(alignment:.leading){ Text(p.title?.isEmpty == false ? p.title! : p.author.name).font(.headline);Text(p.body).lineLimit(3) }
                } }
            } else {
                ForEach(events){e in VStack(alignment:.leading) {
                    Text(["remove":"移除内容","lock":"暂停回复","unlock":"恢复回复","ban":"禁言","dismiss":"结案"][e.action] ?? e.action)
                    Text(e.reason);Text(TreeholePresentation.date(e.createdAt)).font(.caption).foregroundStyle(.secondary)
                } }
            }
            if next != nil { Button("更多"){ Task{await load(more:true)} }.disabled(busy) }
            if !busy && error == nil && (tab == 0 ? posts.isEmpty : events.isEmpty) { Text("暂无记录").foregroundStyle(.secondary) }
        }.navigationTitle("内容与审计").task(id:tab){ await load() }
        .sheet(item:$context){ p in CampusNavigation {
            List { Text(p.body);ForEach(contextComments){ c in Text(c.displayBody) }
                NavigationLink("处理这篇帖子"){ ContentModeration(postID:p.id,commentID:nil,locked:p.locked,viewer:viewer){context=nil; Task{await load()}} }
            }.navigationTitle("帖子上下文").toolbar { Button("关闭"){context=nil} }
        } }
    }
    @MainActor private func read(_ id:String) async {
        guard !busy,tree.user?.id == viewer else{return}; busy=true; defer{busy=false}
        do {let r=try await tree.api.request("admin.context",["postId":id]); guard tree.user?.id == viewer else{return}
            if let p=r.post { contextComments=r.comments ?? []; context=p } else {error="原帖已移除"}
        }catch{self.error=error.localizedDescription}
    }
    @MainActor private func load(more:Bool=false) async {
        guard tree.user?.id == viewer else{return};revision+=1;let version=revision;let page=tab
        busy=true;error=nil
        if !more {posts=[];events=[];next=nil}
        defer{if revision == version {busy=false}}
        var body=more ? next ?? [:] : [:]
        if page == 0 {body["query"]=query.trimmingCharacters(in:.whitespacesAndNewlines)}
        do {
            let r=try await tree.api.request(page == 0 ? "admin.content" : "admin.history",body)
            guard version == revision,tree.user?.id == viewer else{return}
            if page == 0 {
                let fresh=r.posts ?? []; posts += fresh.filter{p in !posts.contains(where:{$0.id == p.id})}
                next=fresh.count == 20 ? fresh.last.map{["beforeId":$0.id,"beforeTime":$0.createdAt]} : nil
            }else{
                let fresh=r.history ?? []; events += fresh.filter{e in !events.contains(where:{$0.id == e.id})}
                next=fresh.count == 30 ? fresh.last.map{["beforeId":$0.id,"beforeTime":$0.createdAt]} : nil
            }
        }catch{if revision == version {self.error=error.localizedDescription}}
    }
}
