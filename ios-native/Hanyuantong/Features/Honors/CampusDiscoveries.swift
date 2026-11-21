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
        Group {
            if taps > 1 {
                artwork.accessibilityHidden(true).overlay {
                    DiscoveryTouchTarget(label: label, identifier: "discovery-" + code, tap: tapped,
                                         cancel: { sequence = TapSequence() })
                }
            } else {
                Button(action: tapped) { artwork }.buttonStyle(.plain).accessibilityLabel(label)
            }
        }
            .animation(systemReduce || reduce ? nil : .easeInOut(duration:0.20),value:effect)
            .task(id:effect) {
                guard effect != nil else { return }
                do { try await Task.sleep(nanoseconds:350_000_000) } catch { return }
                effect=nil
            }
    }
    private var artwork: some View {
        content().scaleEffect(effect != nil && !systemReduce && !reduce ? 1.05 : 1)
            .overlay(alignment: .topTrailing) {
                if effect != nil { Image(systemName: "sparkles").foregroundStyle(Color(hex: 0xaa771e)).accessibilityHidden(true) }
            }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
    private func tapped() { if sequence.tap(target:taps) { discover(code) } }
    private func discover(_ id: String) {
        MedalJournal.shared.unlock(id)
        effect = id
    }
}

/// Counts each completed touch independently, including rapid taps inside a scrolling page.
struct DiscoveryTouchTarget: UIViewRepresentable {
    let label: String
    let identifier: String
    var lastResponse: String? = nil
    var pressing: ((Bool) -> Void)? = nil
    let tap: () -> Void
    var longPress: (() -> Void)? = nil
    let cancel: () -> Void
    func makeUIView(context: Context) -> TouchControl {
        let control = TouchControl()
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityIdentifier = identifier
        control.accessibilityLabel = label
        if longPress != nil {
            control.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "长按小金鱼") { [weak control] _ in
                control?.longPress?(); return true
            }]
        }
        return control
    }
    func updateUIView(_ control: TouchControl, context: Context) {
        control.accessibilityValue = lastResponse
        control.pressing = pressing; control.tap = tap; control.longPress = longPress; control.cancel = cancel
    }

    final class TouchControl: UIControl {
        var pressing: ((Bool) -> Void)?
        var tap: (() -> Void)?
        var longPress: (() -> Void)?
        var cancel: (() -> Void)?
        private var start: CGPoint?
        private var hold: DispatchWorkItem?
        private var didHold = false

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            start = touch.location(in: window); didHold = false
            pressing?(true)
            guard longPress != nil else { return true }
            let action = DispatchWorkItem { [weak self] in
                guard let self, self.start != nil else { return }
                self.didHold = true; self.longPress?()
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
            let shouldTap = start != nil && !didHold
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("关于邯院通").font(.headline)
                DiscoverySurface("goldfish", label: "版本号", taps: 7) {
                    HStack {
                        Text("版本号")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
                Divider()
                NavigationLink { NativeReleaseHistoryView() } label: {
                    HStack { Text("更新日志"); Spacer(); Image(systemName: "chevron.right").accessibilityHidden(true) }
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.campusCard().padding(16)
        }.background(CampusTheme.background).navigationTitle("关于邯院通")
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
