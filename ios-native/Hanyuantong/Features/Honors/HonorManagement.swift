import SwiftUI

struct HonorMember: Decodable,Identifiable {
    let id,nickname:String
    let official:HonorStamp?
    let caps,honors:[String]
    let bannedUntil,recommendation:String?
}
struct HonorAudit:Decodable {
    struct Change:Decodable { let operation:String; let reason:String? }
    let at,target,actor:String
    let change:Change
}
extension TreeholeMember {
    var developer:Bool { role == "moderator" && badges?.official?.code == "developer" }
    func permits(_ cap:String)->Bool { role == "moderator" && (developer || caps?.contains(cap) == true) }
}
struct HonorManagement:View {
    @EnvironmentObject var tree:TreeholeStore
    @State private var members:[HonorMember]=[]
    @State private var log:[HonorAudit]=[]
    @State private var query=""
    @State private var busy=false
    @State private var error:String?
    @State private var selected:HonorMember?
    var body:some View {
        List {
            if let me=tree.user, me.permits("users") || me.permits("recommend") {
                HStack { TextField("昵称或用户 ID",text:$query); Button("搜索") { Task { await load() } }.disabled(busy) }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(members) { m in Button { selected=m } label: {
                    HonorByline(name:m.nickname,badges:MemberBadges(official:m.official,worn:nil)).frame(minHeight:44)
                } }
                if !busy && members.isEmpty && error == nil { Text("没有匹配的成员") }
                if !log.isEmpty { Section("授权记录") { ForEach(log.indices,id:\.self) { i in
                    let entry=log[i]; VStack(alignment:.leading) {
                        Text(entry.actor + " · " + (HonorMemberEditor.names[entry.change.operation] ?? entry.change.operation) + " · " + entry.target)
                        Text([TreeholePresentation.date(entry.at),entry.change.reason].compactMap{$0}.joined(separator:" · ")).font(.caption)
                    }
                } } }
            } else { Text("当前账号没有管理权限") }
        }.navigationTitle("身份与荣誉管理").task(id:tree.user?.id) { await load() }
         .sheet(item:$selected,onDismiss:{ Task { await load() } }) { m in
            if let me=tree.user { CampusNavigation { HonorMemberEditor(me:me,member:m) } }
         }
    }
    @MainActor private func load() async {
        guard !busy, let me=tree.user, me.permits("users") || me.permits("recommend") else { return }
        busy=true; error=nil; defer {busy=false}
        do {
            let r=try await tree.api.request("honors.manage",["query":query.trimmingCharacters(in:.whitespacesAndNewlines)])
            guard tree.user?.id == me.id else { return }
            members=r.members ?? []; log=r.audit ?? []
        } catch { self.error=error.localizedDescription }
    }
}
private struct HonorMemberEditor:View {
    static let names=["grant":"授予荣誉","revoke":"撤销荣誉","appoint":"任命或调整管理员","dismiss":"解除管理员","recommend":"推荐创作者","decline":"驳回推荐","mute":"禁言七天","unmute":"解除禁言","bind":"绑定开发者"]
    let me:TreeholeMember
    let member:HonorMember
    @EnvironmentObject var tree:TreeholeStore
    @Environment(\.dismiss) private var dismiss
    @State private var op=""
    @State private var kind=""
    @State private var caps:Set<String>=[]
    @State private var reason=""
    @State private var confirm=false
    @State private var busy=false
    @State private var error:String?
    @State private var requestID=UUID()
    private var ops:[String] {
        var result:[String]=[]
        if me.developer {
            result.append("grant")
            if member.honors.contains(where:{$0 != "seed"}) { result.append("revoke") }
            if member.recommendation != nil { result.append("decline") }
            if member.official?.code != "developer" { result.append("appoint"); if member.official?.code == "moderator" { result.append("dismiss") } }
        }
        if me.permits("recommend") && !member.honors.contains("creator") { result.append("recommend") }
        if me.permits("users") && member.id != me.id && (member.official == nil || me.developer && member.official?.code != "developer") {
            result.append((MedalDates.parse(member.bannedUntil) ?? .distantPast) > Date() ? "unmute" : "mute")
        }
        return result
    }
    private var kinds:[String] { op == "revoke" ? member.honors.filter {$0 != "seed"} : ["seed","creator","contributor"].filter { !member.honors.contains($0) && ($0 != "creator" || member.recommendation != nil) } }
    var body:some View {
        Form {
            Text(member.nickname).font(.headline); Text(member.id).font(.caption).foregroundStyle(.secondary)
            if let recommendation=member.recommendation { Text("推荐理由 · " + recommendation) }
            Picker("操作",selection:$op) { ForEach(ops,id:\.self) { Text(Self.names[$0] ?? $0).tag($0) } }
            if ["grant","revoke"].contains(op) { Picker("荣誉",selection:$kind) { ForEach(kinds,id:\.self) { Text(HonorByline.style($0).0).tag($0) } } }
            if op == "appoint" { ForEach(["content","reports","users","recommend"],id:\.self) { cap in
                Toggle(["content":"内容管理","reports":"处理举报","users":"管理违规用户","recommend":"推荐创作者"][cap] ?? cap,isOn:Binding(get:{caps.contains(cap)},set:{ value in if value {caps.insert(cap)} else {caps.remove(cap)} }))
            } }
            TextField("填写操作原因",text:$reason)
            if let error { Text(error).font(.footnote) }
            Button("确认操作") { confirm=true }.disabled(!ops.contains(op) || reason.trimmingCharacters(in:.whitespacesAndNewlines).count < 2 || reason.count>200 || (["grant","revoke"].contains(op) && !kinds.contains(kind)))
        }.disabled(busy).navigationTitle("管理成员").toolbar { Button("关闭") { dismiss() } }
        .onAppear { caps=Set(member.caps); op=ops.first ?? ""; kind=kinds.first ?? "" }
        .onChange(of:op) { _ in kind=kinds.first ?? ""; requestID=UUID() }
        .onChange(of:reason) { _ in requestID=UUID() }.onChange(of:kind) { _ in requestID=UUID() }.onChange(of:caps) { _ in requestID=UUID() }
        .confirmationDialog((Self.names[op] ?? op) + " · " + member.nickname,isPresented:$confirm) {
            Button("提交并记录原因",role:.destructive) { Task { await submit() } }
        }
    }
    @MainActor private func submit() async {
        guard !busy,tree.user?.id == me.id,ops.contains(op) else {return}; busy=true; defer {busy=false}
        let body:[String:Any]=["memberId":member.id,"operation":op,"kind":kind,"caps":caps.sorted(),"reason":reason.trimmingCharacters(in:.whitespacesAndNewlines),"requestId":requestID.uuidString]
        do { let r=try await tree.api.request("honors.change",body); if tree.user?.id == me.id {
            if let change=r.updatedIdentity { tree.applyBadges(change.id,change.badges,change.showcase) }; dismiss()
        } } catch {self.error=error.localizedDescription}
    }
}
