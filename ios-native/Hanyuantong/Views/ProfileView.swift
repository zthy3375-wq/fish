import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var learning: LearningStore
    @EnvironmentObject var quzhi: QuzhiStore
    @EnvironmentObject var pangguai: PangguaiStore
    @EnvironmentObject var analytics: AnonymousAnalyticsStore
    @EnvironmentObject var displayPreferences: DisplayPreferencesStore
    @State private var disconnecting = false
    @State private var managingPersonalSchedule = false
    var body: some View {
        List {
            Section {
                LocalProfileSummaryView(store: displayPreferences, academicName: store.academicProfile?.name,
                                        academicMajor: store.academicProfile?.major, academicClass: store.academicProfile?.className)
                    .padding(.vertical, 12)
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
            Section("学校课表设置") {
                DatePicker("学校第一周周一", selection: Binding(get: { store.schoolSemesterStart }, set: { store.calibrateSchoolStart($0) }), displayedComponents: .date)
                    .environment(\.timeZone, ScheduleMath.calendar.timeZone)
                Text("请与学校校历核对，按北京时间计算学校教学周。此处不修改个人学期。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Section("个人课表设置") {
                if let state = store.personalSchedule, let semester = state.semesters.first(where: { $0.id == state.activeSemesterId }) {
                    LabeledContent("当前个人学期", value: semester.title)
                    Text("第一周周一：\(semester.weekStartDate) · \(semester.weekCount) 周").font(.caption).foregroundStyle(CampusTheme.muted)
                } else {
                    Text("旧个人记录已保留。校准第一周周一后尝试启用多学期管理；不兼容记录不会被丢弃。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                Button { managingPersonalSchedule = true } label: { Label("个人学期、课程与作息", systemImage: "calendar.badge.clock") }
                    .accessibilityIdentifier("open-personal-schedule")
            }
            Section("显示与个人资料") {
                NavigationLink("昵称、主题与紧凑布局") { DisplayPreferencesSettingsView(store: displayPreferences) }
                    .accessibilityIdentifier("open-display-preferences")
            }
            Section("个人数据") {
                NavigationLink { CourseImportView(semesterStart: store.semesterStart, existing: store.courses.filter { $0.source == "personal" }, weekCount: store.personalWeekCount, onReplace: store.replacePersonalCourses, onImport: store.importPersonalCourses) } label: { Label("导入课程文件", systemImage: "doc.badge.plus") }.accessibilityIdentifier("open-course-import")
                NavigationLink { PersonalBackupView() } label: { Label("备份与恢复", systemImage: "externaldrive") }
                NavigationLink { NativeReminderSettingsView(reminders: store.reminders) } label: { Label("系统提醒", systemImage: "bell.badge") }
                NavigationLink { NativeWidgetSettingsView(publisher: store.widget) } label: { Label("课表小组件", systemImage: "rectangle.grid.1x2") }
            }
            Section("校园服务") {
                NavigationLink { QuzhiWalletView(store: quzhi) } label: { Label("趣智校园", systemImage: "drop") }.accessibilityIdentifier("open-quzhi")
                NavigationLink { PangguaiWalletView(store: pangguai) } label: { Label("胖乖生活", systemImage: "washer") }.accessibilityIdentifier("open-pangguai")
                NavigationLink { ParcelCenterView() } label: { Label("取快递", systemImage: "shippingbox") }
                NavigationLink { CampusMapView() } label: { Label("校园平面图", systemImage: "map") }
                NavigationLink { LearningCenterView(store: learning) } label: { Label("学习通", systemImage: "books.vertical") }.accessibilityIdentifier("open-learning")
            }
            Section("关于邯院通") {
                Text("学习 · 生活 · 校园")
                Text("iPhone 原生开发版。教务数据以学校官方系统为准；各服务需独立登录，真实账号和设备联调尚待完成。").font(.caption).foregroundStyle(CampusTheme.muted)
                NavigationLink("隐私与本机数据") { PrivacyView() }
                NavigationLink("匿名使用统计") { AnonymousAnalyticsSettingsView(store: analytics) }
                NavigationLink("帮助与反馈") { NativeHelpView() }
            }
        }.scrollContentBackground(.hidden).background(CampusTheme.background).navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $managingPersonalSchedule) { PersonalScheduleSettingsSheet() }
            .confirmationDialog("断开后会移除本机教务会话及教务缓存，个人课程和待办不受影响。", isPresented: $disconnecting, titleVisibility: .visible) { Button("断开连接", role: .destructive) { store.disconnectSchool() } }
    }
}

/// Shared entry from Profile and Schedule. A failed legacy migration cannot open an empty replacement.
struct PersonalScheduleSettingsSheet: View {
    @EnvironmentObject var store: CampusStore
    var body: some View {
        Group {
            if let state = store.personalSchedule {
                SemesterManagementView(state: state, commit: store.savePersonalSchedule)
            } else {
                LegacyPersonalCalendarView(start: store.semesterStart, save: store.calibrateLegacyPersonalStart)
            }
        }
    }
}

private struct LegacyPersonalCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var error: String?
    let save: (Date) throws -> Void
    init(start: Date, save: @escaping (Date) throws -> Void) {
        _start = State(initialValue: start); self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("校准旧个人课表") {
                    DatePicker("个人第一周周一", selection: $start, displayedComponents: .date)
                    Text("将原个人课程完整迁入一个学期，再管理其他学期和作息。学校校历、学校记录和待办不受影响。").font(.caption).foregroundStyle(CampusTheme.muted)
                    if ScheduleMath.weekday(on: start) != 1 { Text("请选择星期一。").foregroundStyle(.red) }
                }
                Section {
                    Text("含超过40周或不兼容信息的旧记录会继续保留，并显示具体原因。请先备份，再调整原记录；不会自动裁剪或替换为空课表。").font(.caption).foregroundStyle(CampusTheme.muted)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("个人学期校准").navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone, ScheduleMath.calendar.timeZone)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { do { try save(start); dismiss() } catch { self.error = error.localizedDescription } }
                            .disabled(ScheduleMath.weekday(on: start) != 1)
                    }
                }
        }.tint(CampusTheme.primary)
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
            if selection == 0 { NativeGradeAnalysisView(grades: store.grades, profile: store.academicProfile) }
            else { NativeExamRecordsView(exams: store.exams) }
            if !store.isConnected { Button("连接教务系统") { store.connectSchool() }.disabled(store.isBusy) }
        }.scrollContentBackground(.hidden).background(CampusTheme.background).navigationTitle("成绩与考试").navigationBarTitleDisplayMode(.inline)
            .toolbar { if store.isConnected { Button { store.refreshSchool() } label: { if store.isBusy { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(store.isBusy).accessibilityLabel("更新教务数据") } }
    }
}
