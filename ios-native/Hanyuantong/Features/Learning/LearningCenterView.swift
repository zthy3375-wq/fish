import SwiftUI
import UIKit

/// Embed inside the app NavigationStack. Own the store above this view so tab changes preserve state.
struct LearningCenterView: View {
    @ObservedObject var store: LearningStore
    @State private var section = "homework"
    @State private var filter = "pending"
    @State private var search = ""
    @State private var courseScope = "all"
    @State private var courseKey = ""
    @State private var showAccount = false
    @State private var confirmLogout = false
    @State private var detail: LearningItem?
    private let filters = [("pending", "待提交"), ("unknown", "待核对"), ("submitted", "已提交"), ("closed", "已截止"), ("all", "全部")]
    private var homework: [LearningItem] { store.cache.items.filter { $0.kind == "homework" } }
    private var filtered: [LearningItem] {
        let input = section == "exams" ? store.cache.items.filter { $0.kind == "exam" } : homework
        return input.filter { item in
            (section == "exams" || filter == "all" || LearningDisplay.state(item).key == filter) &&
            (courseKey.isEmpty || section == "exams" || item.courseKey == courseKey) &&
            (search.isEmpty || (item.title + " " + item.course).localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespaces)))
        }.sorted { (LearningDisplay.date($0.deadline) ?? .distantFuture) < (LearningDisplay.date($1.deadline) ?? .distantFuture) }
    }
    private var courses: [LearningCourse] {
        store.cache.courses.filter {
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespaces))) &&
            (courseScope == "all" || (courseScope == "followed" && store.cache.selectedCourses.contains($0.key)) || (courseScope == "failed" && failed($0.key)))
        }.sorted { a, b in
            let af = store.cache.selectedCourses.contains(a.key), bf = store.cache.selectedCourses.contains(b.key)
            return af != bf ? af : a.name.localizedCompare(b.name) == .orderedAscending
        }
    }
    private func failed(_ key: String) -> Bool { ["error", "partial"].contains(store.cache.courseSync[key]?.status ?? "") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(store.connected ? "学习通已连接" : "课程与作业，一处查看").font(.subheadline).foregroundStyle(CampusTheme.muted)
                    Spacer()
                    if store.connected { Button { select("notices") } label: { Label("通知", systemImage: "bell").font(.subheadline) }.accessibilityLabel("学习通通知") }
                    Button { showAccount.toggle() } label: { Image(systemName: "slider.horizontal.3").frame(width: 40, height: 44) }.accessibilityLabel("学习通账号设置")
                }
                if showAccount || !store.connected || store.needsLogin { accountCard }
                if store.connected {
                    navigation
                    syncStatus
                    if section != "notices" { searchField }
                    if section == "courses" { courseList }
                    else if section == "notices" { noticeList }
                    else { workList }
                } else {
                    CampusEmpty(title: "先连接学习通", detail: "在官方页面自行登录，再选择需要关注的课程。账号、会话和本机计划与教务数据独立。", symbol: "book.closed")
                }
                if let message = store.message {
                    Text(message).font(.footnote).foregroundStyle(CampusTheme.muted).frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(message)
                }
            }.padding(20)
        }
        .background(CampusTheme.background)
        .foregroundStyle(CampusTheme.text)
        .tint(CampusTheme.primary)
        .navigationTitle("学习通")
        .navigationBarTitleDisplayMode(.inline)
        .background(LearningPresenterAnchor { store.attachPresenter($0) }.frame(width: 0, height: 0))
        .confirmationDialog("退出会清除此学习通账号在本机的课程、作业、通知与计划。个人待办和教务数据不受影响。", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出学习通连接", role: .destructive) { store.logout() }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $detail) { item in
            LearningItemDetail(store: store, item: item) {
                detail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.openItem(item) }
            }
        }
    }
    private func select(_ section: String) { self.section = section; search = "" }
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.connected ? "学习通账号" : "连接学习通", systemImage: "book.closed").font(.headline)
            Text("仅查询本人数据；密码在学习通官方页面输入，会话加密保存在这台设备。计划和备注只保存本机，提交状态以平台为准。")
                .font(.footnote).foregroundStyle(CampusTheme.muted)
            if store.needsCleanup {
                Button("重试清理学习通数据", role: .destructive) { store.logout() }.buttonStyle(.bordered)
            } else if store.needsLogin {
                Button(store.cache.issues["connection"] == "VERIFY" ? "完成验证并继续" : store.connected ? "重新连接学习通" : "连接学习通") { store.login() }.buttonStyle(.borderedProminent).foregroundStyle(CampusTheme.onPrimary).disabled(store.blocked)
            }
            if store.connected {
                HStack {
                    Button("打开学习通官方页面") { store.openPortal() }.disabled(store.blocked)
                    Spacer()
                    Button("退出", role: .destructive) { confirmLogout = true }.disabled(store.blocked)
                }.font(.subheadline).frame(minHeight: 44)
            }
            if !store.cache.issues.isEmpty {
                ShareLink(item: store.feedbackText) { Label("导出连接反馈（不含账号或任务内容）", systemImage: "square.and.arrow.up").font(.caption) }.frame(minHeight: 44)
            }
            if store.isOpening { HStack { ProgressView(); Text("官方页面打开中").font(.footnote) } }
        }.campusCard()
    }
    private var navigation: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                tab("homework", "作业", "doc.text")
                tab("exams", "考试", "pencil.and.outline")
            }
            Button { select("courses") } label: {
                HStack(spacing: 12) {
                    Image(systemName: "books.vertical").font(.title2).frame(width: 40)
                    VStack(alignment: .leading, spacing: 4) { Text("课程管理").font(.headline); Text("选择课程 · 更新作业").font(.caption).foregroundStyle(CampusTheme.muted) }
                    Spacer(minLength: 5)
                    Text("\(store.cache.selectedCourses.count) 门已关注").font(.caption)
                    Image(systemName: "chevron.right").font(.caption)
                }.campusCard()
            }.buttonStyle(.plain)
        }
    }
    private func tab(_ key: String, _ title: String, _ symbol: String) -> some View {
        Button { select(key) } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                .background(section == key ? CampusTheme.tint : CampusTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(section == key ? .isSelected : [])
    }
    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(section == "homework" ? (store.pendingCount > 0 ? "\(store.pendingCount) 份作业待提交" : "看看今天的学习任务") : section == "courses" ? "我的课程" : section == "exams" ? "学习通考试" : "学习通通知").font(.title3.weight(.semibold))
                    Text(store.status).font(.caption).foregroundStyle(CampusTheme.muted)
                }
                Spacer(minLength: 4)
                Button { store.cache.selectedCourses.isEmpty ? select("courses") : store.sync() } label: { Label("更新", systemImage: "arrow.clockwise").font(.subheadline).frame(minHeight: 44) }.disabled(store.blocked || store.needsLogin)
            }
            if store.isBusy || store.cache.cursor != nil {
                ProgressView(value: Double(store.cache.cursor ?? 0), total: Double(max(1, store.cache.activeCourses.count)))
                HStack {
                    Text("已处理 \(store.cache.cursor ?? 0) / \(store.cache.activeCourses.count) 门").font(.caption)
                    Spacer()
                    if store.isBusy {
                        Button(store.pauseRequested ? "等待暂停" : "暂停") { store.pause() }.disabled(store.pauseRequested).font(.subheadline)
                    } else {
                        Button("继续更新") { store.sync(resume: true) }.disabled(store.needsLogin || store.blocked).font(.subheadline)
                    }
                }.frame(minHeight: 36)
            }
            if store.cache.issues["connection"] != nil {
                Text(LearningError(code: store.cache.issues["connection"]!).localizedDescription).font(.footnote).foregroundStyle(.orange)
            }
            let failures = store.cache.courseSync.values.filter { $0.status != "ok" }.count
            if failures > 0 && section != "courses" {
                Button("\(failures) 门课程未读完整，查看原因") { select("courses"); courseScope = "failed" }.font(.footnote).frame(minHeight: 36)
            }
        }
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(CampusTheme.muted)
            TextField(section == "courses" ? "搜索课程" : "搜索作业或课程", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
        }.padding(12).background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var workList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if section == "homework" {
                if !courseKey.isEmpty {
                    HStack { Text(store.cache.courses.first { $0.key == courseKey }?.name ?? "所选课程").font(.headline); Spacer(); Button("全部课程") { courseKey = ""; filter = "pending" }.font(.caption) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) { ForEach(filters, id: \.0) { key, title in
                        let count = homework.filter { (key == "all" || LearningDisplay.state($0).key == key) && (courseKey.isEmpty || $0.courseKey == courseKey) }.count
                        Button { filter = key } label: { Text("\(title) \(count)").font(.caption.weight(.medium)).padding(.horizontal, 11).frame(minHeight: 40).background(filter == key ? CampusTheme.tint : CampusTheme.surface, in: Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(filter == key ? .isSelected : [])
                    } }
                }
            } else {
                Text(store.cache.issues["exams"] != nil ? "考试未完整更新，保留上次记录" : store.cache.examUpdatedAt != nil ? "上次同步的考试记录" : "考试尚未同步").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Text("\(filtered.count) 份已读取\(section == "exams" ? "考试" : "作业")").font(.caption).foregroundStyle(CampusTheme.muted)
            ForEach(groupKeys, id: \.self) { key in
                DisclosureGroup {
                    VStack(spacing: 0) {
                        ForEach(filtered.filter { $0.courseKey == key }) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Button { detail = item } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.text)
                                        Text(LearningDisplay.deadline(item)).font(.caption).foregroundStyle(CampusTheme.muted)
                                        Text(LearningDisplay.state(item).label).font(.caption.weight(.medium)).foregroundStyle(LearningDisplay.state(item).key == "pending" ? CampusTheme.primary : CampusTheme.muted)
                                        if item.stale || store.cache.session != "valid" { Text("上次记录 · 待更新").font(.caption).foregroundStyle(.orange) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                                }.buttonStyle(.plain)
                                if LearningDisplay.state(item).key == "pending" {
                                    let today = store.cache.plans[item.id]?.plannedDay == CampusTheme.date(Date(), format: "yyyy-MM-dd")
                                    Button(today ? "已安排今天" : "今天做") { store.today(item) }.font(.caption).frame(minHeight: 44).disabled(today)
                                }
                            }
                            Divider()
                        }
                    }
                } label: {
                    Label(groupName(key), systemImage: "book.closed").font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.text)
                }.campusCard()
            }
            if filtered.isEmpty { CampusEmpty(title: search.isEmpty ? "当前分类没有已读取记录" : "没有匹配记录", detail: "可切换分类，或在课程管理中选择并更新课程。空白页面不会被当作没有作业。", symbol: "book.closed") }
        }
    }
    private var groupKeys: [String] { var keys: [String] = []; for item in filtered where !keys.contains(item.courseKey) { keys.append(item.courseKey) }; return keys }
    private func groupName(_ key: String) -> String { store.cache.courses.first { $0.key == key }?.name ?? filtered.first { $0.courseKey == key }?.course.nonEmpty ?? "课程名称待更新" }
    private var courseList: some View {
        VStack(spacing: 12) {
            Picker("课程筛选", selection: $courseScope) { Text("全部").tag("all"); Text("已关注").tag("followed"); Text("需处理").tag("failed") }.pickerStyle(.segmented)
            ForEach(courses) { course in
                VStack(alignment: .leading, spacing: 10) {
                    Button { courseKey = course.key; filter = "all"; select("homework") } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "book.closed").font(.title3)
                            VStack(alignment: .leading, spacing: 4) { Text(course.name).font(.subheadline.weight(.semibold)); Text(courseStatus(course.key)).font(.caption).foregroundStyle(CampusTheme.muted); if !course.teacher.isEmpty { Text(course.teacher).font(.caption).foregroundStyle(CampusTheme.muted) } }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                    HStack {
                        Button { store.follow(course) } label: { Label(store.cache.selectedCourses.contains(course.key) ? "已关注" : "关注并读取", systemImage: store.cache.selectedCourses.contains(course.key) ? "checkmark" : "plus") }
                        Spacer(minLength: 10)
                        Button(failed(course.key) ? "重试读取" : "更新作业") { store.sync(courseKeys: [course.key]) }
                    }.font(.caption).frame(minHeight: 44).disabled(store.blocked || store.needsLogin)
                    if failed(course.key) {
                        DisclosureGroup("为什么没读到？") {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(LearningError(code: store.cache.courseSync[course.key]?.code ?? "PARTIAL").localizedDescription)
                                Button("打开这门官方课程") { store.openCourse(course) }.disabled(store.blocked || store.needsLogin).frame(minHeight: 44)
                                Text("在官方课程中核对“作业”，返回后只重读这门课。已有作业会保留。")
                            }.font(.caption).foregroundStyle(CampusTheme.muted).padding(.top, 8)
                        }.font(.caption)
                    }
                }.campusCard()
            }
            if courses.isEmpty { CampusEmpty(title: "当前没有匹配课程", detail: store.cache.courses.isEmpty ? "连接后会读取官方课程列表。读取失败不会显示虚构课程。" : "可以调整搜索或课程筛选。", symbol: "books.vertical") }
        }
    }
    private func courseStatus(_ key: String) -> String {
        guard let result = store.cache.courseSync[key] else { return "还未读取" }
        if result.status == "ok" { return result.count == 0 ? "暂无作业" : "已读取 \(result.count) 份作业" }
        return result.status == "partial" ? "已保留 \(result.count) 份 · 未读完整" : "读取未成功"
    }
    private var noticeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.cache.issues["notices"] != nil ? "通知尚未完整更新，保留上次记录" : store.cache.noticeUpdatedAt != nil ? "上次同步的通知" : "通知尚未同步").font(.caption).foregroundStyle(CampusTheme.muted)
            ForEach(store.cache.notices) { notice in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) { Text(notice.sender + " · " + notice.publishedText).font(.caption).foregroundStyle(CampusTheme.muted); Text(notice.content).font(.subheadline).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                } label: { Text(notice.title).font(.subheadline.weight(.semibold)).foregroundStyle(CampusTheme.text) }.campusCard()
            }
            if store.cache.notices.isEmpty { CampusEmpty(title: "暂无已读取通知", detail: "更新关注课程时会查询通知；尚未读取不代表平台没有通知。", symbol: "bell") }
        }
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

private struct LearningItemDetail: View {
    @ObservedObject var store: LearningStore
    let item: LearningItem
    let open: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var plan: LearningPlan
    init(store: LearningStore, item: LearningItem, open: @escaping () -> Void) {
        self.store = store; self.item = item; self.open = open
        _plan = State(initialValue: store.cache.plans[item.id] ?? LearningPlan())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("学习通记录") {
                    Text(item.title).font(.headline)
                    if !item.course.isEmpty { Text(item.course) }
                    Text(LearningDisplay.state(item).label)
                    Text(LearningDisplay.deadline(item))
                    if !item.timeText.isEmpty { Text(item.timeText).font(.footnote) }
                    if !item.description.isEmpty { Text(item.description).font(.subheadline) }
                    if item.stale { Text("这是上次记录，需要更新核对。").foregroundStyle(.orange) }
                    Button("打开学习通官方页面", action: open).disabled(store.blocked)
                }
                Section("本机计划") {
                    Toggle("安排日期", isOn: Binding(get: { plan.plannedDay != nil }, set: { plan.plannedDay = $0 ? CampusTheme.date(Date(), format: "yyyy-MM-dd") : nil }))
                    if plan.plannedDay != nil {
                        DatePicker("日期", selection: Binding(get: { LearningDisplay.date((plan.plannedDay ?? "") + "T12:00") ?? Date() }, set: { plan.plannedDay = CampusTheme.date($0, format: "yyyy-MM-dd") }), displayedComponents: .date)
                            .environment(\.timeZone, CampusTheme.calendar.timeZone)
                    }
                    HStack {
                        Button("今天做") { plan.plannedDay = CampusTheme.date(Date(), format: "yyyy-MM-dd") }
                        Spacer(); Button("清除安排") { plan.plannedDay = nil }
                    }
                    Stepper("预计 \(plan.durationMinutes) 分钟", value: $plan.durationMinutes, in: 5...480, step: 5)
                    Toggle("已准备好", isOn: $plan.prepared)
                    TextField("备注", text: $plan.notes, axis: .vertical).lineLimit(3...8)
                    Text("计划不修改平台截止时间，也不会把作业标为已提交。请在官方页面自行完成操作。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item.kind == "exam" ? "考试详情" : "作业详情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { store.plan(item, value: plan); dismiss() }.disabled(plan.notes.count > 4000) }
            }
        }
    }
}

private struct LearningPresenterAnchor: UIViewControllerRepresentable {
    let attach: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> LearningPresenterController { let controller = LearningPresenterController(); controller.attach = attach; return controller }
    func updateUIViewController(_ controller: LearningPresenterController, context: Context) { controller.attach = attach; if controller.viewIfLoaded?.window != nil { attach(controller) } }
}
private final class LearningPresenterController: UIViewController {
    var attach: ((UIViewController) -> Void)?
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach?(self) }
}
