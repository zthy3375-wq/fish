import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject var tree:TreeholeStore
    @EnvironmentObject var store: CampusStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            CampusNavigation { HomeView() }.tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
            CampusNavigation { ScheduleView() }.tabItem { Label("课表", systemImage: "calendar") }.tag(AppTab.schedule)
            CampusNavigation { TreeholeView() }.tabItem { Label("社区", systemImage: "bubble.left.and.bubble.right") }.tag(AppTab.community)
            CampusNavigation { TasksView() }.tabItem { Label("待办", systemImage: "checklist") }.tag(AppTab.tasks)
            CampusNavigation { ProfileView() }.tabItem { Label("我的", systemImage: "person") }.tag(AppTab.profile)
        }

        .overlay(alignment:.top) { MedalOverlay() }
        .task { await tree.restoreCachedIdentity() }
        .onAppear { MedalJournal.shared.unlock("welcome") }
        .tint(CampusTheme.primary)
        .foregroundStyle(CampusTheme.text)
        .environment(\.calendar, CampusTheme.calendar)
        .environment(\.timeZone, CampusTheme.calendar.timeZone)
        .alert("提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("知道了", role: .cancel) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var learning: LearningStore
    @EnvironmentObject var quzhi: QuzhiStore
    @EnvironmentObject var pangguai: PangguaiStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    @State private var timelineOpen=false
    @AppStorage("home.announcements.enabled") private var announcementsEnabled = true
    @AppStorage("home.announcements.welcomeRead") private var welcomeRead = false
    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 194
    @State private var swimming=false
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("medal.reduce") private var reduceMotion=false
    private var allowsSwimming:Bool { scenePhase == .active && store.selectedTab == .home && !systemReduce && !reduceMotion }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                coursePanel
                Text("校园生活").font(.headline)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NavigationLink { QuzhiWalletView(store: quzhi) } label: { wallet("趣智校园", "洗澡余额", showerBalance, showerDetail, "drop", CampusTheme.walletPurple) }
                        NavigationLink { PangguaiWalletView(store: pangguai) } label: { wallet("胖乖生活", "饮水余额", pangguai.connected ? pangguai.waterBalanceText : "连接账户", waterDetail, "washer", CampusTheme.walletGreen) }
                    }
                    HStack(spacing: 10) {
                        NavigationLink { ParcelCenterView() } label: { utility("取快递", "淘宝 · 拼多多", "shippingbox") }
                        NavigationLink { CampusMapView() } label: { utility("校园平面图", "东区 · 西区", "map") }
                    }
                }.buttonStyle(.plain)
                todayTasks
                upcomingExams
            }.padding(.horizontal,16).padding(.vertical,8).frame(maxWidth:680)
        }.background(CampusTheme.background).campusNavigationBarHidden()
            .task(id: scenePhase == .active && store.selectedTab == .home) {
                guard scenePhase == .active, store.selectedTab == .home else { return }
                while !Task.isCancelled {
                    now = Date()
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { break }
                }
            }
            .onAppear { now=Date(); animateFish(allowsSwimming) }
            .onChange(of:allowsSwimming) { animateFish($0) }
            .onDisappear { animateFish(false) }

    }
    private func animateFish(_ active:Bool) {
        if !active { var transaction=Transaction(); transaction.disablesAnimations=true; withTransaction(transaction) {swimming=false} }
        else { withAnimation(.easeInOut(duration:2.0).repeatForever(autoreverses:true)) {swimming=true} }
    }
    private var coursePanel: some View {
        let today = store.courses(on: now)
        return VStack(spacing: 0) {
            if let focus = HomeCourseFocus.select(courses: store.courses, personalStart: store.semesterStart, schoolStart: store.schoolSemesterStart, now: now) {
                NavigationLink { CourseDetailView(course: focus.course, occurrenceDate: focus.start) } label: {
                    focusCard(focus)
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("暂时没有后续课程").font(.headline)
                    if !store.isConnected && store.courses.isEmpty {
                        Text("连接学校后，可在这里查看课程安排。").font(.caption).foregroundStyle(CampusTheme.muted)
                        Button("连接学校") { store.connectSchool() }
                            .font(.subheadline).frame(minHeight: 44).disabled(store.isBusy)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CampusTheme.tint)
            }
            HStack {
                if today.isEmpty { Text("今天没有课程").foregroundStyle(CampusTheme.muted) }
                else {
                    Button {
                        withAnimation(systemReduce || reduceMotion ? nil : .easeInOut(duration: 0.2)) { timelineOpen.toggle() }
                    } label: {
                        HStack { Text("今日课程 · \(today.count) 节"); Image(systemName: timelineOpen ? "chevron.up" : "chevron.down") }
                    }.accessibilityValue(timelineOpen ? "已展开" : "已收起")
                }
                Spacer()
                Button("查看课表") { store.selectedDate = now; store.selectedTab = .schedule }
                    .accessibilityIdentifier("home-open-schedule")
            }.font(.subheadline).frame(minHeight: 44).padding(.horizontal, 14)
            if timelineOpen {
                ForEach(today) { course in
                    NavigationLink { CourseDetailView(course: course, occurrenceDate: now) } label: {
                        CourseRow(course: course)
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            HStack(spacing: 0) {
                NavigationLink { LearningCenterView(store: learning) } label: {
                    Label("学习通", systemImage: "books.vertical").frame(maxWidth: .infinity, minHeight: 44)
                }
                Divider().frame(height: 20)
                NavigationLink { AcademicRecordsView() } label: {
                    Label("成绩与学业", systemImage: "graduationcap").frame(maxWidth: .infinity, minHeight: 44)
                }
            }.font(.subheadline.weight(.medium))
        }
        .background(CampusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(CampusTheme.border, lineWidth: 0.5).allowsHitTesting(false))
    }
    private func focusCard(_ focus: HomeCourseFocus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(focus.isCurrent(at: now) ? "正在上课" : "下一节课", systemImage: "graduationcap")
                Spacer()
                Text(focus.isCurrent(at: now) ? "进行中" : CampusTheme.date(focus.start, format: "M月d日 HH:mm")).font(.caption)
            }.foregroundStyle(CampusTheme.primary)
            HStack(alignment:.firstTextBaseline,spacing:12) {
                VStack(alignment:.leading) { Text(focus.course.start).font(.title2.monospacedDigit().weight(.semibold)); Text("至 " + focus.course.end).font(.caption).foregroundStyle(.secondary) }
                Text(focus.course.name).font(.title3.weight(.semibold)).frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            Text([focus.course.room.isEmpty ? "教室待定" : focus.course.room, focus.course.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(CampusTheme.muted)
            if focus.isCurrent(at: now) {
                ProgressView(value: focus.progress(at: now)).tint(CampusTheme.primary)
                    .accessibilityLabel("课程进度")
                    .accessibilityValue("剩余 \(focus.remainingMinutes(at: now)) 分钟")
                Text("剩余 \(focus.remainingMinutes(at: now)) 分钟").font(.caption).foregroundStyle(CampusTheme.muted)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(CampusTheme.tint)
    }
    @ViewBuilder private var todayTasks: some View {
        let pending = TaskRules.select(store.tasks, filter: TaskFilter(scope: .today), now: now)
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("今日待办").font(.headline); Spacer(); Button("查看全部 ›") { store.selectedTab = .tasks }.font(.subheadline) }
                ForEach(pending.prefix(3)) { task in
                    HStack {
                        Image(systemName: "circle").foregroundStyle(CampusTheme.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.subheadline)
                            if let deadline = task.deadline { Text("截止 " + TaskPresentation.date(deadline)).font(.caption).foregroundStyle(CampusTheme.muted) }
                        }
                        Spacer()
                    }.contentShape(Rectangle()).onTapGesture { store.selectedTab = .tasks }
                }
            }.campusCard()
        }
    }
    @ViewBuilder private var upcomingExams: some View {
        let exams = NativeExamPresentation.upcoming(store.exams, now: now)
        if !exams.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("近期考试").font(.headline)
                    Spacer()
                    NavigationLink("查看全部 ›") { List { NativeExamRecordsView(exams: store.exams) }.navigationTitle("考试安排") }.font(.subheadline)
                }
                ForEach(exams.prefix(3)) { exam in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(exam.name).font(.subheadline.weight(.semibold)); Spacer(); Text(NativeExamPresentation.dayLabel(exam, now: now)).font(.caption).foregroundStyle(CampusTheme.primary) }
                        Text([exam.date, exam.time, exam.room].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(CampusTheme.muted)
                    }
                }
            }.campusCard()
        }
    }
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                Image("campus-autumn").resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: heroHeight).clipped()
            }.accessibilityHidden(true)
            LinearGradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("邯院通").font(.system(size: 28, weight: .bold))
                Text("学习 · 生活 · 校园").font(.caption)
                Spacer()
                Text("校园里的事，\n简单一点。").font(.system(.title3, design: .serif)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack { Text(CampusTheme.date(now)); Spacer(); Text("第\(store.week(for: now))周") }.font(.caption).foregroundStyle(.white)
            }.padding(14)
            HStack {
                Spacer()
                NavigationLink {
                    HomeAnnouncementView(enabled: $announcementsEnabled, read: $welcomeRead)
                } label: {
                    Image(systemName: "bell").foregroundStyle(CampusTheme.text)
                        .frame(width: 36, height: 36).background(CampusTheme.surface.opacity(0.92), in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if announcementsEnabled && !welcomeRead {
                                Circle().fill(.red).frame(width: 7, height: 7).padding(3)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("通知设置")
                .accessibilityValue(announcementsEnabled && !welcomeRead ? "有未读公告" : "")
            }.padding(8)
            VStack { Spacer(); HStack { Spacer(); DiscoverySurface("puff",label:"首页小金鱼",taps:5,canDream:true) { CampusHeroFish().frame(width:84,height:52).rotationEffect(.degrees(swimming ? 2 : -1)).offset(y:swimming ? -3 : 0) } } }
                .padding(.trailing, 14).padding(.bottom, 25)
        }.frame(height: heroHeight).clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private func wallet(_ name: String, _ label: String, _ balance: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(CampusTheme.muted)
            Text(balance).font(.title2.bold()).monospacedDigit().privacySensitive()
            Text(detail).font(.caption2).foregroundStyle(CampusTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(LinearGradient(colors: [color, CampusTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }
    private var showerBalance: String {
        guard quzhi.connected else { return "连接账户" }
        return quzhi.snapshot.wallet == nil ? "待查询" : "¥" + quzhi.balanceText
    }
    private var showerDetail: String {
        if quzhi.expired { return "登录已失效 · 请重新连接" }
        return quzhi.connected ? "上次查询 · 充值与记录" : "洗澡 · 余额与充值"
    }
    private var waterDetail: String {
        if pangguai.expired { return "登录已失效 · 请重新连接" }
        if pangguai.snapshot.water?.terminal == false { return "查看当前接水记录" }
        return pangguai.connected ? "上次查询 · 饮水与洗衣" : "饮水 · 洗衣 · 扫码"
    }
    private func utility(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundStyle(CampusTheme.primary); VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption2).foregroundStyle(CampusTheme.muted) } }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CourseRow: View {
    let course: Course
    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 3).fill(CampusTheme.course(course.color)).frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(course.name).font(.subheadline.weight(.semibold))
                Text([course.room, course.teacher].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) { Text(course.start).font(.subheadline.weight(.medium)); Text(course.end).font(.caption).foregroundStyle(CampusTheme.muted) }
        }.fixedSize(horizontal: false, vertical: true).campusCard().accessibilityElement(children: .combine)
    }
}

struct PendingServiceView: View {
    let name: String
    let detail: String
    var body: some View {
        ScrollView { CampusEmpty(title: "iPhone 版本待接入", detail: "\(detail)\n此功能尚未完成原生适配，当前不能登录、查询或支付。", symbol: "wrench.and.screwdriver").padding(20) }.background(CampusTheme.background).navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    }
}

/// Fixed native rendering of CampusHero.vue's original 180 × 112 fish SVG.
/// Deliberately static: there is no continuous motion, including with Reduce Motion enabled.
private struct CampusHeroFish: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 180, y: size.height / 112)
            let ink = Color(hex: 0x30243b)
            let stroke = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
            var flag = Path()
            flag.move(to: CGPoint(x: 84, y: 39)); flag.addLine(to: CGPoint(x: 91, y: 9))
            flag.addCurve(to: CGPoint(x: 125, y: 10), control1: CGPoint(x: 103, y: 3), control2: CGPoint(x: 111, y: 17))
            flag.addLine(to: CGPoint(x: 120, y: 32))
            flag.addCurve(to: CGPoint(x: 88, y: 30), control1: CGPoint(x: 106, y: 40), control2: CGPoint(x: 101, y: 24))
            context.fill(flag, with: .color(Color(hex: 0xfff9ed))); context.stroke(flag, with: .color(ink), style: stroke)
            var body = Path()
            body.move(to: CGPoint(x: 18, y: 66))
            body.addCurve(to: CGPoint(x: 81, y: 39), control1: CGPoint(x: 29, y: 43), control2: CGPoint(x: 56, y: 34))
            body.addCurve(to: CGPoint(x: 130, y: 55), control1: CGPoint(x: 105, y: 40), control2: CGPoint(x: 115, y: 51))
            body.addCurve(to: CGPoint(x: 158, y: 46), control1: CGPoint(x: 145, y: 40), control2: CGPoint(x: 158, y: 35))
            body.addCurve(to: CGPoint(x: 148, y: 64), control1: CGPoint(x: 158, y: 53), control2: CGPoint(x: 150, y: 61))
            body.addCurve(to: CGPoint(x: 155, y: 84), control1: CGPoint(x: 156, y: 70), control2: CGPoint(x: 162, y: 80))
            body.addCurve(to: CGPoint(x: 130, y: 76), control1: CGPoint(x: 148, y: 88), control2: CGPoint(x: 137, y: 78))
            body.addCurve(to: CGPoint(x: 60, y: 93), control1: CGPoint(x: 108, y: 88), control2: CGPoint(x: 86, y: 99))
            body.addCurve(to: CGPoint(x: 18, y: 66), control1: CGPoint(x: 40, y: 90), control2: CGPoint(x: 22, y: 81)); body.closeSubpath()
            context.fill(body, with: .color(Color(hex: 0xfff6e9))); context.stroke(body, with: .color(ink), style: stroke)
            context.fill(Path(ellipseIn: CGRect(x: 39.8, y: 58.8, width: 6.4, height: 6.4)), with: .color(ink))
            var smile = Path(); smile.move(to: CGPoint(x: 63, y: 73)); smile.addQuadCurve(to: CGPoint(x: 76, y: 73), control: CGPoint(x: 70, y: 78))
            context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            var sparks = Path()
            sparks.move(to: CGPoint(x: 19, y: 38)); sparks.addLine(to: CGPoint(x: 11, y: 29))
            sparks.move(to: CGPoint(x: 32, y: 30)); sparks.addLine(to: CGPoint(x: 28, y: 18))
            sparks.move(to: CGPoint(x: 45, y: 27)); sparks.addLine(to: CGPoint(x: 47, y: 15))
            context.stroke(sparks, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}


private struct HomeAnnouncementView: View {
    @EnvironmentObject var store: CampusStore
    @Binding var enabled: Bool
    @Binding var read: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    Button { enabled.toggle() } label: {
                        Text("应用内提醒")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Toggle("应用内提醒", isOn: $enabled).labelsHidden()
                }
                .accessibilityRepresentation { Toggle("应用内提醒", isOn: $enabled) }
                NavigationLink("设置课程提醒与系统权限") { NativeReminderSettingsView(reminders: store.reminders) }
            }
            if enabled {
                Section("项目公告") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("欢迎使用邯院通").font(.headline)
                        Text("连接学校后可以同步课表，离线时可查看上次保存的课程。学校公告请前往学校官网查看。")
                        Text(read ? "已读" : "未读").font(.caption).foregroundStyle(CampusTheme.muted)
                    }.padding(.vertical, 4)
                    if !read { Button("全部标为已读") { read = true } }
                }
            }
        }.navigationTitle("通知设置").navigationBarTitleDisplayMode(.inline)
    }
}
