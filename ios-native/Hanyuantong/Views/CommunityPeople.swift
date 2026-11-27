import SwiftUI

struct NativeSocialCounts:Decodable { let followingCount,followerCount:Int }

struct ProfileSocialBar:View {
    @EnvironmentObject var tree:TreeholeStore
    let member:TreeholeMember
    let following:()->Void
    let open:(String)->Void
    @State private var counts:NativeSocialCounts?
    var body:some View {
        HStack(spacing:4) {
            if tree.followingEnabled {
                Button(action:following) { metric("关注",counts?.followingCount) }
                NavigationLink { CommunityFollowers(viewer:member.id,open:open) } label: { metric("粉丝",counts?.followerCount) }
            }
            if tree.messagesEnabled { NavigationLink { NativeMessages(viewer:member.id) } label: { metric("未读私信",tree.messageUnread) } }
        }.buttonStyle(.plain).task(id:member.id) {
            guard tree.followingEnabled else{return}
            if let data=try? await tree.api.request("follows.stats"), tree.user?.id == member.id { counts=data.social }
        }
    }
    private func metric(_ name:String,_ value:Int?)->some View {
        VStack(spacing:4) { Text(value.map{String($0)} ?? "—").font(.headline.monospacedDigit());Text(name).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth:.infinity,minHeight:48).accessibilityElement(children:.combine)
    }
}

private struct CommunityFollowers:View {
    @EnvironmentObject var tree:TreeholeStore
    @Environment(\.dismiss) var dismiss
    let viewer:String
    let open:(String)->Void
    @State private var rows:[TreeholeFollow]=[]
    @State private var cursor:[String:String]?
    @State private var busy=false
    @State private var error:String?
    var body:some View {
        List {
            if busy { ProgressView() }
            if let error { Text(error); Button("重试") { Task { await load(more:!rows.isEmpty && cursor != nil) } } }
            if !busy && rows.isEmpty && error == nil { Text("还没有粉丝").foregroundStyle(.secondary) }
            ForEach(rows) { row in Button { dismiss(); open(row.id) } label: {
                HStack { TreeholeAvatar(name:row.nickname,avatar:row.avatar,size:38); Text(row.nickname) }
            } }
            if cursor != nil { Button("更多粉丝") { Task { await load(more:true) } }.disabled(busy) }
        }.navigationTitle("粉丝").refreshable { await load() }.task(id:viewer) { await load() }
    }
    @MainActor private func load(more:Bool=false) async {
        guard !busy,tree.user?.id == viewer else{return}; busy=true;error=nil; defer{busy=false}
        do {let r=try await tree.api.request("followers.list",more ? cursor ?? [:] : [:])
            guard tree.user?.id == viewer,!Task.isCancelled else{return}
            let fresh=r.followers ?? []
            rows=more ? rows + fresh.filter{ item in !rows.contains(where:{$0.id == item.id}) } : fresh; cursor=r.next
        }catch{self.error=error.localizedDescription}
    }
}
