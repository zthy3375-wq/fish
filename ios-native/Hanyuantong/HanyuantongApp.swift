import SwiftUI
import UIKit

@main
struct HanyuantongApp: App {
    @StateObject private var store = CampusStore()
    @StateObject private var treehole: TreeholeStore
    @StateObject private var learning = LearningStore()
    @StateObject private var quzhi = QuzhiStore()
    @StateObject private var pangguai = PangguaiStore()
    @StateObject private var analytics = AnonymousAnalyticsStore()
    @StateObject private var displayPreferences = DisplayPreferencesStore()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        CampusTabChrome.configure()
        #if DEBUG && targetEnvironment(simulator)
        _treehole = StateObject(wrappedValue: CommunityReplyUITestTransport.store() ?? TreeholeStore())
        #else
        _treehole = StateObject(wrappedValue: TreeholeStore())
        #endif
    }
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
                .onChange(of: scenePhase) { if $0 == .active { store.refreshReminders(); if analytics.state.deletePending { analytics.flush() } } }
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


#if DEBUG && targetEnvironment(simulator)
/// Inputs come from XCTest. This session resolves every request locally.
private final class CommunityReplyUITestTransport: URLProtocol {
    private struct Response: Decodable { let status: Int; let json: String }
    private static let fixture = ProcessInfo.processInfo.environment["HYT_REPLY_UI_FIXTURE"].flatMap {
        try? JSONDecoder().decode([String: [Response]].self, from: Data($0.utf8))
    }
    private static let lock = NSLock()
    private static var offsets: [String: Int] = [:]

    @MainActor static func store() -> TreeholeStore? {
        guard fixture != nil else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        let transport = TreeholeService(vault: FixtureVault(), session: URLSession(configuration: configuration))
        return TreeholeStore(api: transport)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let action = url.lastPathComponent
        Self.lock.lock()
        let responses = Self.fixture?[action] ?? []
        let index = Self.offsets[action, default: 0]
        let response = responses.isEmpty ? nil : responses[min(index, responses.count - 1)]
        Self.offsets[action] = index + 1
        Self.lock.unlock()
        let http = HTTPURLResponse(url: url, statusCode: response?.status ?? 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((response?.json ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private final class FixtureVault: TreeholeTokenVault {
        var token: String? = String(repeating: "q", count: 43)
        func read() throws -> String? { token }
        func save(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
}
#endif
