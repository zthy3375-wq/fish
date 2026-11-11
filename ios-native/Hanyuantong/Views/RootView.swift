import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: CampusStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { HomeView() }.tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
            NavigationStack { ScheduleView() }.tabItem { Label("课表", systemImage: "calendar") }.tag(AppTab.schedule)
            NavigationStack { TasksView() }.tabItem { Label("待办", systemImage: "checklist") }.tag(AppTab.tasks)
            NavigationStack { ProfileView() }.tabItem { Label("我的", systemImage: "person") }.tag(AppTab.profile)
        }
        .tint(CampusTheme.primary)
        .foregroundStyle(CampusTheme.text)
        .preferredColorScheme(.light)
        .environment(\.calendar, CampusTheme.calendar)
        .environment(\.timeZone, CampusTheme.calendar.timeZone)
        .alert("提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("知道了", role: .cancel) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: CampusStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                HStack {
                    Text("今日课程").font(.headline)
                    Spacer()
                    Button("查看课表 ›") { store.selectedTab = .schedule }.font(.subheadline)
                }
                let courses = store.courses(on: Date())
                if courses.isEmpty {
                    CampusEmpty(title: "今天暂无课程", detail: store.isConnected ? "享受自己的校园时光" : "连接教务系统，或在课表中添加个人课程", symbol: "sun.max")
                } else {
                    VStack(spacing: 10) { ForEach(courses) { course in NavigationLink { CourseDetailView(course: course) } label: { CourseRow(course: course) }.buttonStyle(.plain) } }
                }
                Text("校园生活").font(.headline)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NavigationLink { PendingServiceView(name: "趣智校园", detail: "洗澡余额、充值与记录") } label: { wallet("趣智校园", "洗澡余额", "洗澡 · 余额与充值", "drop", Color(hex: 0xeee5ff)) }
                        NavigationLink { PendingServiceView(name: "胖乖生活", detail: "饮水、洗衣与扫码设备") } label: { wallet("胖乖生活", "饮水余额", "饮水 · 洗衣 · 扫码", "washer", Color(hex: 0xe4f2eb)) }
                    }
                    HStack(spacing: 10) {
                        NavigationLink { PendingServiceView(name: "取快递", detail: "淘宝、拼多多出库码快捷入口") } label: { utility("取快递", "淘宝 · 拼多多", "shippingbox") }
                        NavigationLink { CampusMapView() } label: { utility("校园平面图", "东区 · 西区", "map") }
                    }
                }.buttonStyle(.plain)
                Text("学习与教务").font(.headline)
                VStack(spacing: 0) {
                    NavigationLink { AcademicRecordsView() } label: { Label("成绩与考试", systemImage: "graduationcap").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }
                    Divider()
                    NavigationLink { PendingServiceView(name: "学习通", detail: "课程、作业、考试与通知同步") } label: { HStack { Label("学习通", systemImage: "books.vertical"); Spacer(); Text("待接入").font(.caption).foregroundStyle(CampusTheme.muted) }.padding(.vertical, 12) }
                }.campusCard()
            }.padding(20).frame(maxWidth: 680)
        }.background(CampusTheme.background).toolbar(.hidden, for: .navigationBar)
    }
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            Image("campus-autumn").resizable().scaledToFill().frame(height: 275).clipped().accessibilityHidden(true)
            LinearGradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("邯院通").font(.system(size: 28, weight: .bold))
                Text("学习 · 生活 · 校园").font(.caption)
                Spacer()
                Text("校园里的事，\n简单一点。").font(.system(size: 24, weight: .semibold)).lineSpacing(5)
                Spacer()
                HStack { Text(CampusTheme.date(Date())); Spacer(); Text("第\(store.week(for: Date()))周") }.font(.caption).foregroundStyle(.white)
            }.padding(22)
        }.frame(height: 275).clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private func wallet(_ name: String, _ label: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(CampusTheme.muted)
            Text("待接入").font(.title2.bold())
            Text(detail).font(.caption2).foregroundStyle(CampusTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(color, in: RoundedRectangle(cornerRadius: 20))
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
