import SwiftUI
import UIKit
import Network

struct TapSequence {
    private var last = Date.distantPast
    private var count = 0
    mutating func tap(target: Int, at now: Date = Date()) -> Bool {
        let gap = now.timeIntervalSince(last)
        if gap < 0 || gap > 0.75 { count = 0 }
        last = now; count += 1
        if count == target { count = 0; return true }
        return false
    }
}

struct DiscoverySurface<Content: View>: View {
    let code: String
    let label: String
    let taps: Int
    @ViewBuilder let content: () -> Content
    @State private var sequence = TapSequence()
    @State private var effect: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("medal.reduce") private var reduce = false
    init(_ code:String, label:String, taps:Int=1, @ViewBuilder content:@escaping ()->Content) {
        self.code=code; self.label=label; self.taps=taps; self.content=content
    }
    var body: some View {
        Button(action: tapped) {
            content().scaleEffect(effect != nil && !systemReduce && !reduce ? 1.05 : 1)
                .overlay(alignment: .topTrailing) {
                    if effect != nil { Image(systemName: "sparkles").foregroundStyle(Color(hex: 0xaa771e)).accessibilityHidden(true) }
                }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
            .animation(systemReduce || reduce ? nil : .easeInOut(duration:0.20),value:effect)
            .task(id:effect) {
                guard effect != nil else { return }
                do { try await Task.sleep(nanoseconds:350_000_000) } catch { return }
                effect=nil
            }
    }
    private func tapped() { if sequence.tap(target:taps) { discover(code) } }
    private func discover(_ id: String) {
        MedalJournal.shared.unlock(id)
        effect = id
    }
}

/// The hit target stays still while the fish artwork swims within its bounds.
struct HomeFishTouchTarget: UIViewRepresentable {
    let lastResponse: String?
    let pressing: (Bool) -> Void
    let tap: () -> Void
    let dream: () -> Void
    let cancel: () -> Void
    func makeUIView(context: Context) -> FishControl {
        let control = FishControl()
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityIdentifier = "home-mascot"
        control.accessibilityLabel = "首页小金鱼"
        control.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "长按小金鱼") { [weak control] _ in
            control?.dream?(); return true
        }]
        return control
    }
    func updateUIView(_ control: FishControl, context: Context) {
        control.accessibilityValue = lastResponse
        control.pressing = pressing; control.tap = tap; control.dream = dream; control.cancel = cancel
    }

    final class FishControl: UIControl {
        var pressing: ((Bool) -> Void)?
        var tap: (() -> Void)?
        var dream: (() -> Void)?
        var cancel: (() -> Void)?
        private var start: CGPoint?
        private var hold: DispatchWorkItem?
        private var didDream = false

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            start = touch.location(in: window); didDream = false
            pressing?(true)
            let action = DispatchWorkItem { [weak self] in
                guard let self, self.start != nil else { return }
                self.didDream = true; self.dream?()
            }
            hold = action
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: action)
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            guard let start else { return false }
            let point = touch.location(in: window)
            if hypot(point.x - start.x, point.y - start.y) <= 12 { return true }
            cancelTracking(with: event)
            return false
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            let shouldTap = start != nil && !didDream
            release()
            if shouldTap { tap?() }
        }
        override func cancelTracking(with event: UIEvent?) {
            if start != nil { release(); cancel?() }
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { cancelTracking(with: nil) }
        }
        override func accessibilityActivate() -> Bool { tap?(); return true }
        private func release() {
            hold?.cancel(); hold = nil; start = nil; pressing?(false)
        }
    }
}

struct CampusVersionPage: View {
    var body: some View {
        List {
            Section("关于邯院通") {
                DiscoverySurface("goldfish",label:"版本号",taps:7) {
                    HStack { Text("版本号"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—").foregroundStyle(.secondary) }
                }
            }
            Section { NavigationLink("更新日志") { NativeReleaseHistoryView() } }
        }.navigationTitle("关于邯院通")
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
