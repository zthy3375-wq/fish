import Foundation
import Combine
import WidgetKit
import SwiftUI

@MainActor final class NativeWidgetPublisher: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "课表小组件默认关闭"
    private var loaded = false
    private var storage: ProtectedStorage?
    init() {
        do {
            let storage = try ProtectedStorage(); self.storage = storage
            enabled = try storage.read("widget-enabled", as: Bool.self) ?? false
            loaded = true
        } catch { status = "小组件设置暂无法读取，原记录未覆盖。" }
    }
    func change(_ value: Bool, courses: [Course], semesterStart: Date) {
        guard loaded, let storage else { return }
        do {
            if value { try write(courses: courses, semesterStart: semesterStart) }
            else { try WidgetSnapshotFile.remove() }
            try storage.write(value, name: "widget-enabled")
            enabled = value
            WidgetCenter.shared.reloadTimelines(ofKind: "HanyuantongCourseWidget")
            status = value ? "课表已提供给本 App 小组件，请从主屏幕小组件列表添加邯院通。" : "小组件课表副本已移除。"
        } catch { status = "小组件共享容器或签名尚不可用。开发者需为 App 与 Widget 配置同一 App Group 和 Keychain Group，未写入明文替代文件。" }
    }
    @discardableResult func clearForAccountChange() -> Bool {
        guard enabled else { return true }
        do {
            try WidgetSnapshotFile.remove()
            WidgetCenter.shared.reloadTimelines(ofKind: "HanyuantongCourseWidget")
            return true
        } catch {
            status = "旧账号的小组件副本未能清理，请解锁设备后重试退出。"
            return false
        }
    }
    func publish(courses: [Course], semesterStart: Date) {
        guard loaded, enabled else { return }
        do {
            try write(courses: courses, semesterStart: semesterStart)
            WidgetCenter.shared.reloadTimelines(ofKind: "HanyuantongCourseWidget")
        } catch { status = "小组件更新失败，可能仍显示上次缓存。请解锁后重新打开 App。" }
    }
    private func write(courses: [Course], semesterStart: Date) throws {
        try WidgetSnapshotFile.write(WidgetSnapshot(version: 1, generatedAt: Date(), semesterStart: semesterStart,
            courses: courses.map { WidgetCourse(id: $0.id.uuidString, title: $0.name, room: $0.room, day: $0.day, start: $0.start, end: $0.end, weeks: $0.weeks) }))
    }
}
struct NativeWidgetSettingsView: View {
    @ObservedObject var publisher: NativeWidgetPublisher
    @EnvironmentObject var store: CampusStore
    var body: some View {
        Form {
            Toggle("允许小组件显示课表", isOn: Binding(get: { publisher.enabled }, set: { publisher.change($0, courses: store.courses, semesterStart: store.semesterStart) }))
            Text(publisher.status)
            Text("开启后会将课程名称、地点和上课时间的加密副本提供给本 App 的小组件，不包含学校 Cookie、成绩或登录信息。小组件可能显示在主屏幕/锁屏上，请自行判断隐私需要。关闭后移除副本并请求刷新，iOS 控制实际刷新时间。").font(.footnote).foregroundStyle(.secondary)
            Text("添加方法：长按 iPhone 主屏幕空白处，选择编辑/添加小组件，搜索“邯院通”。iOS 不支持 Android 的自动固定流程。")
            Button("刷新课表副本") { store.refreshWidget() }.disabled(!publisher.enabled)
        }.navigationTitle("课表小组件").navigationBarTitleDisplayMode(.inline)
    }
}
