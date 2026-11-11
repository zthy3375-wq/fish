import SwiftUI
import UIKit

@main
struct HanyuantongApp: App {
    @StateObject private var store = CampusStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
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
