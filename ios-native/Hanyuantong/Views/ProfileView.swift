import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var tree: TreeholeStore
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var learning: LearningStore
    @EnvironmentObject var displayPreferences: DisplayPreferencesStore
    @State private var schoolExpanded = false
    @State private var disconnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LocalProfileSummaryView(store: displayPreferences, academicName: store.academicProfile?.name,
                                        academicMajor: store.academicProfile?.major, academicClass: store.academicProfile?.className)
                HonorShelfLink(badges: tree.user?.badges, pins: tree.user?.showcase ?? [], personal: true)
                Text("常用教务").font(.subheadline.weight(.semibold)).padding(.top, 6)
                HStack(alignment: .top, spacing: 0) {
                    shortcut("成绩与学业", icon: "chart.bar") { AcademicRecordsView() }
                    shortcut("考试安排", icon: "calendar.badge.clock") { AcademicRecordsView(initialSelection: 1) }
                    shortcut("学期校历", icon: "calendar") { SemesterCalendar() }
                    shortcut("桌面课表", icon: "rectangle.grid.1x2") { NativeWidgetSettingsView(publisher: store.widget) }
                }.padding(5).modifier(ProfilePanel())
                Text("账号与连接").font(.subheadline.weight(.semibold)).padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button { schoolExpanded.toggle() } label: {
                        HStack {
                            Image(systemName: "graduationcap").foregroundStyle(CampusTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("学校教务")
                                Text(store.isConnected ? "已连接" : "未连接").font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: schoolExpanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("school-details")
                    .accessibilityValue(schoolExpanded ? "已展开" : "已收起")
                    Button {
                        if store.isConnected { store.refreshSchool() } else { store.connectSchool() }
                    } label: {
                            if store.isBusy { ProgressView() }
                            else { Text(store.isConnected ? "刷新" : "连接").font(.subheadline.weight(.medium)).frame(minWidth: 44, minHeight: 44) }
                        }.buttonStyle(.borderedProminent).disabled(store.isBusy)
                        .accessibilityLabel(store.isConnected ? "刷新教务数据" : "连接邯郸学院")
                    }
                    if schoolExpanded {
                    if store.isBusy { Button("取消本次查询", role: .cancel) { store.cancelSchool() } }
                    if !store.semesters.isEmpty {
                        Picker("查询学期", selection: $store.selectedTerm) {
                            Text("当前学期").tag(Optional<AcademicTerm>.none)
                            ForEach(store.semesters, id: \.self) { term in Text(term.title).tag(Optional(term)) }
                        }.disabled(store.isBusy)
                        Text("选择后点击更新，切换学期会替换当前显示的学校课表。").font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                    if let synced = store.lastSynced {
                        CampusLabeledValue("上次更新", value: CampusTheme.date(synced, format: "M月d日 HH:mm"))
                    }
                    if store.isConnected {
                        Button("断开教务连接", role: .destructive) { disconnecting = true }.disabled(store.isBusy)
                    } else {
                        Text("连接后可同步课表、成绩和考试安排。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Button {
                    tree.accountEntryRequested = true
                    store.selectedTab = .community
                } label: { profileRow("邯院通社区账号", icon: "bubble.left") }.buttonStyle(CampusPressStyle())
                Divider()
                NavigationLink { LearningCenterView(store: learning) } label: { profileRow("学习通", icon: "book") }
                    .buttonStyle(CampusPressStyle()).accessibilityIdentifier("open-learning")
                }.padding(.horizontal, 12).modifier(ProfilePanel())
                VStack(alignment: .leading, spacing: 4) { CommunityGroupSection() }
                    .padding(12).modifier(ProfilePanel())
            }.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 680)
        }
        .campusScrollBackground().background(CampusTheme.background)
        .navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .navigationBarLeading) { CampusRootTitle(title: "我的") }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { ProfileSettingsView() } label: { Label("设置", systemImage: "slider.horizontal.3").labelStyle(.titleAndIcon).font(.subheadline) }
                    .accessibilityLabel("设置与帮助").accessibilityIdentifier("profile-settings")
            }
        }
        .confirmationDialog("断开后会移除本机教务会话及教务缓存，个人课程和待办不受影响。", isPresented: $disconnecting, titleVisibility: .visible) {
            Button("断开连接", role: .destructive) { store.disconnectSchool() }
        }
    }
    private func profileRow(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(CampusTheme.primary)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(CampusTheme.text)
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(CampusTheme.muted)
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
    private func shortcut<Content: View>(_ title: String, icon: String, @ViewBuilder destination: () -> Content) -> some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(CampusTheme.primary)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.text)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(CampusPressStyle()).accessibilityLabel(title)
    }

}

private struct ProfilePanel: ViewModifier {
    func body(content: Content) -> some View {
        content.background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CampusTheme.border, lineWidth: 1).allowsHitTesting(false))
    }
}

private struct ProfileSettingsView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var displayPreferences: DisplayPreferencesStore
    @EnvironmentObject var analytics: AnonymousAnalyticsStore
    @EnvironmentObject var quzhi: QuzhiStore
    @EnvironmentObject var pangguai: PangguaiStore
    @State private var managingPersonalSchedule = false

    var body: some View {
        List {
            Section("偏好与数据") {
                CampusAppearanceControls(store: displayPreferences) { message in store.message = message }
                NavigationLink { NativeReminderSettingsView(reminders: store.reminders) } label: { Label("通知设置", systemImage: "bell") }
                NavigationLink { PersonalBackupView() } label: { Label("缓存管理与备份", systemImage: "externaldrive") }
            }
            Section("学校服务") { Link("邯郸学院官网",destination:URL(string:"https://www.hdc.edu.cn/")!); NavigationLink("统一日程") { CampusAgendaView() } }
            Section("学校课表设置") {
                NavigationLink("学期校历") { SemesterCalendar() }
                DatePicker("学校第一周周一", selection: Binding(get: { store.schoolSemesterStart }, set: { store.calibrateSchoolStart($0) }), displayedComponents: .date)
                    .environment(\.timeZone, ScheduleMath.calendar.timeZone)
                Text("请与学校校历核对，按北京时间计算学校教学周。此处不修改个人学期。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Section("个人课表设置") {
                if let state = store.personalSchedule, let semester = state.semesters.first(where: { $0.id == state.activeSemesterId }) {
                    CampusLabeledValue("当前个人学期", value: semester.title)
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
            }
            Section("关于邯院通") {
                Text("学习 · 生活 · 校园")
                Text("iPhone 原生开发版。教务数据以学校官方系统为准；各服务需独立登录，真实账号和设备联调尚待完成。").font(.caption).foregroundStyle(CampusTheme.muted)
                NavigationLink("版本与更新日志") { CampusVersionPage() }
                NavigationLink("隐私与本机数据") { PrivacyView() }
                if analytics.state.hasIdentity { NavigationLink("旧版统计记录") { AnonymousAnalyticsSettingsView(store: analytics) } }
                NavigationLink("帮助与反馈") { NativeHelpView() }
            }
        }
        .campusScrollBackground().background(CampusTheme.background)
        .navigationTitle("设置与帮助").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $managingPersonalSchedule) { PersonalScheduleSettingsSheet() }
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
        CampusNavigation {
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
            Section("学校账号") { Text("请只在学校官方登录页面输入账号和密码。学校登录不会使用自制密码输入框。") }
            Section("树洞与邯院通账号") { Text(TreeholeView.rules) }
            Section("本机数据") { Text("个人课程与待办保存在本机。断开教务连接会清除教务会话与教务缓存，保留个人记录。") }
            Section("服务状态") { Text("当前为 iPhone 原生开发版，尚未完成全部 Android 功能迁移。第三方服务需由用户主动连接；付款和设备操作须核对确认，以平台实际状态为准。") }
        }.navigationTitle("隐私与本机数据").navigationBarTitleDisplayMode(.inline)
    }
}

struct AcademicRecordsView: View {
    @EnvironmentObject var store: CampusStore
    @State private var selection: Int
    init(initialSelection: Int = 0) { _selection = State(initialValue: initialSelection) }
    var body: some View {
        List {
            Section { Picker("教务记录", selection: $selection) { Text("成绩").tag(0); Text("考试").tag(1) }.pickerStyle(.segmented) }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if selection == 0 { NativeGradeAnalysisView(grades: store.grades, profile: store.academicProfile) }
            else { NativeExamRecordsView(exams: store.exams).onAppear { if !store.exams.isEmpty { MedalJournal.shared.unlock("exam",scope:store.schoolMedalScope) } } }
            if !store.isConnected { Button("连接教务系统") { store.connectSchool() }.disabled(store.isBusy) }
        }.campusScrollBackground().background(CampusTheme.background).navigationTitle("成绩与考试").navigationBarTitleDisplayMode(.inline)
            .toolbar { if store.isConnected { Button { store.refreshSchool() } label: { if store.isBusy { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(store.isBusy).accessibilityLabel("更新教务数据") } }
    }
}
