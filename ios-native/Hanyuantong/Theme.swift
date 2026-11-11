import SwiftUI

enum CampusTheme {
    static let background = Color(hex: 0xf7f8fb)
    static let surface = Color(hex: 0xfdfdff)
    static let text = Color(hex: 0x283445)
    static let muted = Color(hex: 0x6d7889)
    static let primary = Color(hex: 0x4f6f94)
    static let tint = Color(hex: 0xeaf0f8)
    static let border = Color(hex: 0xdce1e9)
    static func course(_ name: String) -> Color {
        switch name { case "blue": return Color(hex: 0x55769b); case "green": return Color(hex: 0x628b7e); case "orange": return Color(hex: 0x9a7b58); default: return Color(hex: 0x7e739a) }
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
        padding(16).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
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
