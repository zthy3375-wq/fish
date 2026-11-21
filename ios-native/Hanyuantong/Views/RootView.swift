import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject var tree:TreeholeStore
    @EnvironmentObject var store: CampusStore
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage("medal.reduce") private var localReduce = false
    var body: some View {
        TabView(selection: $store.selectedTab) {
            CampusNavigation { HomeView().modifier(reveal(.home)).background(tabChrome) }.tabItem { Label("首页", image: "tab-House") }.tag(AppTab.home)
            CampusNavigation { ScheduleView().modifier(reveal(.schedule)).background(tabChrome) }.tabItem { Label("课表", image: "tab-CalendarDays") }.tag(AppTab.schedule)
            CampusNavigation { TreeholeView().modifier(reveal(.community)).background(tabChrome) }.tabItem { Label("社区", image: "tab-MessagesSquare") }.tag(AppTab.community)
            CampusNavigation { TasksView().modifier(reveal(.tasks)).background(tabChrome) }.tabItem { Label("待办", image: "tab-ListTodo") }.tag(AppTab.tasks)
            CampusNavigation { ProfileView().modifier(reveal(.profile)).background(tabChrome) }.tabItem { Label("我的", image: "tab-UserRound") }.tag(AppTab.profile)
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
    private func reveal(_ tab: AppTab) -> CampusPageReveal {
        CampusPageReveal(active: store.selectedTab == tab, reduce: reduce || localReduce)
    }
    private var tabChrome: some View {
        CampusTabChrome(selection: store.selectedTab, reduceMotion: reduce || localReduce).frame(width: 0, height: 0)
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
    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 224
    @State private var paused = false
    @State private var swimStarted: Date?
    @State private var swimElapsed: TimeInterval = 0
    @State private var fishPressed = false
    @State private var fishTaps = TapSequence()
    @State private var lastFishResponse: String?
    @State private var fishCue: String?
    @State private var fishTouchSerial = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage("medal.reduce") private var reduceMotion=false
    private var allowsSwimming:Bool { scenePhase == .active && store.selectedTab == .home && !systemReduce && !reduceMotion && !paused && !fishPressed }

    var body: some View {
        GeometryReader { screen in
            ScrollView {
                VStack(spacing: 0) {
                    hero(safeTop: screen.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 14) {
                        coursePanel
                        Text("校园生活").font(.headline)
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                NavigationLink { QuzhiWalletView(store: quzhi) } label: { wallet("趣智校园", "洗澡余额", showerBalance, showerDetail, "drop", CampusTheme.walletPurple, CampusTheme.primary) }.accessibilityIdentifier("home-quzhi")
                                NavigationLink { PangguaiWalletView(store: pangguai) } label: { wallet("胖乖生活", "饮水余额", pangguai.connected ? pangguai.waterBalanceText : "连接账户", waterDetail, "washer", CampusTheme.walletGreen, CampusTheme.course("green")) }.accessibilityIdentifier("home-pangguai")
                            }.fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 0) {
                                NavigationLink { ParcelCenterView() } label: { utility("取快递", "淘宝 · 拼多多出库码", "shippingbox") }
                                Rectangle().fill(CampusTheme.border).frame(width: 1).accessibilityHidden(true)
                                NavigationLink { CampusMapView() } label: { utility("校园平面图", "东区 · 西区", "map") }.accessibilityIdentifier("home-campus-map")
                            }.fixedSize(horizontal: false, vertical: true)
                                .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(CampusTheme.border).allowsHitTesting(false) }
                        }.buttonStyle(CampusPressStyle())
                        todayTasks
                        upcomingExams
                    }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: 680)
                }
            }.ignoresSafeArea(.container, edges: .top)
        }.background(CampusTheme.background).campusNavigationBarHidden()
            .task(id: scenePhase == .active && store.selectedTab == .home) {
                guard scenePhase == .active, store.selectedTab == .home else { return }
                while !Task.isCancelled {
                    now = Date()
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { break }
                }
            }
            .onAppear { now = Date(); setSwimming(allowsSwimming) }
            .onChange(of: allowsSwimming) { setSwimming($0) }
            .onDisappear { setSwimming(false) }
    }
    private func setSwimming(_ enabled: Bool) {
        if enabled && swimStarted == nil { swimStarted = Date() }
        if !enabled, let started = swimStarted {
            swimElapsed += max(0, Date().timeIntervalSince(started))
            swimStarted = nil
        }
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
                    Text("暂时没有后续课程").font(.system(size: 20, weight: .bold))
                    Text(!store.isConnected || store.lastSynced == nil ? "连接学校后，可在这里查看课程安排。" : "未找到后续课程，可在课表中查看或添加课程。")
                        .font(.caption).foregroundStyle(CampusTheme.muted)
                    let canOpenSchedule = store.isConnected || !store.courses.isEmpty
                    Button {
                        if canOpenSchedule { store.selectedDate = now; store.selectedTab = .schedule }
                        else { store.selectedTab = .profile }
                    } label: {
                        Label(canOpenSchedule ? "打开课表" : "连接学校", systemImage: "chevron.right")
                            .labelStyle(TitleThenIconLabel()).font(.subheadline).foregroundStyle(CampusTheme.primary).frame(minHeight: 44)
                    }.disabled(store.isBusy && !canOpenSchedule)
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
                Button {
                    store.selectedDate = now; store.selectedTab = .schedule
                } label: {
                    Label("查看课表", systemImage: "chevron.right").labelStyle(TitleThenIconLabel())
                }.foregroundStyle(CampusTheme.primary).accessibilityIdentifier("home-open-schedule")
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
                    studyShortcut("学习通", symbol: "books.vertical")
                }
                Divider().frame(height: 20)
                NavigationLink { AcademicRecordsView() } label: {
                    studyShortcut("成绩与学业", symbol: "chart.bar.xaxis")
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
    private func hero(safeTop: CGFloat) -> some View {
        let ink = scheme == .dark ? Color.white : Color(hex: 0x302044)
        let badge = scheme == .dark ? Color(hex: 0x2e223c).opacity(0.82) : Color.white.opacity(0.68)
        let height = heroHeight + safeTop
        return GeometryReader { bounds in
            ZStack(alignment: .topLeading) {
                let artHeight = max(height, bounds.size.width * 2 / 3)
                Image("campus-autumn").resizable().scaledToFill()
                    .frame(width: bounds.size.width, height: artHeight)
                    .offset(y: -(artHeight - height) * 0.7)
                    .frame(width: bounds.size.width, height: height, alignment: .top).clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [scheme == .dark ? .black.opacity(0.65) : Color(hex: 0xfff6fc).opacity(0.42), .clear],
                               startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("邯院通").font(.custom("Songti SC", size: 37, relativeTo: .largeTitle)).fontWeight(.bold).tracking(1)
                            Capsule().fill(Color(hex: 0x7553a6)).frame(width: 76, height: 2).rotationEffect(.degrees(-5)).padding(.leading, 30)
                            Text("学习 · 生活 · 校园").font(.system(size: 10)).tracking(3).padding(.top, 8)
                        }
                        Spacer()
                        NavigationLink { HomeAnnouncementView(enabled: $announcementsEnabled, read: $welcomeRead) } label: {
                            Image(systemName: "bell").font(.system(size: 20)).frame(width: 44, height: 44)
                                .background(badge, in: Circle()).overlay(alignment: .topTrailing) {
                                    if announcementsEnabled && !welcomeRead { Circle().fill(Color(hex: 0xb14f55)).frame(width: 6, height: 6).padding(9) }
                                }
                        }.accessibilityLabel("通知设置")
                    }
                    Text("校园里的事，\n简单一点。").font(.custom("Songti SC", size: 15, relativeTo: .body))
                        .tracking(2).lineSpacing(4).padding(.top, 15)
                    Spacer()
                    Text(CampusTheme.date(now, format: "M月d日 · EEE") + "   " + teachingWeek)
                        .font(.caption2).padding(.horizontal, 9).padding(.vertical, 5).background(badge, in: Capsule())
                }.padding(.horizontal, 24).padding(.top, safeTop + 20).padding(.bottom, 9)
                ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !allowsSwimming)) { timeline in
                        let t = swimElapsed + (swimStarted.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0)
                        let cycle = t.truncatingRemainder(dividingBy: 17) / 17
                        let bob = cos(t * 2 * .pi / 2.9)
                        VStack(spacing: -6) {
                            CampusHeroFish().frame(width: 94, height: 60)
                            Ellipse().stroke(.white.opacity(0.6), lineWidth: 1).frame(width: 61, height: 7)
                        }.rotationEffect(.degrees(-2 * bob))
                            .scaleEffect(x: cycle < 0.48 || cycle >= 0.98 ? 1 : -1, y: 1)
                            .scaleEffect(fishPressed && !systemReduce && !reduceMotion ? 0.94 : 1)
                            .offset(x: CGFloat(18 * cos(2 * .pi * cycle)), y: CGFloat(2 * bob))
                    }.allowsHitTesting(false).accessibilityHidden(true)
                    DiscoveryTouchTarget(label: "首页小金鱼", identifier: "home-mascot", lastResponse: lastFishResponse, pressing: { fishPressed = $0 }, tap: {
                        if fishTaps.tap(target: 5) {
                            MedalJournal.shared.unlock("puff"); showFishCue("别戳啦！")
                        } else { showFishCue("咕噜") }
                    }, longPress: {
                        fishTaps = TapSequence()
                        MedalJournal.shared.unlock("dream"); showFishCue("呼……")
                    }, cancel: { fishTaps = TapSequence() })
                    if let fishCue {
                        Text(fishCue).font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(badge, in: Capsule()).offset(y: -34).allowsHitTesting(false)
                            .accessibilityIdentifier("home-fish-cue")
                    }
                }.frame(width: 138, height: 76)
                    .offset(x: bounds.size.width * 0.35 - 22, y: height - 102)
                    .task(id: fishTouchSerial) {
                        guard fishCue != nil else { return }
                        do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
                        fishCue = nil
                    }
                if !systemReduce && !reduceMotion {
                    Button { paused.toggle() } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill").font(.caption2)
                            .padding(5).background(badge, in: Circle()).frame(width: 44, height: 44)
                    }.accessibilityLabel(paused ? "播放小鱼动画" : "暂停小鱼动画")
                        .position(x: bounds.size.width - 30, y: height - 22)
                }
            }.foregroundStyle(ink).buttonStyle(CampusPressStyle()).clipped()
        }.frame(height: height)
    }
    private func studyShortcut(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(CampusTheme.primary).accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(CampusTheme.muted).accessibilityHidden(true)
        }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
    }

    private func showFishCue(_ text: String) {
        lastFishResponse = text; fishCue = text; fishTouchSerial += 1
    }
    private var teachingWeek: String {
        let week = store.week(for: now)
        return (1...store.scheduleWeekCount).contains(week) ? "第 \(week) 教学周" : "学期外"
    }
    private func wallet(_ name: String, _ label: String, _ balance: String, _ detail: String, _ icon: String, _ fill: Color, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 2)
                Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
            }.foregroundStyle(ink)
            Text(label).font(.caption2).foregroundStyle(CampusTheme.muted).padding(.top, 6)
            Text(balance).font(.title3.bold()).monospacedDigit().privacySensitive()
            Spacer(minLength: 0)
            Text(detail).font(.caption2).foregroundStyle(CampusTheme.muted)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
            .background(LinearGradient(colors: [fill, CampusTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(CampusTheme.border).allowsHitTesting(false) }
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
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(CampusTheme.primary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.footnote.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(CampusTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(CampusTheme.muted).accessibilityHidden(true)
        }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
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
/// Motion is applied to this artwork by the hero timeline.
struct CampusHeroFish: View {
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


struct HomeAnnouncementView: View {
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
