import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject var store: CampusStore
    @EnvironmentObject var analytics: AnonymousAnalyticsStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { HomeView() }.tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
            NavigationStack { ScheduleView() }.tabItem { Label("课表", systemImage: "calendar") }.tag(AppTab.schedule)
            NavigationStack { TasksView() }.tabItem { Label("待办", systemImage: "checklist") }.tag(AppTab.tasks)
            NavigationStack { ProfileView() }.tabItem { Label("我的", systemImage: "person") }.tag(AppTab.profile)
        }
        .onChange(of: store.selectedTab) { tab in
            if tab == .schedule { analytics.recordFeature(.schedule) }
            if tab == .tasks { analytics.recordFeature(.tasks) }
        }
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let focus = HomeCourseFocus.select(courses: store.courses, personalStart: store.semesterStart, schoolStart: store.schoolSemesterStart, now: now) {
                    NavigationLink { CourseDetailView(course: focus.course) } label: { focusCard(focus) }.buttonStyle(.plain)
                }
                HStack {
                    Text("今日课程").font(.headline)
                    Spacer()
                    Button("查看课表 ›") { store.selectedTab = .schedule }.font(.subheadline)
                }
                let courses = store.courses(on: now)
                if courses.isEmpty {
                    CampusEmpty(title: "今天暂无课程", detail: store.isConnected ? "享受自己的校园时光" : "连接教务系统，或在课表中添加个人课程", symbol: "sun.max")
                } else {
                    VStack(spacing: 10) { ForEach(courses) { course in NavigationLink { CourseDetailView(course: course) } label: { CourseRow(course: course) }.buttonStyle(.plain) } }
                }
                todayTasks
                upcomingExams
                Text("校园生活").font(.headline)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NavigationLink { QuzhiWalletView(store: quzhi) } label: { wallet("趣智校园", "洗澡余额", "洗澡 · 余额与充值", "drop", CampusTheme.walletPurple) }
                        NavigationLink { PangguaiWalletView(store: pangguai) } label: { wallet("胖乖生活", "饮水余额", "饮水 · 洗衣 · 扫码", "washer", CampusTheme.walletGreen) }
                    }
                    HStack(spacing: 10) {
                        NavigationLink { ParcelCenterView() } label: { utility("取快递", "淘宝 · 拼多多", "shippingbox") }
                        NavigationLink { CampusMapView() } label: { utility("校园平面图", "东区 · 西区", "map") }
                    }
                }.buttonStyle(.plain)
                Text("学习与教务").font(.headline)
                VStack(spacing: 0) {
                    NavigationLink { AcademicRecordsView() } label: { Label("成绩与考试", systemImage: "graduationcap").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }
                    Divider()
                    NavigationLink { LearningCenterView(store: learning) } label: { HStack { Label("学习通", systemImage: "books.vertical"); Spacer(); Text("作业 · 考试").font(.caption).foregroundStyle(CampusTheme.muted) }.padding(.vertical, 12) }
                }.campusCard()
            }.padding(20).frame(maxWidth: 680)
        }.background(CampusTheme.background).toolbar(.hidden, for: .navigationBar)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    now = Date()
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                }
            }
            .onAppear { now = Date() }
    }
    private func focusCard(_ focus: HomeCourseFocus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(focus.isCurrent(at: now) ? "正在上课" : "下一节课", systemImage: "graduationcap")
                Spacer()
                Text(focus.isCurrent(at: now) ? "进行中" : CampusTheme.date(focus.start, format: "M月d日 HH:mm")).font(.caption)
            }.foregroundStyle(CampusTheme.primary)
            Text(focus.course.name).font(.title3.weight(.semibold))
            Text([focus.course.room.isEmpty ? "教室待定" : focus.course.room, focus.course.teacher, focus.course.start + "–" + focus.course.end].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(CampusTheme.muted)
            if focus.isCurrent(at: now) {
                ProgressView(value: focus.progress(at: now)).tint(CampusTheme.primary)
                    .accessibilityLabel("课程进度")
                    .accessibilityValue("剩余 \(focus.remainingMinutes(at: now)) 分钟")
                Text("剩余 \(focus.remainingMinutes(at: now)) 分钟").font(.caption).foregroundStyle(CampusTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).campusCard()
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
                    .frame(width: proxy.size.width, height: 275).clipped()
            }.accessibilityHidden(true)
            LinearGradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("邯院通").font(.system(size: 28, weight: .bold))
                Text("学习 · 生活 · 校园").font(.caption)
                Spacer()
                Text("校园里的事，\n简单一点。").font(.system(size: 24, weight: .semibold)).lineSpacing(5)
                Spacer()
                HStack { Text(CampusTheme.date(now)); Spacer(); Text("第\(store.week(for: now))周") }.font(.caption).foregroundStyle(.white)
            }.padding(22)
            VStack { Spacer(); HStack { Spacer(); CampusHeroFish().frame(width: 108, height: 68) } }
                .padding(.trailing, 14).padding(.bottom, 48).allowsHitTesting(false).accessibilityHidden(true)
        }.frame(height: 275).clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private func wallet(_ name: String, _ label: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(CampusTheme.muted)
            Text(walletBalance(name)).font(.title2.bold())
            Text(detail).font(.caption2).foregroundStyle(CampusTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(color, in: RoundedRectangle(cornerRadius: 20))
    }
    private func walletBalance(_ name: String) -> String {
        if name == "趣智校园" { return quzhi.expired ? "登录已过期" : quzhi.connected ? quzhi.balanceText : "未连接" }
        return pangguai.expired ? "登录已过期" : pangguai.connected ? (pangguai.snapshot.balance.map { "¥" + $0 } ?? "未读取") : "未连接"
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
