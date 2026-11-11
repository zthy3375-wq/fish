import SwiftUI
import UIKit

@main
struct HanyuantongApp: App {
    @StateObject private var store = CampusStore()
    @StateObject private var learning = LearningStore()
    @StateObject private var quzhi = QuzhiStore()
    @StateObject private var pangguai = PangguaiStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(learning)
                .environmentObject(quzhi)
                .environmentObject(pangguai)
                .onOpenURL { url in
                    if url.scheme == "hanyuantong", url.host == "schedule", url.user == nil, url.password == nil { store.selectedTab = .schedule }
                }
                .onChange(of: scenePhase) { if $0 == .active { store.refreshReminders() } }
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
