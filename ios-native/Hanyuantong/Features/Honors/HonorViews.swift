import SwiftUI
import UIKit
import AudioToolbox

struct HonorByline: View {
    let name: String
    let badges: MemberBadges?
    var body: some View {
        HStack(alignment:.firstTextBaseline,spacing:5) {
            Text(name).lineLimit(2).layoutPriority(1)
            ForEach(badges?.visible ?? []) { stamp in
                let style = Self.style(stamp.code)
                Label(style.0,systemImage:style.1).font(.caption2.weight(.medium)).foregroundStyle(style.2)
                    .accessibilityLabel(style.0)
            }
        }
    }
    static func style(_ code:String) -> (String,String,Color) {
        switch code {
        case "developer": return ("开发者","crown.fill",Color(hex:0xad771c))
        case "moderator": return ("管理员","shield.fill",.blue)
        case "seed": return ("种子","leaf.fill",Color(hex:0x40815d))
        case "creator": return ("优质","sparkles",.purple)
        case "contributor": return ("贡献者","heart.fill",Color(hex:0xa84769))
        default: return ("荣誉","rosette",.secondary)
        }
    }
}

struct MedalEmblem: View {
    let medal: CampusMedal
    let locked: Bool
    var body: some View {
        let color = locked ? Color.secondary : Color(hex:UInt32(medal.color.dropFirst(),radix:16) ?? 0x917142)
        ZStack {
            Circle().fill(LinearGradient(colors:[color.opacity(0.22),color.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Circle().strokeBorder(color.opacity(0.32),lineWidth:1)
            Image(systemName:locked && medal.hidden == true ? "lock.fill" : medal.symbol)
                .font(.system(size:21,weight:.medium)).foregroundStyle(color)
        }.frame(width:48,height:48).accessibilityHidden(true)
    }
}

struct HonorShelfLink: View {
    let badges: MemberBadges?
    let pins: [String]
    var memberID: String? = nil
    var personal=false
    @EnvironmentObject private var campus:CampusStore
    @EnvironmentObject private var learning:LearningStore
    @ObservedObject private var journal=MedalJournal.shared
    @State private var opened = false
    @State private var selectedCode: String?
    private var displayMedals:[CampusMedal] {
        let privatePins = personal ? journal.pinned(school:campus.schoolMedalScope,learning:learning.cache.account) : []
        var codes=privatePins + pins.filter { !privatePins.contains($0) }
        if personal {
            let recent=CampusMedal.catalog.compactMap { medal -> (String,Date)? in
                guard medal.source != "community", let at=journal.stamp(medal,scope:medal.source == "school" ? campus.schoolMedalScope : learning.cache.account) else {return nil}
                return (medal.code,at)
            }.sorted{$0.1>$1.1}
            for item in recent where !codes.contains(item.0) {codes.append(item.0)}
        }
        return Array(codes.compactMap {CampusMedal.byCode[$0]}.prefix(3))
    }
    init(badges:MemberBadges?,pins:[String],memberID:String?=nil,personal:Bool=false) {
        self.badges=badges; self.pins=pins; self.memberID=memberID; self.personal=personal
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Button { selectedCode=nil; opened=true } label: {
                HStack(spacing:14) {
                    Image(systemName:"rosette").font(.title).foregroundStyle(Color(hex:0xa77828))
                        .frame(width:50,height:54).background(Color(hex:0xd2a44e).opacity(0.12),in:RoundedRectangle(cornerRadius:13))
                    VStack(alignment:.leading,spacing:4) {
                        Text("荣誉殿堂").font(.headline)
                        Text(badges?.visible.first.map{HonorByline.style($0.code).0} ?? "身份与成就收藏").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.borderless).accessibilityIdentifier("open-honor-shelf")
            if !displayMedals.isEmpty {
                HStack(spacing:8) {
                    ForEach(displayMedals) { medal in
                        Button { selectedCode=medal.code; opened=true } label:{
                            HStack(spacing:4) { Image(systemName:medal.symbol);Text(medal.name).lineLimit(2) }
                                .font(.caption).frame(maxWidth:.infinity,minHeight:44)
                                .background(Color(hex:0xb8974f).opacity(0.10),in:RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.borderless).accessibilityLabel("查看成就，"+medal.name)
                    }
                }
            }
        }.padding(.vertical,6)
        .background(NavigationLink(isActive:$opened) {
            MedalCollection(memberID:memberID,initialCode:selectedCode)
        } label: { EmptyView() }.hidden().accessibilityHidden(true))
    }
}

struct MedalCollection: View {
    @EnvironmentObject var tree: TreeholeStore
    @EnvironmentObject var campus: CampusStore
    @EnvironmentObject var learning: LearningStore
    @ObservedObject var journal = MedalJournal.shared
    let memberID: String?
    var initialCode:String?=nil
    @State private var openedInitial=false
    @State private var selectedStamp:HonorStamp?
    @State private var hall: NativeHonorHall?
    @State private var group = "全部"
    @State private var error: String?
    @State private var loading = false
    @State private var editing = false
    @State private var cacheNote: String?
    @State private var chosen: CampusMedal?
    @State private var showSettings = false
    private var viewer: String? { tree.user?.id }
    private var own: Bool { memberID == nil || memberID == viewer }
    private var target: String? { memberID ?? viewer }
    private var current: NativeHonorHall? { hall?.id == target ? hall : nil }
    private var medals: [CampusMedal] { own ? CampusMedal.catalog : (current?.showcase ?? []).compactMap { CampusMedal.byCode[$0] } }
    private func date(_ m: CampusMedal) -> Date? {
        if m.source == "community" { return MedalDates.parse(current?.awards[m.code]) }
        return journal.stamp(m,scope:m.source == "school" ? campus.schoolMedalScope : learning.cache.account)
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                if let h = current {
                    HonorByline(name:h.nickname,badges:h.badges).font(.title2.weight(.semibold))
                    let stamps=[h.badges.official].compactMap{$0} + h.honors
                    ForEach(stamps) { item in
                        let style=HonorByline.style(item.code)
                        HStack {
                            Button { selectedStamp=item } label:{ Label(style.0,systemImage:style.1).foregroundStyle(style.2) }
                            Spacer()
                            if own && h.honors.contains(where:{$0.code == item.code}) {
                                Button(h.badges.worn?.code == item.code ? "摘下" : "佩戴") {
                                    wear(h.badges.worn?.code == item.code ? nil : item.code,h.showcase)
                                }.disabled(editing)
                            }
                        }
                    }
                }
                if own && viewer == nil && !loading { Text("登录社区账号后，这里也会显示你的社区荣誉。").font(.footnote).foregroundStyle(.secondary) }
                if let cacheNote { Text(cacheNote).font(.footnote).foregroundStyle(.secondary) }
                if loading { ProgressView("读取社区荣誉") }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary); Button("重新读取") { Task { await refresh(force:true) } } }
                if own {
                    let count = medals.filter { date($0) != nil }.count
                    HStack { Text("成就收藏馆").font(.title2.bold()); Spacer(); Text("\(count) / \(medals.count)").monospacedDigit() }
                    ProgressView(value:Double(count),total:Double(max(1,medals.count))).tint(.purple)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:60),spacing:4)],alignment:.leading,spacing:2) {
                        ForEach(["全部","初识","学习","生活","社区","时光","隐藏"],id:\.self) { key in
                            Button { group=key } label: {
                                Text(key).font(.subheadline.weight(.medium))
                                    .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .background(group == key ? CampusTheme.tint : .clear,in:Capsule())
                                .accessibilityAddTraits(group == key ? .isSelected : [])
                        }
                    }.accessibilityIdentifier("medal-groups")
                } else { Text("展示成就").font(.headline) }
                if medals.isEmpty && !loading { Text(own ? "收藏目录读取失败" : "还没有展示成就").foregroundStyle(.secondary) }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:88),spacing:8)],spacing:10) {
                    ForEach(medals.filter { group == "全部" || $0.group == group }) { m in
                        let locked = date(m) == nil
                        Button { chosen = m } label: {
                            VStack(spacing:8) { MedalEmblem(medal:m,locked:locked); Text(locked && m.hidden == true ? "???" : m.name).font(.caption.weight(.medium)).multilineTextAlignment(.center).lineLimit(2) }
                                .frame(maxWidth:.infinity,minHeight:94).padding(4)
                                .background(Color.secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20).frame(maxWidth:650)
        }.navigationTitle("荣誉殿堂").navigationBarTitleDisplayMode(.inline)
        .toolbar { if own { Button { showSettings = true } label: { Image(systemName:"slider.horizontal.3") }.accessibilityLabel("成就反馈设置") } }
        .sheet(item:$selectedStamp) { badge in HonorStampDetails(item:badge) }
        .sheet(isPresented:$showSettings) { MedalSettings() }
        .sheet(item:$chosen) { m in
            CampusNavigation {
                List {
                    let stamp = date(m)
                    Section {
                        MedalEmblem(medal:m,locked:stamp == nil)
                        Text(stamp == nil && m.hidden == true ? "隐藏成就" : m.name).font(.title2.bold())
                        Text(m.tier + " · " + m.group)
                        if stamp != nil || m.hidden != true {
                            Text(m.description); Text(m.condition).foregroundStyle(.secondary)
                            if stamp == nil, let key = m.metric, let value = current?.progress?[key] { Text("\(min(value,m.goal)) / \(m.goal)") }
                        }
                        if let stamp { Text("获得于 " + CampusTheme.date(stamp, format:"yyyy年M月d日")) }
                        else { Label("未解锁",systemImage:"lock") }
                    }
                    if own, m.source != "community", stamp != nil {
                        let pins=journal.pinned(school:campus.schoolMedalScope,learning:learning.cache.account)
                        Button(pins.contains(m.code) ? "从本机展柜取下" : "展示在本机展柜") {
                            journal.togglePin(m,school:campus.schoolMedalScope,learning:learning.cache.account)
                        }.disabled(!pins.contains(m.code) && pins.count>=3)
                    }
                    if own, m.source == "community", stamp != nil, let h = current {
                        let pinned = h.showcase.contains(m.code)
                        Button(pinned ? "从主页取下" : "展示在社区主页") {
                            wear(h.badges.worn?.code,pinned ? h.showcase.filter { $0 != m.code } : h.showcase + [m.code])
                            chosen = nil
                        }.disabled(editing || (!pinned && h.showcase.count >= 3))
                    }
                }.navigationTitle("成就详情").toolbar { Button("完成") { chosen = nil } }
            }
        }
        .refreshable { await refresh(force:true) }
        .task(id:target) {
            await refresh()
            if !Task.isCancelled, !openedInitial, let initialCode,let medal=medals.first(where:{$0.code == initialCode}),date(medal) != nil { openedInitial=true; chosen=medal }
        }
    }
    @MainActor private func refresh(force:Bool=false) async {
        if viewer == nil && memberID == nil {
            do { try await tree.restoreGalleryIdentity() }
            catch { self.error="社区账号暂时无法读取，仍可查看本机收藏。"; loading=false; return }
            if tree.user != nil { return } // The account change starts the scoped task.
        }
        let owner = viewer
        guard let id = target, UUID(uuidString:id) != nil, owner != nil else { hall=nil; error=nil; loading=false; cacheNote=nil; return }
        loading=true; error=nil; cacheNote=nil
        if own, let storage = try? ProtectedStorage(), let cache = try? storage.read("honors-" + id, as:NativeHonorHall.self), cache.id == id {
            hall=cache
            if !force, let last=UserDefaults.standard.object(forKey:"hall.updated." + id) as? Date, (0..<45).contains(Date().timeIntervalSince(last)) {loading=false;return}
            cacheNote="已显示上次保存的社区荣誉"
        }
        do {
            let response = try await tree.api.request("honors.hall",["memberId":id])
            guard !Task.isCancelled, tree.user?.id == owner, target == id else { return }
            guard let h=response.hall,h.id == id else { throw TreeholeError(code:"invalid_response") }
            hall=h; cacheNote=nil
            if own, let storage = try? ProtectedStorage() { do { try storage.write(h,name:"honors-" + id); UserDefaults.standard.set(Date(),forKey:"hall.updated." + id) } catch { cacheNote="本次社区荣誉未保存到设备" } }
        } catch { if !Task.isCancelled && tree.user?.id == owner { self.error = "社区荣誉暂时无法更新。" } }
        if tree.user?.id == owner { loading=false }
    }
    private func wear(_ honor:String?,_ pins:[String]) {
        guard !editing, let owner=viewer, owner == target else { return }
        editing=true
        Task { @MainActor in
            defer { editing=false }
            do {
                let r = try await tree.api.request("honors.wear",["honor":honor as Any? ?? NSNull(),"showcase":pins])
                guard tree.user?.id == owner, let h=r.hall, h.id == owner else { return }
                hall=h; tree.applyIdentity(h)
                if let storage = try? ProtectedStorage() { try? storage.write(h,name:"honors-" + owner) }
            } catch { self.error=error.localizedDescription }
        }
    }
}

private struct HonorStampDetails:View {
    let item:HonorStamp
    @Environment(\.dismiss) var dismiss
    private let info=["developer":("开发者","邯院通的创建者，经原始所有者记录和稳定账号核验。"),"moderator":("管理员","由开发者任命，按获授权限处理内容、举报和用户问题。"),"seed":("种子用户","早期参与测试和建设，由开发者授予并永久保留。"),"creator":("优质创作者","持续分享优质内容，由管理员推荐、开发者审核。"),"contributor":("社区贡献者","以建议、反馈或实际帮助改善社区，由开发者核实授予。")]
    var body:some View { CampusNavigation { List {
        let style=HonorByline.style(item.code)
        Label(info[item.code]?.0 ?? style.0,systemImage:style.1).font(.title2.weight(.semibold)).foregroundStyle(style.2)
        if let description=info[item.code]?.1 {Text(description)}
        if let date=MedalDates.parse(item.at) {Text("获得于 " + CampusTheme.date(date,format:"yyyy年M月d日"))}
        else {Text("暂无可核实的授予日期").foregroundStyle(.secondary)}
    }.navigationTitle("身份与荣誉").toolbar {Button("完成"){dismiss()}} } }
}

private struct MedalSettings: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("medal.sound") var sound=false
    @AppStorage("medal.reduce") var reduce=false
    @AppStorage("medal.haptic") var haptic=true
    var body: some View { CampusNavigation { Form {
        Toggle("提示音",isOn:$sound); Toggle("轻微振动",isOn:$haptic); Toggle("减少动画",isOn:$reduce)
    }.navigationTitle("成就反馈").toolbar { Button("完成") { dismiss() } } } }
}

struct MedalOverlay: View {
    @ObservedObject var journal = MedalJournal.shared
    @Environment(\.accessibilityReduceMotion) var systemReduce
    @AppStorage("medal.reduce") var reduce=false
    @AppStorage("medal.haptic") var haptic=true
    @AppStorage("medal.sound") var sound=false
    var body: some View {
        Group { if let m = journal.notice {
            HStack(spacing:12) { MedalEmblem(medal:m,locked:false); VStack(alignment:.leading,spacing:3) {
                Text("成就已解锁").font(.caption).foregroundStyle(.secondary)
                Text(m.name).font(.headline); Text(m.description).font(.caption).lineLimit(2)
            }; Spacer() }.padding(13).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
              .shadow(color:.black.opacity(0.12),radius:8,y:3).padding(.horizontal,16).padding(.top,5)
              .id(m.code).transition(reduce || systemReduce ? .opacity : .opacity.combined(with:.scale(scale:0.94,anchor:.top)))
              .task(id:m.code) {
                  if haptic { UIImpactFeedbackGenerator(style:.light).impactOccurred() }
                  if sound { AudioServicesPlaySystemSound(1057) }
                  UIAccessibility.post(notification:.announcement,argument:"成就已解锁，" + m.name)
                  do { try await Task.sleep(nanoseconds:2_500_000_000) } catch { return }
                  journal.advance(m.code)
              }
        } }.animation(reduce || systemReduce ? nil : .easeOut(duration:0.24),value:journal.notice?.code).allowsHitTesting(false)
    }
}
