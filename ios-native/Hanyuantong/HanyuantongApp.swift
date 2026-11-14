import SwiftUI
import UIKit

@main
struct HanyuantongApp: App {
    @StateObject private var store = CampusStore()
    @StateObject private var treehole = TreeholeStore()
    @StateObject private var learning = LearningStore()
    @StateObject private var quzhi = QuzhiStore()
    @StateObject private var pangguai = PangguaiStore()
    @StateObject private var analytics = AnonymousAnalyticsStore()
    @StateObject private var displayPreferences = DisplayPreferencesStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(treehole)
                .environmentObject(learning)
                .environmentObject(quzhi)
                .environmentObject(pangguai)
                .environmentObject(analytics)
                .environmentObject(displayPreferences)
                .preferredColorScheme(displayPreferences.preferences.theme.colorScheme)
                .environment(\.campusCompactLayout, displayPreferences.preferences.compact)
                .onOpenURL { url in
                    if url.scheme == "hanyuantong", url.host == "schedule", url.user == nil, url.password == nil { store.selectedTab = .schedule }
                }
                .onChange(of: scenePhase) { if $0 == .active { store.refreshReminders(); analytics.flush() } }
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.calendar, ScheduleMath.calendar)
                .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                .background(PresenterBridge { store.attachPresenter($0) }.frame(width: 0, height: 0))
        }
    }
}
private struct PresenterBridge: UIViewControllerRepresentable {
    let ready: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> PresenterController {
        let controller = PresenterController(); controller.ready = ready; return controller
    }
    func updateUIViewController(_ uiViewController: PresenterController, context: Context) {}
    final class PresenterController: UIViewController {
        var ready: ((UIViewController) -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The bridge remains attached to the active SwiftUI scene; never pick an unrelated window.
            ready?(parent ?? self)
        }
    }
}
