import SwiftUI
import UIKit

enum CampusTheme {
    // Normal-contrast values mirror the current Android tokens. No light-theme redesign.
    static let background = adaptive(light: 0xf7f8fb, dark: 0x171c24, highLight: 0xffffff, highDark: 0x000000)
    static let surface = adaptive(light: 0xfdfdff, dark: 0x1e2530, highLight: 0xffffff, highDark: 0x111720)
    static let text = adaptive(light: 0x283445, dark: 0xe1e7ef, highLight: 0x131f30, highDark: 0xffffff)
    static let muted = adaptive(light: 0x6d7889, dark: 0xa6b1c2, highLight: 0x455267, highDark: 0xd5dfed)
    static let primary = adaptive(light: 0x4f6f94, dark: 0xa4bbd9, highLight: 0x365978, highDark: 0xcadcf4)
    static let tint = adaptive(light: 0xeaf0f8, dark: 0x303e53, highLight: 0xe0e8f4, highDark: 0x202e43)
    static let border = adaptive(light: 0xdce1e9, dark: 0x3a4556, highLight: 0x788596, highDark: 0x91a1b8)
    static let onPrimary = adaptive(light: 0xffffff, dark: 0x171c24)
    static let walletPurple = adaptive(light: 0xeee5ff, dark: 0x352f44)
    static let walletGreen = adaptive(light: 0xe4f2eb, dark: 0x2c3c37)

    static func adaptive(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(uiColor: dynamicUIColor(light: light, dark: dark, highLight: highLight, highDark: highDark))
    }
    static func dynamicUIColor(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let enhanced = traits.accessibilityContrast == .high
            let hex = isDark ? (enhanced ? highDark ?? dark : dark) : (enhanced ? highLight ?? light : light)
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static func course(_ name: String) -> Color {
        switch name {
        case "blue": return adaptive(light: 0x55769b, dark: 0xadc4df, highLight: 0x365978, highDark: 0xd9e8ff)
        case "green": return adaptive(light: 0x628b7e, dark: 0xa9c9bd, highLight: 0x315d4f, highDark: 0xd2f1e5)
        case "orange": return adaptive(light: 0x9a7b58, dark: 0xd9bd98, highLight: 0x6a4d2c, highDark: 0xffdfb8)
        default: return adaptive(light: 0x7e739a, dark: 0xc6b8dc, highLight: 0x564971, highDark: 0xe7d6ff)
        }
    }
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }
    static func date(_ date: Date, format: String = "M月d日 EEEE") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension View {
    func campusCard() -> some View {
        modifier(CampusCardModifier())
    }
}

private struct CampusCompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var campusCompactLayout: Bool {
        get { self[CampusCompactLayoutKey.self] }
        set { self[CampusCompactLayoutKey.self] = newValue }
    }
}

enum CampusLayoutMetrics {
    static func cardPadding(compact: Bool, accessibilitySize: Bool) -> CGFloat {
        compact && !accessibilitySize ? 12 : 16
    }
}

private struct CampusCardModifier: ViewModifier {
    @Environment(\.campusCompactLayout) private var compact
    @Environment(\.dynamicTypeSize) private var typeSize
    func body(content: Content) -> some View {
        content.padding(CampusLayoutMetrics.cardPadding(compact: compact, accessibilitySize: typeSize.isAccessibilitySize))
            .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(CampusTheme.border, lineWidth: 0.7))
    }
}

struct CampusEmpty: View {
    let title: String
    let detail: String
    var symbol = "tray"
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(CampusTheme.primary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(CampusTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 22).campusCard()
    }
}
