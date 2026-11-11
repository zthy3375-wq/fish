import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var learning: LearningStore
    @EnvironmentObject var quzhi: QuzhiStore
    @EnvironmentObject var pangguai: PangguaiStore
    @State private var disconnecting = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle").font(.system(size: 44)).foregroundStyle(CampusTheme.primary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) { Text("我的校园").font(.title3.weight(.semibold)); Text(store.isConnected ? "教务系统已连接" : "连接账号，校园信息随手查看").font(.caption).foregroundStyle(CampusTheme.muted) }
                }.padding(.vertical, 12)
            }
            Section("教务系统") {
                if store.isBusy { Button("取消本次查询", role: .cancel) { store.cancelSchool() } }
                if !store.semesters.isEmpty {
                    Picker("查询学期", selection: $store.selectedTerm) {
                        Text("当前学期").tag(Optional<AcademicTerm>.none)
                        ForEach(store.semesters, id: \.self) { term in Text(term.title).tag(Optional(term)) }
                    }.disabled(store.isBusy)
                    Text("选择后点击更新，切换学期会替换当前显示的学校课表。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                if store.isConnected {
                    Label("教务系统已连接", systemImage: "checkmark.shield")
                    Button { store.refreshSchool() } label: { HStack { Label("更新课表、成绩与考试", systemImage: "arrow.clockwise"); Spacer(); if store.isBusy { ProgressView() } } }.disabled(store.isBusy)
                    if let synced = store.lastSynced { LabeledContent("上次更新", value: CampusTheme.date(synced, format: "M月d日 HH:mm")).font(.caption) }
                    Button("断开教务连接", role: .destructive) { disconnecting = true }.disabled(store.isBusy)
                } else {
                    Button { store.connectSchool() } label: { Label("连接邯郸学院教务系统", systemImage: "link") }.disabled(store.isBusy).accessibilityIdentifier("连接邯郸学院")
                }
                NavigationLink { AcademicRecordsView() } label: { Label("成绩与考试", systemImage: "graduationcap") }
            }
            Section("课表设置") {
                DatePicker("第一周周一", selection: $store.semesterStart, displayedComponents: .date)
                Text("请与学校校历核对开学日期，教学周按北京时间计算。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Section("个人数据") {
                NavigationLink { CourseImportView(semesterStart: store.semesterStart, existing: store.courses.filter { $0.source == "personal" }, onReplace: store.replacePersonalCourses, onImport: store.importPersonalCourses) } label: { Label("导入课程文件", systemImage: "doc.badge.plus") }.accessibilityIdentifier("open-course-import")
                NavigationLink { PersonalBackupView() } label: { Label("备份与恢复", systemImage: "externaldrive") }
                NavigationLink { NativeReminderSettingsView(reminders: store.reminders) } label: { Label("系统提醒", systemImage: "bell.badge") }
                NavigationLink { NativeWidgetSettingsView(publisher: store.widget) } label: { Label("课表小组件", systemImage: "rectangle.grid.1x2") }
            }
            Section("校园服务") {
                NavigationLink { QuzhiWalletView(store: quzhi) } label: { Label("趣智校园", systemImage: "drop") }.accessibilityIdentifier("open-quzhi")
                NavigationLink { PangguaiWalletView(store: pangguai) } label: { Label("胖乖生活", systemImage: "washer") }.accessibilityIdentifier("open-pangguai")
                NavigationLink { ParcelShortcutsView() } label: { Label("取快递", systemImage: "shippingbox") }
                NavigationLink { CampusMapView() } label: { Label("校园平面图", systemImage: "map") }
                NavigationLink { LearningCenterView(store: learning) } label: { Label("学习通", systemImage: "books.vertical") }.accessibilityIdentifier("open-learning")
            }
            Section("关于邯院通") {
                Text("学习 · 生活 · 校园")
                Text("iPhone 原生开发版。教务数据以学校官方系统为准；各服务需独立登录，真实账号和设备联调尚待完成。").font(.caption).foregroundStyle(CampusTheme.muted)
                NavigationLink("隐私与本机数据") { PrivacyView() }
                NavigationLink("帮助与反馈") { NativeHelpView() }
            }
        }.scrollContentBackground(.hidden).background(CampusTheme.background).navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("断开后会移除本机教务会话及教务缓存，个人课程和待办不受影响。", isPresented: $disconnecting, titleVisibility: .visible) { Button("断开连接", role: .destructive) { store.disconnectSchool() } }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("学校账号") { Text("请只在学校官方登录页面输入账号和密码。邯院通不会提供自制密码输入框。") }
            Section("本机数据") { Text("个人课程与待办保存在本机。断开教务连接会清除教务会话与教务缓存，保留个人记录。") }
            Section("服务状态") { Text("当前为 iPhone 原生开发版，尚未完成全部 Android 功能迁移。第三方服务需由用户主动连接；付款和设备操作须核对确认，以平台实际状态为准。") }
        }.navigationTitle("隐私与本机数据").navigationBarTitleDisplayMode(.inline)
    }
}

struct AcademicRecordsView: View {
    @EnvironmentObject var store: CampusStore
    @State private var selection = 0
    var body: some View {
        List {
            Section { Picker("教务记录", selection: $selection) { Text("成绩").tag(0); Text("考试").tag(1) }.pickerStyle(.segmented) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if selection == 0 {
                if store.grades.isEmpty { empty("暂无成绩记录") }
                ForEach(store.grades) { grade in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) { Text(grade.name).font(.headline); Spacer(); Text(grade.score).font(.title3.bold()).foregroundStyle(CampusTheme.primary) }
                        Text([grade.term, grade.credit.isEmpty ? "" : "\(grade.credit) 学分", grade.kind].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(CampusTheme.muted)
                    }.padding(.vertical, 7).accessibilityElement(children: .combine)
                }
            } else {
                if store.exams.isEmpty { empty("暂无考试安排") }
                ForEach(store.exams) { exam in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(exam.name).font(.headline)
                        Label("\(exam.date) \(exam.time)", systemImage: "clock").font(.subheadline)
                        if !exam.room.isEmpty { Label(exam.room, systemImage: "mappin.and.ellipse").font(.subheadline) }
                        if !exam.seat.isEmpty { Text("座位号：\(exam.seat)").font(.caption) }
                    }.padding(.vertical, 7).accessibilityElement(children: .combine)
                }
            }
            if !store.isConnected { Button("连接教务系统") { store.connectSchool() }.disabled(store.isBusy) }
        }.scrollContentBackground(.hidden).background(CampusTheme.background).navigationTitle("成绩与考试").navigationBarTitleDisplayMode(.inline)
            .toolbar { if store.isConnected { Button { store.refreshSchool() } label: { if store.isBusy { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(store.isBusy).accessibilityLabel("更新教务数据") } }
    }
    private func empty(_ title: String) -> some View { CampusEmpty(title: title, detail: store.isConnected ? "请更新教务数据；安排以学校官方通知为准。" : "连接学校账号后查看官方记录。", symbol: "doc.text").listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
}
