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
