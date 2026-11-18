import SwiftUI
import Network

struct TapSequence {
    private var last = Date.distantPast
    private var count = 0
    mutating func tap(target: Int, at now: Date = Date()) -> Bool {
        if now.timeIntervalSince(last) > 0.9 { count = 0 }
        last = now; count += 1
        if count == target { count = 0; return true }
        return false
    }
}

struct DiscoverySurface<Content: View>: View {
    let code: String
    let label: String
    let taps: Int
    let canDream: Bool
    @ViewBuilder let content: () -> Content
    @State private var sequence = TapSequence()
    @State private var effect: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("medal.reduce") private var reduce = false
    init(_ code:String, label:String, taps:Int=1, canDream:Bool=false, @ViewBuilder content:@escaping ()->Content) {
        self.code=code; self.label=label; self.taps=taps; self.canDream=canDream; self.content=content
    }
    var body: some View {
        content().scaleEffect(effect != nil && !systemReduce && !reduce ? 1.05 : 1)
            .overlay(alignment:.topTrailing) { if let effect { Image(systemName:effect == "dream" ? "moon.zzz.fill" : "sparkles")
                .foregroundStyle(Color(hex:0xaa771e)).accessibilityHidden(true) } }
            .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration:3).exclusively(before:TapGesture()).onEnded { gesture in
                switch gesture {
                case .first: if canDream { discover("dream") }
                case .second: tapped()
                }
            }).accessibilityElement(children:.ignore).accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .accessibilityAction { tapped() }
            .animation(systemReduce || reduce ? nil : .easeInOut(duration:0.20),value:effect)
            .task(id:effect) {
                guard let id=effect else { return }
                do { try await Task.sleep(nanoseconds:350_000_000) } catch { return }
                MedalJournal.shared.unlock(id); effect=nil
            }
    }
    private func tapped() { if sequence.tap(target:taps) { discover(code) } }
    private func discover(_ id:String) { if effect == nil { effect=id } }
}

struct CampusVersionPage: View {
    var body: some View {
        List {
            Section("关于邯院通") {
                DiscoverySurface("goldfish",label:"版本号",taps:7) {
                    HStack { Text("版本号"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—").foregroundStyle(.secondary) }
                }
            }
            Section { NavigationLink("更新日志") { CampusChangeLog() } }
        }.navigationTitle("关于邯院通")
    }
}
private struct CampusChangeLog: View {
    var body: some View {
        List {
            Section("本次 iOS 测试版") {
                Label("荣誉殿堂与社区身份",systemImage:"rosette")
                Text("在「我的」翻看收藏，在社区昵称旁查看认证；你可以挑选已获得的社区成就展示给同学。")
                Label("校园里的小发现",systemImage:"sparkles")
                Text("小金鱼在首页、课表和校园地图留下了几个小秘密。")
                Label("社区账号与私信",systemImage:"bubble.left.and.bubble.right")
                Text("使用账号和密码注册，可从社区进入互动消息和私信。")
            }
            Section("已有原生功能") { Text("课程、个人学期、待办及备份"); Text("学习通课程、成绩与考试安排"); Text("校园平面图、趣智校园及胖乖生活") }
            Section { DiscoverySurface("lastline",label:"小金鱼，记于邯院") { Text("— 小金鱼，记于邯院").font(.footnote).foregroundStyle(.secondary) } }
        }.navigationTitle("更新日志")
    }
}

@MainActor final class OfflineScheduleCheck: ObservableObject {
    private var monitor: NWPathMonitor?
    func start(scope: String?) {
        stop()
        guard let scope else { return }
        let next=NWPathMonitor(); monitor=next
        next.pathUpdateHandler = { [weak self, weak next] path in
            Task { @MainActor in
                guard let self, let next, self.monitor === next else { return }
                if path.status == .unsatisfied { MedalJournal.shared.unlock("offline",scope:scope) }
                self.stop()
            }
        }
        next.start(queue:DispatchQueue(label:"campus.offline-schedule"))
    }
    func stop() { monitor?.cancel(); monitor=nil }
    deinit { monitor?.cancel() }
}
