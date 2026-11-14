import WidgetKit
import SwiftUI

struct CourseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}
struct CourseProvider: TimelineProvider {
    func placeholder(in context: Context) -> CourseEntry { CourseEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (CourseEntry) -> Void) {
        completion(CourseEntry(date: Date(), snapshot: try? WidgetSnapshotFile.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseEntry>) -> Void) {
        let now = Date(), snapshot = try? WidgetSnapshotFile.read()
        let calendar = WidgetSnapshot.calendar
        var dates = [now]
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { continue }
            if day > now { dates.append(day) }
            for course in snapshot?.today(day) ?? [] {
                for time in [course.start, course.end] {
                    let pieces = time.split(separator: ":").compactMap { Int($0) }
                    if pieces.count == 2, let date = calendar.date(bySettingHour: pieces[0], minute: pieces[1], second: 0, of: day), date > now { dates.append(date) }
                }
            }
        }
        let entries = Array(Set(dates)).sorted().prefix(40).map { CourseEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}
struct CourseWidgetView: View {
    let entry: CourseEntry
    @Environment(\.widgetFamily) private var family
    private var courses: [WidgetCourse] {
        let parts = WidgetSnapshot.calendar.dateComponents([.hour,.minute], from: entry.date)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return (entry.snapshot?.today(entry.date) ?? []).filter { $0.end > clock }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("邯院通").font(.headline); Spacer(); Text("今日课程").font(.caption).foregroundStyle(.secondary) }
            if entry.snapshot == nil {
                Text("请打开 App 开启课表小组件").font(.caption).foregroundStyle(.secondary)
            } else if courses.isEmpty {
                Spacer(minLength: 0)
                Text("今天没有后续课程").font(.subheadline)
                Text("以 App 和学校通知为准").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(Array(courses.prefix(family == .systemSmall ? 1 : 3))) { course in
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.32, green: 0.44, blue: 0.59)).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(course.start)–\(course.end)  \(course.room)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.96, green: 0.97, blue: 0.99))
            .privacySensitive()
            .widgetURL(URL(string: "hanyuantong://schedule"))
    }
}
@main struct HanyuantongWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HanyuantongCourseWidget", provider: CourseProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                CourseWidgetView(entry: entry).containerBackground(for: .widget) { Color(red: 0.96, green: 0.97, blue: 0.99) }
            } else { CourseWidgetView(entry: entry) }
        }.configurationDisplayName("邯院通课表").description("查看当天接下来的课程，点击打开课表。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
