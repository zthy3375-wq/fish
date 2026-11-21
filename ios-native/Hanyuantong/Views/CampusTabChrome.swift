import SwiftUI
import UIKit

/// The system tab buttons retain their accessibility actions, hit areas and navigation stacks.
struct CampusTabChrome: UIViewControllerRepresentable {
    let selection: AppTab
    let reduceMotion: Bool

    static func configure() {
        if #unavailable(iOS 16.0) {
            // iOS 15 hosts SwiftUI List and Form in a UITableView.
            UITableView.appearance().backgroundColor = UIColor(CampusTheme.background)
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(CampusTheme.surface)
        appearance.shadowColor = UIColor(CampusTheme.border)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(CampusTheme.muted)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(CampusTheme.muted), .font: UIFont.systemFont(ofSize: 11, weight: .medium)]
            item.selected.iconColor = UIColor(CampusTheme.primary)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(CampusTheme.primary), .font: UIFont.systemFont(ofSize: 11, weight: .semibold)]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.selection = selection
        controller.reduceMotion = reduceMotion
        controller.positionMarker()
    }

    private final class Marker: UIView {}

    final class Controller: UIViewController {
        var selection = AppTab.home
        var reduceMotion = false
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); positionMarker() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); positionMarker() }

        func positionMarker() {
            guard let tabs = tabBarController, let items = tabs.tabBar.items, items.count == AppTab.allCases.count,
                  let index = AppTab.allCases.firstIndex(of: selection) else { return }
            let bar = tabs.tabBar
            let buttons = bar.subviews.compactMap { $0 as? UIControl }.sorted { $0.frame.minX < $1.frame.minX }
            guard buttons.count == items.count else { return }
            let button = buttons[bar.effectiveUserInterfaceLayoutDirection == .rightToLeft ? items.count - 1 - index : index]
            let target = button.frame.insetBy(dx: 3, dy: 2)
            guard target.width > 0 && target.height > 0 else { return }
            let marker: Marker
            if let existing = bar.subviews.compactMap({ $0 as? Marker }).first { marker = existing }
            else {
                marker = Marker(frame: target)
                marker.isUserInteractionEnabled = false
                marker.accessibilityElementsHidden = true
                marker.backgroundColor = UIColor(CampusTheme.tint)
                marker.layer.cornerRadius = 12
                bar.insertSubview(marker, belowSubview: buttons[0])
            }
            guard marker.frame != target else { return }
            UIView.animate(withDuration: reduceMotion ? 0 : 0.2, delay: 0,
                           options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) { marker.frame = target }
        }
    }
}

struct CampusPageReveal: ViewModifier {
    var active: Bool
    var reduce: Bool
    @State private var opacity = 1.0

    func body(content: Content) -> some View {
        content.opacity(opacity)
            .onAppear { reveal() }
            .onChange(of: active) { _ in reveal() }
    }

    private func reveal() {
        guard active && !reduce else { opacity = 1; return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { opacity = 0.6 }
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.12)) { opacity = 1 }
        }
    }
}

struct CampusPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage("medal.reduce") private var localReduce = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduce && !localReduce ? 0.98 : 1)
            .animation(reduce || localReduce ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CampusRootTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 22, weight: .bold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(CampusTheme.muted) }
        }.foregroundStyle(CampusTheme.text)
    }
}


struct CampusDetailHeader: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .navigationBarLeading) {
                CampusRootTitle(title: title)
            }
        }
    }
}
