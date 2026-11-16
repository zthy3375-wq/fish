import SwiftUI
import PhotosUI

struct TreeholeView: View {
    @EnvironmentObject var tree: TreeholeStore
    @State private var screen = "feed"
    @State private var routes: [TreeholeRouteFrame] = []
    @State private var bio = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageOffset: CGFloat = 0
    @State private var selectedPhoto: String?
    private var pageAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.24) }
    @State private var auth = "login"
    @State private var username = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var invitation = ""
    @State private var recoveryInput = ""
    @State private var newPassword = ""
    @State private var agreed = false
    @StateObject private var draft = TreeholeDraftStore()
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var gallery: TreeholeGallerySelection?
    @Environment(\.scenePhase) private var scenePhase
    private var anonymous: Bool { draft.value.anonymous }
    @State private var replyExpanded = false
    @State private var detailTab = "body"
    @State private var scrollIntentUntil = Date.distantPast
    @State private var feedAnchor: String?
    @State private var visibleFeedPost: String?
    @State private var previousScreen = "feed"
    @State private var initialDetailTarget = "post"
    @State private var viewportHeight: CGFloat = 0
    @State private var feedEndOffset: CGFloat = .greatestFiniteMagnitude
    @State private var replyAnonymous = false
    private var bodyText: String { draft.value.body }
    @State private var replyPhotos: [TreeholeDraftPhoto] = []
    @State private var pickedReplyPhotos: [PhotosPickerItem] = []
    private var hasReply: Bool { !replyText.isEmpty || !replyPhotos.isEmpty }
    @State private var replyText = ""
    @State private var reportReason = ""
    @State private var commentRequest = UUID().uuidString
    @State private var replyTo: TreeholeComment?
    @State private var reportTarget: TreeholeTarget?
    @State private var confirmation: TreeholeConfirmation?
    @State private var discard = false
    @State private var searchOpen = false
    @State private var accountPage = "overview"
    @FocusState private var replyFocused: Bool
    private var title: String {
        switch screen {
        case "compose": return "发帖"
        case "detail": return "帖子详情"
        case "inbox": return "互动消息"
        case "profile": return "同学主页"
        case "following": return "我关注的人"
        case "account": return accountPage == "overview" ? "我的树洞" : accountPage == "profile" ? "修改昵称" : accountPage == "password" ? "账号安全" : "注销账号"
        case "moderate": return "举报处理"
        default: return "邯院社区"
        }
    }
    private var forceAnonymous: Bool { tree.current?.category == "treehole" || tree.current?.anonymous == true && tree.current?.author.mine == true }
    var body: some View {
        ScrollViewReader { proxy in lifecycle(scrolling(proxy)) }
    }
    private func scrolling(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if tree.busy { ProgressView("正在处理…").frame(maxWidth: .infinity) }
                if let message = tree.message {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(.subheadline).foregroundStyle(.red)
                        if !tree.ready { Button("重试连接") { tree.enter() } }
                        else if tree.user != nil && screen == "feed" { Button("重新加载") { tree.perform { try await tree.feed() } } }
                    }.campusCard().accessibilityElement(children: .combine)
                }
                if tree.user == nil && tree.ready { authentication }
                if let user = tree.user {
                    switch screen {
                    case "compose": composer
                    case "detail": if let post = tree.current { discussion(post) }
                    case "account": account(user)
                    case "moderate": moderation
                    case "inbox": TreeholeInboxView(tree: tree, open: openNotification)
                    case "profile": publicProfile
                    case "following": TreeholeFollowingView(tree: tree, open: showProfile, browse: { accountFeed("all") })
                    default: feed
                    }
                }
            }.offset(x: pageOffset).padding(.horizontal, 18).padding(.top, screen == "feed" ? 0 : 8).padding(.bottom, screen == "feed" ? 88 : 24).frame(maxWidth: 680).frame(maxWidth: .infinity).disabled(tree.busy)
        }
        .coordinateSpace(name: "treehole-scroll")
        .onPreferenceChange(TreeholeDiscussionOffset.self) { value in if screen == "detail" && Date() > scrollIntentUntil { if value < 24 { detailTab = "comments" } else if value > 160 { detailTab = "body" } } }
        .background(GeometryReader { geometry in Color.clear.preference(key: TreeholeViewportHeight.self, value: geometry.size.height) })
        .onPreferenceChange(TreeholeViewportHeight.self) { viewportHeight = $0 }
        .onPreferenceChange(TreeholeFeedFrames.self) { frames in
            guard screen == "feed" else { return }
            visibleFeedPost = frames.filter { $0.value.maxY > 0 }.min { $0.value.minY < $1.value.minY }?.key
        }
        .onPreferenceChange(TreeholeFeedEndOffset.self) { value in feedEndOffset = value; requestNextFeedPage() }
        .onChange(of: tree.busy) { value in if !value { requestNextFeedPage() } }
        .onChange(of: tree.feedRevision) { _ in feedAnchor = nil; if screen == "feed" { DispatchQueue.main.async { proxy.scrollTo("feed-top", anchor: .top) } } }
        .onChange(of: screen) { next in
            if previousScreen == "feed" { feedAnchor = visibleFeedPost }
            previousScreen = next
            if next != "detail" { tree.leaveDetail() }
            if !reduceMotion {
                pageOffset = next == "feed" ? -18 : 24
                DispatchQueue.main.async { if screen == next { withAnimation(pageAnimation) { pageOffset = 0 } } }
            }
            if next == "feed" {
                let target = tree.feedNeedsRefresh ? "feed-top" : feedAnchor ?? "feed-top"
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
            } else if next == "detail" {
                DispatchQueue.main.async { proxy.scrollTo(initialDetailTarget, anchor: .top); detailTab = ["comments", "context"].contains(initialDetailTarget) ? "comments" : "body" }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 20).onChanged { value in
            guard screen != "feed", !tree.busy, !reduceMotion, value.startLocation.x < 24 else { return }
            pageOffset = abs(value.translation.height) < 30 ? min(180, max(0, value.translation.width)) : 0
        }.onEnded { value in
            withAnimation(pageAnimation) { pageOffset = 0 }
            guard screen != "feed", !tree.busy, value.startLocation.x < 24,
                  value.translation.width > 90, abs(value.translation.height) < 30 else { return }
            back()
        })
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            guard screen == "feed", tree.user != nil, !tree.busy else { return }
            tree.busy = true; tree.message = nil
            defer { tree.busy = false }
            do { try await tree.feed() } catch {
                if let error = error as? TreeholeError, error.code == "session_expired" { tree.clear() }
                tree.message = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试"
            }
        }
        .background(screen == "feed" || screen == "detail" || screen == "compose" ? TreeholeTheme.surface : TreeholeTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(tree.busy || screen != "feed")
        .toolbar(screen == "feed" && tree.recovery == nil ? .visible : .hidden, for: .tabBar)
        .toolbar {
            if screen == "detail" {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 28) {
                        detailTabButton("正文", value: "body") { scrollIntentUntil = Date().addingTimeInterval(0.65); withAnimation(pageAnimation) { proxy.scrollTo("post", anchor: .top) } }
                        detailTabButton("评论", value: "comments") { scrollIntentUntil = Date().addingTimeInterval(0.65); withAnimation(pageAnimation) { proxy.scrollTo("comments", anchor: .top) } }
                    }
                }
            }
            if screen != "feed" { ToolbarItem(placement: .navigationBarLeading) { Button { back() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("返回社区").disabled(tree.busy) } }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if screen == "compose" { Button("发布", action: publish).fontWeight(.semibold).disabled(tree.busy || (bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.value.photos.isEmpty && draft.value.poll == nil) || (draft.value.poll != nil && (!tree.pollsEnabled || draft.value.poll?.valid != true))) }
                else if screen == "feed", let user = tree.user {
                    Button { withAnimation { searchOpen.toggle() } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索帖子")
                    if tree.engagementEnabled { Button(action: showInbox) { Image(systemName: "bell").overlay(alignment: .topTrailing) { if tree.unreadCount > 0 { Text(tree.unreadCount > 99 ? "99+" : "\(tree.unreadCount)").font(.system(size: 9, weight: .bold)).padding(3).background(TreeholeTheme.primary, in: Capsule()).foregroundStyle(.white).offset(x: 9, y: -9) } } }.accessibilityLabel("互动消息") }
                    Button { nickname = user.nickname; bio = user.bio ?? ""; password = ""; newPassword = ""; accountPage = "overview"; screen = "account" } label: { TreeholeAvatar(name: user.nickname, avatar: user.avatar, size: 32) }.accessibilityLabel("我的树洞")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if screen == "feed" && tree.user != nil {
                Button(action: startPost) { Label("发树洞", systemImage: "square.and.pencil").font(.subheadline.weight(.semibold)).padding(.horizontal, 19).padding(.vertical, 16) }
                    .foregroundStyle(TreeholeTheme.onPrimary).background(Color(red: 0.15, green: 0.17, blue: 0.20), in: RoundedRectangle(cornerRadius: 15))
                    .shadow(color: TreeholeTheme.primary.opacity(0.18), radius: 12, y: 5).padding(20).disabled(tree.busy).accessibilityLabel("发帖")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if screen == "detail", let post = tree.current, tree.user != nil { replyBar(post) { scrollIntentUntil = Date().addingTimeInterval(0.65); detailTab = "comments"; withAnimation(pageAnimation) { proxy.scrollTo("comments", anchor: .top) } }.disabled(tree.busy) }
        }
    }
    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
        .task { draft.bind(tree.user?.id); if !tree.ready { tree.enter() } }
        .onDisappear { draft.flush() }
        .onChange(of: scenePhase) { if $0 != .active { draft.flush() } else { Task { await tree.refreshUnread() } } }
        .task(id: tree.user?.id) {
            guard tree.user != nil else { return }
            while !Task.isCancelled {
                if scenePhase == .active { await tree.refreshUnread() }
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { break }
            }
        }
        .onChange(of: pickedPhotos) { items in loadPhotos(items) }
        .onChange(of: pickedReplyPhotos) { items in loadReplyPhotos(items) }
        .fullScreenCover(item: $gallery) { TreeholeGallery(selection: $0, api: tree.api) }
        .onChange(of: tree.user?.id) { identity in if identity == nil { auth = "login"; routes = [] }; draft.bind(identity); replyText = ""; replyPhotos = []; pickedReplyPhotos = []; replyExpanded = false; password = ""; newPassword = ""; replyTo = nil; accountPage = "overview"; screen = "feed" }
        .sheet(isPresented: Binding(get: { tree.recovery != nil }, set: { if !$0 { tree.recovery = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("保存你的账号恢复码", systemImage: "checkmark.shield").font(.title2.bold())
                Text("忘记密码时，用登录账号和这串恢复码找回。恢复码只在这次显示，请保存到密码管理器或安全位置。")
                Text(tree.recovery ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().background(TreeholeTheme.background).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("请勿发到树洞或分享给他人。").font(.caption).foregroundStyle(.secondary)
                Button("我已保存恢复码") { tree.recovery = nil }.buttonStyle(.borderedProminent)
            }.padding(24).interactiveDismissDisabled()
        }
        .sheet(isPresented: $replyExpanded, onDismiss: { replyFocused = false }) {
            if let post = tree.current { ScrollView { replyEditor(post) }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).interactiveDismissDisabled(tree.busy) }
        }
        .sheet(item: $reportTarget) { target in reportSheet(target) }
        .confirmationDialog(confirmation?.title ?? "确认操作", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            Button("确认", role: .destructive) { if let action = confirmation?.action { tree.perform(action) }; confirmation = nil }
            Button("取消", role: .cancel) { confirmation = nil }
        }
        .confirmationDialog("放弃还没发布的内容？", isPresented: $discard, titleVisibility: .visible) {
            if screen == "compose" { Button("保存草稿并返回") { draft.flush(); screen = "feed" } }
            Button("放弃并返回", role: .destructive) { if screen == "compose" { draft.clear() }; replyText = ""; replyPhotos = []; pickedReplyPhotos = []; replyTo = nil; returnToFeed() }
            Button("继续编辑", role: .cancel) { }
        }
    }
    private var authentication: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 42)).foregroundStyle(TreeholeTheme.primary)
                    .frame(width: 96, height: 96).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 30)).rotationEffect(.degrees(-7)).accessibilityHidden(true)
                Spacer()
            }.padding(.vertical, 12)
            Text(auth == "login" ? "说说校园里的那些事" : auth == "register" ? "创建邯院通账号" : "找回邯院通账号").font(.title2.bold())
            Text("树洞使用独立的邯院通账号，昵称由你决定。学校账号继续用于课表和成绩。").font(.subheadline).foregroundStyle(.secondary)
            TextField("登录账号 · 4–24 位字母、数字或下划线", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            if auth == "register" { TextField("公开昵称 · 2–20 字", text: $nickname).textContentType(.nickname) }
            if auth == "recover" { TextField("账号恢复码", text: $recoveryInput).textInputAutocapitalization(.never).autocorrectionDisabled() }
            SecureField(auth == "recover" ? "新密码 · 至少 10 位" : "密码 · 至少 10 位", text: $password).textContentType(auth == "login" ? .password : .newPassword)
            if auth == "register" && tree.requiresInvite { TextField("内测邀请码", text: $invitation).textInputAutocapitalization(.never) }
            DisclosureGroup("树洞规则与匿名说明") {
                Text(Self.rules).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
            if auth == "register" { Toggle("我已阅读并同意树洞规则与账号服务说明", isOn: $agreed).font(.caption) }
            Button(auth == "login" ? "登录树洞" : auth == "register" ? "创建账号" : "重设密码并登录") {
                tree.perform {
                    let result = try await tree.api.request(auth, ["username": username, "password": password, "nickname": nickname, "invite": invitation, "agreed": agreed, "recoveryCode": recoveryInput])
                    password = ""; recoveryInput = ""; tree.user = result.user; tree.recovery = result.recoveryCode; try await tree.feed(); await tree.refreshUnread()
                }
            }.buttonStyle(.borderedProminent).disabled(username.isEmpty || password.count < 10 || (auth == "register" && (!agreed || !tree.registration || nickname.count < 2)))
            HStack {
                if auth != "register" && tree.registration { Button("注册账号") { auth = "register"; password = "" } }
                Spacer()
                if auth == "login" { Button("忘记密码") { auth = "recover"; password = "" } }
                else { Button("返回登录") { auth = "login"; password = "" } }
            }.font(.subheadline)
            if !tree.registration { Text("树洞正在准备内测，暂未开放新账号注册。").font(.caption).foregroundStyle(.secondary) }
        }.textFieldStyle(.roundedBorder).padding(8).campusCard()
    }
    private var feed: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tree.engagementEnabled {
                TreeholeFeedScopes(tree: tree, select: accountFeed)
            }
            TreeholeDiscoveryBar(tree: tree) { category, interest in selectDiscovery(category, interest: interest) }.id("feed-top")
            if draft.value.hasContent { Button(action: startPost) { HStack { Label("继续编辑草稿", systemImage: "doc.text"); Spacer(); Image(systemName: "chevron.right") }.font(.caption).padding(12).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 10)) } }
            if searchOpen {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索树洞里的文字", text: $tree.query).submitLabel(.search).onSubmit { reloadFeed() }
                    if !tree.query.isEmpty { Button { tree.query = ""; reloadFeed() } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
                    Button("搜索", action: reloadFeed)
                }.font(.subheadline).campusCard()
            } else if !tree.query.isEmpty {
                HStack { Text("搜索：" + tree.query).font(.caption).foregroundStyle(.secondary); Spacer(); Button("清除") { tree.query = ""; reloadFeed() }.font(.caption) }
            }
            HStack(spacing: 20) {
                if tree.scope == "all" || tree.scope == "following" {
                    ForEach([("latest", "最新"), ("hot", "热门")], id: \.0) { value, label in
                        Button { tree.sort = value; reloadFeed() } label: { Text(label).font(.system(size: 12, weight: tree.sort == value ? .semibold : .regular)).foregroundStyle(tree.sort == value ? TreeholeTheme.text : TreeholeTheme.muted) }.accessibilityAddTraits(tree.sort == value ? .isSelected : [])
                    }
                } else {
                    Text(["mine": "我的帖子", "saved": "我的收藏", "participated": "我参与的", "watching": "关注的讨论"][tree.scope] ?? "广场").font(.caption.weight(.semibold))
                    Button("查看全部") { tree.scope = "all"; reloadFeed() }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: reloadFeed) { Image(systemName: "arrow.clockwise").font(.system(size: 13)).frame(width: 32, height: 44) }.foregroundStyle(.secondary).accessibilityLabel("刷新树洞")
            }.buttonStyle(.plain).overlay(alignment: .bottom) { Divider() }
            if tree.posts.isEmpty && !tree.busy && tree.message == nil {
                if tree.scope == "following" {
                    CampusEmpty(title: "暂时没有公开动态", detail: tree.query.isEmpty && tree.category == "all" ? "在同学主页点一下关注，TA 的公开帖子会出现在这里。" : "换个筛选条件，再看看关注的同学分享了什么。", symbol: "person.2")
                    HStack { Button("去广场看看") { accountFeed("all") }; Spacer(); Button("管理我关注的人", action: showFollowing) }.font(.subheadline).frame(minHeight: 44)
                } else {
                CampusEmpty(title: tree.query.isEmpty ? "这里还很安静" : "还没找到这段回声", detail: tree.query.isEmpty ? (tree.scope == "saved" ? "遇见喜欢的文字，点一下收藏。" : tree.scope == "mine" ? "你的第一条树洞，从一句话开始。" : "从一句想说的话开始。") : "换个关键词试试", symbol: "bubble.left.and.bubble.right")
                }
            }
            LazyVStack(spacing: 0) { ForEach(tree.posts) { post in postCard(post).id(post.id).background(GeometryReader { geometry in Color.clear.preference(key: TreeholeFeedFrames.self, value: [post.id: geometry.frame(in: .named("treehole-scroll"))]) }); Rectangle().fill(TreeholeTheme.background).frame(height: 7).padding(.horizontal, -16) } }
            if tree.feedNext != nil { feedPageEnd }
            else if !tree.posts.isEmpty { Text("暂时就这些，过一会儿再来看看吧").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 22) }
        }
    }
    private var feedPageEnd: some View {
        VStack(spacing: 8) {
            if tree.feedLoadingMore { HStack(spacing: 8) { ProgressView(); Text("正在加载更多帖子…") } }
            else if let error = tree.feedPageError {
                Text(error + "，已保留当前帖子。").multilineTextAlignment(.center)
                Button("重试加载") { Task { await tree.loadMoreFeed(automatic: false) } }.frame(minHeight: 44)
            } else { Button("加载更多帖子") { Task { await tree.loadMoreFeed(automatic: false) } }.frame(minHeight: 44) }
        }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 88)
            .background(GeometryReader { geometry in Color.clear.preference(key: TreeholeFeedEndOffset.self, value: geometry.frame(in: .named("treehole-scroll")).minY) })
    }
    private func requestNextFeedPage() {
        guard screen == "feed", viewportHeight > 0, feedEndOffset < viewportHeight + 280, feedEndOffset > -100 else { return }
        Task { await tree.loadMoreFeed() }
    }
    private func returnToFeed() {
        routes = []; tree.leaveDetail(); screen = "feed"
        if tree.feedNeedsRefresh { reloadFeed() }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                TreeholeAvatar(name: anonymous ? "匿名同学" : tree.user?.nickname ?? "", anonymous: anonymous, avatar: tree.user?.avatar, size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(anonymous ? "匿名同学" : tree.user?.nickname ?? "").font(.subheadline.weight(.semibold))
                    Text(anonymous ? "本帖使用独立匿名代号" : "使用邯院通账号").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Toggle("匿名发布", isOn: $draft.value.anonymous).disabled(draft.value.category == "treehole").font(.caption).fixedSize().tint(TreeholeTheme.primary)
            }
            Divider()
            TreeholeDiscoveryComposer(draft: $draft.value, enabled: tree.discoveryEnabled)
            TextField("添加标题（选填）", text: $draft.value.title).font(.system(size: 21, weight: .bold)).onChange(of: draft.value.title) { draft.value.title = String($0.prefix(40)) }
            Divider()
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty { Text("分享校园里的新鲜事…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                TextEditor(text: $draft.value.body).scrollContentBackground(.hidden).frame(minHeight: 190).accessibilityLabel("想说的话").onChange(of: bodyText) { draft.value.body = String($0.prefix(3000)) }
            }.font(.body).lineSpacing(7)
            if !draft.value.photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(draft.value.photos) { photo in
                        if let image = UIImage(data: photo.data) { Button { selectedPhoto = photo.id } label: { Image(uiImage: image).resizable().scaledToFill().frame(height: 100).clipped() }.buttonStyle(.plain).overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedPhoto == photo.id ? TreeholeTheme.primary : .clear, lineWidth: 2)).accessibilityLabel("调整图片顺序").overlay(alignment: .topTrailing) { Button { removePhoto(photo) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.55)).padding(5) }.accessibilityLabel("移除图片") } }
                    }
                }
            }
            if let selectedPhoto, let index = draft.value.photos.firstIndex(where: { $0.id == selectedPhoto }) {
                HStack {
                    Text("调整第 \(index + 1) 张").foregroundStyle(.secondary); Spacer()
                    Button("前移") { draft.value.photos.swapAt(index, index - 1) }.disabled(index == 0).frame(minWidth: 44, minHeight: 44)
                    Button("后移") { draft.value.photos.swapAt(index, index + 1) }.disabled(index == draft.value.photos.count - 1).frame(minWidth: 44, minHeight: 44)
                }.font(.caption).padding(.horizontal, 10).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 10))
            }
            if tree.imagesEnabled && draft.value.photos.count < 9 {
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 9 - draft.value.photos.count, matching: .images) { Label("添加图片 · \(draft.value.photos.count)/9", systemImage: "photo.on.rectangle").font(.subheadline).padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 10)) }
            }
            if draft.value.poll != nil {
                TreeholePollEditor(poll: Binding(get: { draft.value.poll ?? TreeholePollDraft() }, set: { draft.value.poll = $0 })) { draft.value.poll = nil }
                if !tree.pollsEnabled { Text("投票暂不可用，草稿已保留").font(.caption).foregroundStyle(.secondary) }
            } else if tree.pollsEnabled { Button { draft.value.poll = TreeholePollDraft() } label: { Label("添加投票", systemImage: "chart.bar.xaxis").frame(minHeight: 44) } }
            if !draft.message.isEmpty { Text(draft.message).font(.caption2).foregroundStyle(.secondary) }
            HStack { Label("友善表达，尊重隐私", systemImage: "bubble.left"); Spacer(); Text("\(bodyText.count) / 3000") }.font(.caption2).foregroundStyle(.secondary)
            Divider()
            Label(anonymous ? "其他同学看不到你的昵称和账号。本帖内匿名回复使用同一代号。发布后身份方式固定。" : "帖子显示你的邯院通昵称。发布后身份方式固定。", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(.horizontal, 3).padding(.top, 8)
    }
    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        tree.perform {
            defer { pickedPhotos = [] }
            for item in items.prefix(max(0, 9 - draft.value.photos.count)) {
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw TreeholeError(code: "invalid_image") }
                draft.value.photos.append(try TreeholeDraftStore.prepare(bytes)); draft.flush()
            }
        }
    }
    private func removePhoto(_ photo: TreeholeDraftPhoto) {
        draft.value.photos.removeAll { $0.id == photo.id }
        if let remote = photo.remote { Task { _ = try? await tree.api.request("media.discard", ["imageId": remote.id]) } }
    }
    private func publish() {
        let member = tree.user?.id
        tree.perform {
            guard tree.discoveryEnabled || !["entertainment", "treehole"].contains(draft.value.category) else { tree.message = "这个分区暂不可用，草稿已保留，请稍后重试"; return }
            guard draft.value.poll == nil || tree.pollsEnabled && draft.value.poll?.valid == true else { return }
            for photo in draft.value.photos where photo.remote == nil {
                guard let remote = try await tree.api.request("media.upload", ["data": photo.data.base64EncodedString(), "requestId": photo.id]).image else { throw TreeholeError(code: "images_unavailable") }
                guard tree.user?.id == member, let index = draft.value.photos.firstIndex(where: { $0.id == photo.id }) else { throw CancellationError() }
                draft.value.photos[index].remote = remote; draft.flush()
            }
            let r = try await tree.api.request("posts.create", ["body": bodyText, "title": draft.value.title, "category": draft.value.category, "interest": draft.value.category == "entertainment" ? draft.value.interest ?? "" : "", "anonymous": draft.value.category == "treehole" || anonymous, "requestId": draft.value.requestId, "images": draft.value.photos.compactMap { $0.remote?.id }, "poll": draft.value.poll?.payload as Any? ?? NSNull()])
            guard tree.user?.id == member else { throw CancellationError() }
            draft.clear()
            if let post = r.post { tree.feedNeedsRefresh = true; initialDetailTarget = "post"; tree.current = post; tree.comments = []; detailTab = "body"; replyExpanded = false; screen = "detail"; try await tree.detail(post) }
        }
    }
    @ViewBuilder private func commentImages(_ comment: TreeholeComment, post: TreeholePost) -> some View {
        if !comment.deleted, let images = comment.images, !images.isEmpty {
            TreeholeImageGrid(postId: post.id, images: images, full: false, api: tree.api) { index in gallery = TreeholeGallerySelection(postId: post.id, images: images, index: index) }.frame(maxWidth: images.count == 1 ? 160 : 270, alignment: .leading)
        }
    }
    private var replyPhotoEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !replyPhotos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(replyPhotos) { photo in
                        if let image = UIImage(data: photo.data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 74, height: 74).clipped().clipShape(RoundedRectangle(cornerRadius: 8)).overlay(alignment: .topTrailing) {
                                Button { removeReplyPhoto(photo) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)).frame(width: 44, height: 44) }.accessibilityLabel("移除评论图片").disabled(tree.busy)
                            }
                        }
                    }
                }
            }
            if tree.commentImagesEnabled && replyPhotos.count < 3 {
                PhotosPicker(selection: $pickedReplyPhotos, maxSelectionCount: 3 - replyPhotos.count, matching: .images) { Label("添加图片 · \(replyPhotos.count)/3", systemImage: "photo").font(.caption).frame(minHeight: 44) }.disabled(tree.busy)
            }
        }
    }
    private func loadReplyPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, tree.commentImagesEnabled else { return }
        let member = tree.user?.id, postId = tree.current?.id
        tree.perform {
            defer { pickedReplyPhotos = [] }
            for item in items.prefix(max(0, 3 - replyPhotos.count)) {
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw TreeholeError(code: "invalid_image") }
                guard member == tree.user?.id, postId == tree.current?.id else { throw CancellationError() }
                replyPhotos.append(try TreeholeDraftStore.prepare(bytes))
            }
        }
    }
    private func removeReplyPhoto(_ photo: TreeholeDraftPhoto) {
        replyPhotos.removeAll { $0.id == photo.id }
        if let image = photo.remote { Task { _ = try? await tree.api.request("media.discard", ["imageId": image.id]) } }
    }
    private func sendComment(_ post: TreeholePost) {
        let member = tree.user?.id
        tree.perform {
            do {
                for photo in replyPhotos where photo.remote == nil {
                    guard let image = try await tree.api.request("media.upload", ["data": photo.data.base64EncodedString(), "requestId": photo.id, "purpose": "comment"]).image else { throw TreeholeError(code: "images_unavailable") }
                    guard member == tree.user?.id, tree.current?.id == post.id, let index = replyPhotos.firstIndex(where: { $0.id == photo.id }) else { throw CancellationError() }
                    replyPhotos[index].remote = image
                }
                _ = try await tree.api.request("comments.create", ["postId": post.id, "body": replyText, "anonymous": replyAnonymous || forceAnonymous, "requestId": commentRequest, "replyTo": replyTo?.id as Any? ?? NSNull(), "images": replyPhotos.compactMap { $0.remote?.id }])
                guard member == tree.user?.id, tree.current?.id == post.id else { throw CancellationError() }
                replyText = ""; replyPhotos = []; pickedReplyPhotos = []; replyTo = nil; replyFocused = false; replyExpanded = false; commentRequest = UUID().uuidString; try await tree.detail(post)
            } catch {
                if member == tree.user?.id, tree.current?.id == post.id, let e = error as? TreeholeError, e.code == "image_unavailable" {
                    replyPhotos = replyPhotos.map { TreeholeDraftPhoto(id: UUID().uuidString, data: $0.data) }
                }
                throw error
            }
        }
    }
    @ViewBuilder private func discussion(_ post: TreeholePost) -> some View {
        postCard(post, full: true).id("post")
        if tree.engagementEnabled {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(post.watching == true ? "正在关注这段讨论" : "想知道后续？").font(.subheadline.weight(.semibold)); Text("新回复会出现在互动消息").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await tree.toggleWatch(post) } } label: { Label(post.watching == true ? "取消关注" : "关注讨论", systemImage: post.watching == true ? "bell.slash" : "bell").font(.caption).frame(minHeight: 44) }.disabled(tree.watchPending)
            }.padding(.vertical, 10)
            Divider()
        }
        if let context = tree.focusedThread {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("消息对应的回复").font(.caption).foregroundStyle(.secondary); Spacer(); Button("查看全部讨论") { tree.focusedThread = nil }.font(.caption) }
                commentRow(context, post: post, floor: 0)
            }.padding(12).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 12)).id("context")
        }
        HStack { Text("评论 \(post.commentCount)").font(.system(size: 16, weight: .semibold)); Spacer(); Text("按时间排序").font(.caption2).foregroundStyle(.secondary) }.padding(.top, 12).padding(.bottom, 4).id("comments").background(GeometryReader { geometry in Color.clear.preference(key: TreeholeDiscussionOffset.self, value: geometry.frame(in: .named("treehole-scroll")).minY) })
        if let error = tree.detailError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                VStack(alignment: .leading, spacing: 4) { Text("暂时没有加载完整").fontWeight(.semibold); Text(error + "，当前正文已保留。") }
                Spacer(minLength: 0)
                Button("重试") { Task { try? await tree.detail(post) } }.frame(minWidth: 44, minHeight: 44).disabled(tree.detailLoading)
            }.font(.caption).padding(14).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }
        if tree.detailLoading && tree.comments.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 6).fill(TreeholeTheme.background).frame(width: 120, height: 28)
                RoundedRectangle(cornerRadius: 6).fill(TreeholeTheme.background).frame(height: 12)
                HStack { ProgressView(); Text("正在加载评论…").font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 24).frame(maxWidth: .infinity, minHeight: max(180, viewportHeight - 80), alignment: .topLeading)
        }
        else if tree.comments.isEmpty && tree.detailError == nil { CampusEmpty(title: "第一句回应，留给你", detail: "认真倾听，也是一种陪伴。", symbol: "bubble.left").frame(minHeight: max(180, viewportHeight - 80), alignment: .top) }
        else {
            VStack(spacing: 0) {
                ForEach(Array(tree.comments.enumerated()), id: \.element.id) { index, comment in
                    commentRow(comment, post: post, floor: index + 1)
                    if index < tree.comments.count - 1 { Divider().padding(.leading, 44) }
                }
            }.frame(minHeight: max(180, viewportHeight - 80), alignment: .top)
        }
        if tree.commentNext != nil { Button(tree.detailLoading ? "正在加载…" : "加载更多评论") { Task { try? await tree.detail(post, more: true) } }.frame(maxWidth: .infinity, minHeight: 44).disabled(tree.detailLoading) }
        if post.locked { Label("这条讨论已暂停回复", systemImage: "lock").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding() }
    }
    private func commentRow(_ comment: TreeholeComment, post: TreeholePost, floor: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TreeholeAvatar(name: comment.author.name, anonymous: comment.author.anonymous, avatar: comment.author.avatar, size: 36)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(comment.author.name).font(.system(size: 14, weight: .semibold))
                            if comment.isOriginalPoster { Text("楼主").font(.system(size: 10)).foregroundStyle(TreeholeTheme.primary).padding(.horizontal, 4).padding(.vertical, 2).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 4)) }
                        }
                        Text(TreeholePresentation.date(comment.createdAt) + (floor > 0 ? " · \(floor) 楼" : "")).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !comment.deleted { commentLike(comment, post: post); contentMenu(post, comment: comment) }
                }

                if !comment.displayBody.isEmpty { Text(comment.displayBody).font(.system(size: 16)).foregroundStyle(comment.deleted ? TreeholeTheme.muted : TreeholeTheme.text).lineSpacing(5).textSelection(.enabled) }
                commentImages(comment, post: post)
                if !comment.deleted && !post.locked { Button("回复") { replyTo = comment; replyExpanded = true }.font(.caption).padding(.vertical, 4) }
                if (comment.replyCount ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array((comment.replies ?? []).prefix(tree.expandedReplies.contains(comment.id) ? Int.max : 2))) { child in
                            VStack(alignment: .leading, spacing: 2) {
                                Button { replyTo = child; replyExpanded = true } label: {
                                    (Text(child.author.name + (child.isOriginalPoster ? " [楼主]" : "")).foregroundColor(Color(red: 0.23, green: 0.40, blue: 0.54)) + Text(child.replyTo != comment.id && child.replyTo != nil ? " 回复 " + replyName(child.replyTo!) : "").foregroundColor(.secondary) + Text(child.displayBody.isEmpty ? "" : "：" + child.displayBody)).font(.system(size: 14)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                                }.buttonStyle(.plain).disabled(child.deleted || post.locked)
                                commentImages(child, post: post)
                                if tree.expandedReplies.contains(comment.id) { HStack { Text(TreeholePresentation.date(child.createdAt)).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); if !child.deleted { if tree.expandedReplies.contains(comment.id) { commentLike(child, post: post) }; contentMenu(post, comment: child) } } }
                            }
                        }
                        if !tree.expandedReplies.contains(comment.id) || tree.replyPages[comment.id] != nil {
                            Divider()
                            Button(tree.loadingThreads.contains(comment.id) ? "正在加载…" : tree.expandedReplies.contains(comment.id) ? "加载更多回复" : "全部 \(comment.replyCount ?? 0) 条回复") { tree.expand(comment, post: post) }.font(.caption).frame(maxWidth: .infinity, minHeight: 30).disabled(tree.loadingThreads.contains(comment.id))
                        }
                        if tree.expandedReplies.contains(comment.id) { Button("收起回复") { tree.collapse(comment) }.font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 30).disabled(tree.loadingThreads.contains(comment.id)) }
                    }.padding(10).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }.padding(.vertical, 20)
    }
    private func replyName(_ id: String) -> String { (tree.comments + tree.comments.flatMap { $0.replies ?? [] }).first { $0.id == id }?.author.name ?? "同学" }
    private func commentLike(_ comment: TreeholeComment, post: TreeholePost) -> some View {
        Button { tree.likeComment(comment, post: post) } label: { Label("\(comment.likeCount ?? 0)", systemImage: comment.liked == true ? "hand.thumbsup.fill" : "hand.thumbsup").font(.caption2) }.foregroundStyle(comment.liked == true ? TreeholeTheme.primary : TreeholeTheme.muted).disabled(tree.pendingCommentLikes.contains(comment.id)).accessibilityLabel(comment.liked == true ? "取消评论点赞" : "评论点赞")
    }
    private func detailTabButton(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        Button { detailTab = value; action() } label: {
            VStack(spacing: 7) { Text(label).font(.system(size: 16, weight: detailTab == value ? .semibold : .regular)); Capsule().fill(detailTab == value ? TreeholeTheme.text : .clear).frame(height: 3) }
        }.foregroundStyle(detailTab == value ? TreeholeTheme.text : TreeholeTheme.muted).accessibilityAddTraits(detailTab == value ? .isSelected : [])
    }
    private func replyBar(_ post: TreeholePost, showComments: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Button { replyExpanded = true } label: { HStack(spacing: 7) { Image(systemName: "square.and.pencil"); Text(post.locked ? "讨论已暂停" : !hasReply ? "说点什么吧…" : "继续编辑回复…").lineLimit(1); Spacer(minLength: 0) }.font(.system(size: 13)).padding(11).foregroundStyle(.secondary).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 7)) }.disabled(post.locked).accessibilityLabel("写回复")
            Button { tree.react(post, kind: "like") } label: { barAction(post.likeCount > 0 ? "\(post.likeCount)" : "点赞", icon: post.liked ? "hand.thumbsup.fill" : "hand.thumbsup") }.foregroundStyle(post.liked ? TreeholeTheme.primary : TreeholeTheme.muted).disabled(tree.pendingReactions.contains(post.id + ":like")).accessibilityLabel(post.liked ? "取消点赞" : "点赞")
            Button { tree.react(post, kind: "save") } label: { barAction(post.saved ? "已收藏" : "收藏", icon: post.saved ? "bookmark.fill" : "bookmark") }.foregroundStyle(post.saved ? TreeholeTheme.primary : TreeholeTheme.muted).disabled(tree.pendingReactions.contains(post.id + ":save")).accessibilityLabel(post.saved ? "取消收藏" : "收藏")
            Button(action: showComments) { barAction(post.commentCount > 0 ? "\(post.commentCount)" : "评论", icon: "bubble.right") }.foregroundStyle(TreeholeTheme.muted).accessibilityLabel("查看评论")
        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 680).frame(maxWidth: .infinity).background(TreeholeTheme.surface).overlay(alignment: .top) { Divider() }
    }
    private func barAction(_ label: String, icon: String) -> some View {
        VStack(spacing: 3) { Image(systemName: icon).font(.system(size: 20)); Text(label).font(.system(size: 10)).fixedSize() }.frame(minWidth: 28, minHeight: 44)
    }
    private func replyEditor(_ post: TreeholePost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(replyTo.map { "回复 " + $0.author.name } ?? "写评论").font(.subheadline.weight(.semibold)); Spacer(); Button { replyFocused = false; replyExpanded = false } label: { Image(systemName: "xmark").padding(8) }.accessibilityLabel("收起回复编辑器").disabled(tree.busy) }
            if let replyTo { HStack { Text(replyTo.body).font(.caption).lineLimit(1); Spacer(); Button { self.replyTo = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("取消回复") }.foregroundStyle(.secondary) }
            TextField("说说你的想法…", text: $replyText, axis: .vertical).lineLimit(3...5).focused($replyFocused).font(.body).padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("你的回复").onChange(of: replyText) { replyText = String($0.prefix(1000)) }.disabled(tree.busy)
            replyPhotoEditor
            HStack(spacing: 10) {
                Button { replyAnonymous.toggle() } label: { Label(tree.current?.category == "treehole" ? "本区统一匿名" : forceAnonymous ? "保持楼主匿名身份" : replyAnonymous ? "匿名回复" : "昵称回复", systemImage: replyAnonymous || forceAnonymous ? "theatermasks" : "person.crop.circle").font(.caption2).padding(9).background(TreeholeTheme.background, in: Capsule()) }.disabled(tree.busy || forceAnonymous).accessibilityValue(replyAnonymous || forceAnonymous ? "匿名" : "昵称")
                Spacer(minLength: 0)
                Text("\(replyText.count)/1000").font(.system(size: 10)).foregroundStyle(.secondary)
                Button("发布回复") { sendComment(post) }.font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).tint(TreeholeTheme.text).disabled(tree.busy || (replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyPhotos.isEmpty))
            }
            if let message = tree.message { Text(message).font(.caption).foregroundStyle(.red) }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 12).background(TreeholeTheme.surface).task { replyFocused = true }
    }
    private func postCard(_ post: TreeholePost, full: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                if tree.engagementEnabled, let id = post.author.id, !post.anonymous {
                    Button { showProfile(id) } label: { author(post.author, date: post.createdAt, full: full) }.buttonStyle(.plain).accessibilityLabel("查看 " + post.author.name + " 的主页")
                } else if full { author(post.author, date: post.createdAt, full: true) }
                else { Button { open(post) } label: { author(post.author, date: post.createdAt, full: false).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(TreeholePressStyle()).accessibilityLabel("打开 " + post.author.name + " 的帖子") }
                Spacer(minLength: 3); contentMenu(post)
            }
            if full {
                if let title = post.title, !title.isEmpty { Text(title).font(.title2.weight(.bold)).textSelection(.enabled) }
                if !post.displayBody.isEmpty { Text(post.displayBody).font(.body).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                Button { open(post) } label: { VStack(alignment: .leading, spacing: 8) { if let title = post.title, !title.isEmpty { Text(title).font(.headline.weight(.bold)).lineLimit(2) }; if !post.displayBody.isEmpty { Text(post.displayBody).font(.body).lineSpacing(5).lineLimit(3) } }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading) }.buttonStyle(TreeholePressStyle())
            }
            if let poll = post.poll { TreeholePollCard(poll: poll, enabled: tree.pollsEnabled && !post.locked, pending: tree.pendingVotes.contains(post.id)) { option in Task { await tree.vote(post, optionId: option) } } }
            if let images = post.images, !images.isEmpty { TreeholeImageGrid(postId: post.id, images: images, full: full, api: tree.api) { index in gallery = TreeholeGallerySelection(postId: post.id, images: images, index: index) } }
            if !full, let count = post.newReplyCount, count > 0 { Button("\(count) 条新回复 · 接着聊") { open(post, comments: true) }.font(.caption).frame(minHeight: 40) }
            if tree.responsesEnabled { TreeholeResponses(post: post, disabled: tree.pendingResponses.contains(post.id)) { tree.respond(post, kind: $0) } }
            if post.locked { Label("已暂停回复", systemImage: "lock").font(.caption2).foregroundStyle(.secondary) }
            HStack {
                Button { if hasReply { tree.message = "请先发布回复，或返回时选择放弃"; return }; selectDiscovery(post.category ?? "daily", interest: post.interest ?? "") } label: { Text("# " + (TreeholeCategories.interestName(post.interest).isEmpty ? TreeholeCategories.name(post.category) : "兴趣 · " + TreeholeCategories.interestName(post.interest))).font(.caption).foregroundStyle(TreeholeTheme.muted).padding(.horizontal, 8).padding(.vertical, 5).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 6)).frame(minHeight: 44) }
                Spacer()
                if !full {
                    Button { open(post, comments: true) } label: { Label("\(post.commentCount)", systemImage: "bubble.right").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("查看评论，共 \(post.commentCount) 条")
                    Button { tree.react(post, kind: "like") } label: { Label("\(post.likeCount)", systemImage: post.liked ? "hand.thumbsup.fill" : "hand.thumbsup").frame(minWidth: 44, minHeight: 44) }.foregroundStyle(post.liked ? TreeholeTheme.primary : TreeholeTheme.muted).disabled(tree.pendingReactions.contains(post.id + ":like"))
                }
            }.font(.caption).foregroundStyle(TreeholeTheme.muted).buttonStyle(TreeholePressStyle())
        }.padding(.vertical, 18)
            .background {
                if !full { Button { open(post) } label: { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityHidden(true) }
            }
    }
    private func author(_ author: TreeholeAuthor, date: String, full: Bool) -> some View {
        HStack(spacing: 10) {
            TreeholeAvatar(name: author.name, anonymous: author.anonymous, avatar: author.avatar, size: full ? 42 : 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(author.name).font(full ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                HStack(spacing: 5) { Text(TreeholePresentation.date(date)); if author.mine { Text("我").foregroundStyle(TreeholeTheme.primary).padding(.horizontal, 4).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 3)) } }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func startPost() { replyExpanded = false; replyTo = nil; replyText = ""; replyPhotos = []; pickedReplyPhotos = []; replyAnonymous = false; commentRequest = UUID().uuidString; if !draft.value.hasContent { draft.value.category = tree.category == "all" ? "daily" : tree.category; draft.value.interest = tree.category == "entertainment" ? tree.interest : nil; if draft.value.category == "treehole" { draft.value.anonymous = true } }; screen = "compose" }
    private func selectDiscovery(_ category: String, interest: String = "") {
        guard !tree.busy else { return }
        if screen == "detail", hasReply { tree.message = "请先发布回复，或返回时选择放弃"; return }
        screen = "feed"; tree.leaveDetail(); tree.perform { try await tree.selectDiscovery(category, interest: interest) }
    }
    private func reloadFeed() { tree.perform { try await tree.feed() } }
    private func contentMenu(_ post: TreeholePost, comment: TreeholeComment? = nil) -> some View {
        let mine = comment?.author.mine ?? post.author.mine
        let anon = comment?.author.anonymous ?? post.anonymous
        let target = TreeholeTarget(postId: post.id, commentId: comment?.id)
        return Menu {
            if mine {
                Button("删除", role: .destructive) { confirmation = TreeholeConfirmation(title: "删除这条内容？") {
                    _ = try await tree.api.request(comment == nil ? "posts.delete" : "comments.delete", target.payload)
                    if comment == nil { tree.posts.removeAll { $0.id == post.id }; screen = "feed"; tree.current = nil } else { try await tree.detail(post) }
                } }
            } else {
                Button("举报") { reportReason = ""; reportTarget = target }
                Button(anon ? "隐藏这条讨论" : "屏蔽昵称发言") { confirmation = TreeholeConfirmation(title: anon ? "隐藏这条讨论？" : "屏蔽此人的昵称发言？匿名内容不会关联屏蔽。") {
                    _ = try await tree.api.request("blocks.set", target.payload); if !anon, let id = (comment?.author ?? post.author).id { tree.didBlockPublicAuthor(id) }; routes = []; tree.current = nil; screen = "feed"; try await tree.feed()
                } }
            }
        } label: { Image(systemName: "ellipsis").padding(10) }.accessibilityLabel("内容操作")
    }
    @ViewBuilder private func account(_ user: TreeholeMember) -> some View {
        if accountPage == "overview" {
            VStack(spacing: 12) {
                TreeholeAvatar(name: user.nickname, avatar: user.avatar, size: 66)
                Text(user.nickname).font(.title2.bold())
                Text("@" + user.username).font(.caption).foregroundStyle(.secondary)
                Text("用自己的昵称，留下校园里的回声。").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
            if tree.avatarsEnabled { TreeholeAvatarEditor(tree: tree) }
            HStack(spacing: 0) {
                Button { accountFeed("mine") } label: { VStack(spacing: 10) { Image(systemName: "bubble.left").font(.title3); Text("我的帖子").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }
                Divider()
                Button { accountFeed("saved") } label: { VStack(spacing: 10) { Image(systemName: "bookmark").font(.title3); Text("我的收藏").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }
            }.fixedSize(horizontal: false, vertical: true).campusCard()
            if tree.engagementEnabled {
                HStack { Button { accountFeed("participated") } label: { Label("我参与的", systemImage: "bubble.left.and.bubble.right").frame(maxWidth: .infinity, minHeight: 44) }; Button(action: showInbox) { Label("互动消息", systemImage: "bell").frame(maxWidth: .infinity, minHeight: 44) } }.font(.subheadline).campusCard()
            }
            VStack(spacing: 0) {
                if tree.followingEnabled { settingsRow("我关注的人", symbol: "person.2", action: showFollowing) }
                settingsRow("修改昵称", symbol: "person.crop.circle") { accountPage = "profile" }
                Divider()
                settingsRow("账号安全", symbol: "lock.shield") { password = ""; newPassword = ""; accountPage = "password" }
                Divider()
                settingsRow("恢复已屏蔽的内容", symbol: "eye.slash") { confirmation = TreeholeConfirmation(title: "恢复所有已屏蔽的内容？") { _ = try await tree.api.request("blocks.clear"); tree.feedNeedsRefresh = true; tree.message = "已恢复屏蔽的内容" } }
                if user.role == "moderator" { Divider(); settingsRow("处理举报", symbol: "flag") { tree.perform { tree.reports = try await tree.api.request("admin.reports").reports ?? []; screen = "moderate" } } }
            }.campusCard()
            Button { confirmation = TreeholeConfirmation(title: "退出邯院通账号？") { _ = try await tree.api.request("logout"); draft.clear(); tree.clear(); screen = "feed" } } label: { Label("退出邯院通账号", systemImage: "rectangle.portrait.and.arrow.right").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 6) }.campusCard()
            Button("注销邯院通账号") { password = ""; accountPage = "delete" }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                if accountPage == "profile" {
                    Text("其他同学会看到这个昵称。").font(.subheadline).foregroundStyle(.secondary)
                    TextField("公开昵称", text: $nickname).textContentType(.nickname)
                    if tree.engagementEnabled { TextField("个人简介（选填）", text: $bio, axis: .vertical).lineLimit(2...4).onChange(of: bio) { bio = String($0.prefix(120)) } }
                    Button("保存资料") { tree.perform { var body = ["nickname": nickname]; if tree.engagementEnabled { body["bio"] = bio }; tree.user = try await tree.api.request("profile.update", body).user; tree.feedNeedsRefresh = true; accountPage = "overview" } }.buttonStyle(.borderedProminent).disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                } else if accountPage == "password" {
                    Text("修改后其他设备会退出登录，并生成新的恢复码。").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("当前密码", text: $password).textContentType(.password)
                    SecureField("新密码 · 至少 10 位", text: $newPassword).textContentType(.newPassword)
                    Button("修改密码") { tree.perform { let r = try await tree.api.request("password.change", ["password": password, "newPassword": newPassword]); password = ""; newPassword = ""; tree.recovery = r.recoveryCode; accountPage = "overview" } }.buttonStyle(.borderedProminent).disabled(password.isEmpty || newPassword.count < 10)
                } else {
                    Text("注销会删除你的帖子、评论和登录状态。学校课表保留。请输入当前密码确认身份。").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("当前密码", text: $password).textContentType(.password)
                    Button("注销邯院通账号", role: .destructive) { confirmation = TreeholeConfirmation(title: "注销账号并删除全部社区内容？") { _ = try await tree.api.request("account.delete", ["password": password]); password = ""; draft.clear(); tree.clear(); screen = "feed" } }.buttonStyle(.bordered).disabled(password.isEmpty)
                }
            }.textFieldStyle(.roundedBorder).campusCard()
        }
    }
    private func settingsRow(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 12) { Image(systemName: symbol).frame(width: 22).foregroundStyle(TreeholeTheme.muted); Text(label).foregroundStyle(TreeholeTheme.text); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }.font(.subheadline).padding(.vertical, 14) }.buttonStyle(.plain)
    }
    private func accountFeed(_ scope: String) { tree.perform { try await tree.selectScope(scope); routes = []; searchOpen = false; screen = "feed" } }
    private func reportSheet(_ target: TreeholeTarget) -> some View {
        NavigationStack {
            Form {
                Section("举报原因") { TextEditor(text: $reportReason).frame(minHeight: 120).onChange(of: reportReason) { reportReason = String($0.prefix(300)) }; Text("例如：泄露隐私、骚扰、垃圾广告").font(.caption) }
                if let message = tree.message { Text(message).foregroundStyle(.red) }
                Button("提交举报") { tree.perform { var payload = target.payload; payload["reason"] = reportReason; _ = try await tree.api.request("reports.create", payload); reportTarget = nil; tree.message = "举报已提交" } }.disabled(tree.busy || reportReason.count < 2)
            }.navigationTitle("举报内容").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { reportTarget = nil }.disabled(tree.busy) } }.interactiveDismissDisabled(tree.busy)
        }
    }
    private var moderation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("举报处理").font(.title2.bold())
            if tree.reports.isEmpty { Text("暂无待处理举报。").foregroundStyle(.secondary) }
            ForEach(tree.reports) { report in
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.body); Text("举报原因：" + report.reason).font(.caption)
                    HStack { ForEach([("remove", "删除"), ("lock", "锁帖"), ("ban", "禁言 7 天"), ("dismiss", "忽略")], id: \.0) { decision, label in
                        Button(label) { confirmation = TreeholeConfirmation(title: "确认\(label)？") { _ = try await tree.api.request("admin.resolve", ["reportId": report.id, "decision": decision, "reason": report.reason]); tree.reports = try await tree.api.request("admin.reports").reports ?? []; tree.feedNeedsRefresh = true } }
                    } }.font(.caption)
                }.campusCard()
            }
        }
    }
    private func routeFrame() -> TreeholeRouteFrame {
        TreeholeRouteFrame(screen: screen, post: tree.current, comments: tree.comments, next: tree.commentNext, context: tree.focusedThread, profile: tree.publicProfile, profilePosts: tree.profilePosts, profileNext: tree.profileNext)
    }
    private func previousRoute() {
        guard let frame = routes.popLast() else { returnToFeed(); return }
        tree.leaveDetail(); tree.current = frame.post.map { tree.restoreResponse($0) }; tree.comments = frame.comments; tree.commentNext = frame.next; tree.focusedThread = frame.context
        tree.publicProfile = frame.profile.map { tree.restoreProfile($0) }; tree.profilePosts = frame.profilePosts.map { tree.restoreResponse($0) }; tree.profileNext = frame.profileNext
        initialDetailTarget = frame.context == nil ? "post" : "context"; screen = frame.screen
        if screen == "feed" && tree.feedNeedsRefresh { reloadFeed() }
        if screen == "following" { Task { await tree.loadFollowing() } }
    }
    private func showFollowing() {
        guard tree.followingEnabled else { return }; routes.append(routeFrame()); screen = "following"
        Task { await tree.loadFollowing() }
    }
    private func showInbox() {
        routes.append(routeFrame()); screen = "inbox"
        Task { await tree.loadInbox() }
    }
    private func openNotification(_ item: TreeholeNotification) {
        let frame = routeFrame()
        tree.perform {
            try await tree.notificationDetail(item)
            routes.append(frame); replyText = ""; replyPhotos = []; pickedReplyPhotos = []; replyTo = nil; replyAnonymous = false; commentRequest = UUID().uuidString
            initialDetailTarget = tree.focusedThread != nil ? "context" : item.commentId != nil ? "comments" : "post"
            detailTab = item.commentId == nil ? "body" : "comments"; screen = "detail"
        }
    }
    private func showProfile(_ id: String) {
        guard tree.engagementEnabled, !(screen == "profile" && tree.publicProfile?.id == id) else { return }
        let frame = routeFrame()
        tree.perform { try await tree.profile(id); routes.append(frame); screen = "profile" }
    }
    @ViewBuilder private var publicProfile: some View {
        if let profile = tree.publicProfile {
            VStack(spacing: 12) {
                TreeholeAvatar(name: profile.nickname, avatar: profile.avatar, size: 64)
                Text(profile.nickname).font(.title2.bold())
                Text(profile.bio.isEmpty ? "还没有填写简介" : profile.bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("\(profile.postCount) 条公开帖子").font(.caption).foregroundStyle(.secondary)
                if tree.followingEnabled, profile.id != tree.user?.id {
                    Button { Task { await tree.setFollow(profile.id, enabled: profile.following != true) } } label: {
                        Text(tree.pendingFollows.contains(profile.id) ? "处理中…" : profile.following == true ? "已关注 · 取消关注" : "关注 TA").font(.subheadline).padding(.horizontal, 24).frame(minHeight: 44)
                    }.buttonStyle(.bordered).disabled(tree.pendingFollows.contains(profile.id)).accessibilityAddTraits(profile.following == true ? .isSelected : [])
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 24)
            Label("这里展示公开帖子，匿名发言不会出现在主页", systemImage: "checkmark.shield").font(.caption2).foregroundStyle(.secondary)
            Divider()
            if tree.profilePosts.isEmpty { CampusEmpty(title: "还没有公开帖子", detail: "之后再来看看吧", symbol: "bubble.left") }
            LazyVStack(spacing: 0) { ForEach(tree.profilePosts) { post in postCard(post); Divider() } }
            if tree.profileNext != nil { Button("更多公开帖子") { tree.perform { try await tree.profile(profile.id, more: true) } }.frame(maxWidth: .infinity, minHeight: 44) }
        }
    }
    private func open(_ post: TreeholePost, comments: Bool = false) {
        guard !tree.busy, screen != "detail" else { return }
        routes.append(routeFrame())
        scrollIntentUntil = Date().addingTimeInterval(0.65)
        initialDetailTarget = comments ? "comments" : "post"; detailTab = comments ? "comments" : "body"
        replyExpanded = false; replyText = ""; replyPhotos = []; pickedReplyPhotos = []; replyTo = nil; replyAnonymous = false; commentRequest = UUID().uuidString
        tree.openDetail(post); screen = "detail"
    }
    private func back() {
        replyFocused = false
        if screen == "account" && accountPage != "overview" { accountPage = "overview"; password = ""; newPassword = ""; return }
        if screen == "moderate" { screen = "account"; return }
        if (screen == "compose" && draft.value.hasContent) || (screen == "detail" && hasReply) { discard = true; return }
        password = ""; newPassword = ""; previousRoute()
    }
    static let rules = "尊重同学，勿发布他人隐私、辱骂、骚扰、垃圾广告或违法内容。可以举报、删除自己的内容和注销账号。匿名会对其他用户隐藏昵称与账号，后台保留账号关联用于处理举报；不同帖子使用不同匿名代号，同一帖子内的匿名发言可关联。请留意文字本身是否暴露身份。账号服务保存登录账号、昵称、密码加密摘要、帖子、互动与举报记录，用于登录及社区服务。教务账号与课表不会上传到社区。可以在账号设置中注销。"
}
private struct TreeholeRouteFrame {
    let screen: String
    let post: TreeholePost?
    let comments: [TreeholeComment]
    let next: [String: String]?
    let context: TreeholeComment?
    let profile: TreeholePublicProfile?
    let profilePosts: [TreeholePost]
    let profileNext: [String: String]?
}
// Derive presentation only from the public alias, never an account identifier.
struct TreeholeAvatar: View {
    let name: String
    var anonymous = false
    var avatar: TreeholeImage? = nil
    var size: CGFloat = 42
    private var tone: Color {
        let palette = ["green", "blue", "purple", "orange"]
        let index = name.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return CampusTheme.course(palette[index])
    }
    var body: some View {
        Group {
            if anonymous { Image(systemName: "theatermasks").font(.system(size: size * 0.43, weight: .medium)) }
            else if let source = avatar?.url, let url = URL(string: source) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Text(String(name.prefix(1))).font(.system(size: size * 0.43, weight: .medium)) }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.34))
            } else { Text(String(name.prefix(1))).font(.system(size: size * 0.43, weight: .medium)) }
        }.foregroundStyle(tone).frame(width: size, height: size).background(tone.opacity(0.13), in: RoundedRectangle(cornerRadius: anonymous ? size / 2 : size * 0.34)).accessibilityHidden(true)
    }
}
private struct TreeholeTarget: Identifiable {
    let postId: String; let commentId: String?
    var id: String { postId + (commentId ?? "") }
    var payload: [String: Any] { var value: [String: Any] = ["postId": postId]; if let commentId { value["commentId"] = commentId }; return value }
}
private struct TreeholeConfirmation { let title: String; let action: @MainActor () async throws -> Void }

private struct TreeholeDiscussionOffset: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
enum TreeholeTheme {
    static let surface = Color(uiColor: .systemBackground)
    static let background = Color(uiColor: .secondarySystemBackground)
    static let text = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let primary = CampusTheme.primary
    static let onPrimary = Color.white
    static let tint = CampusTheme.primary.opacity(0.08)
}

private struct TreeholeViewportHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct TreeholeFeedEndOffset: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct TreeholeFeedFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, fresh in fresh }) }
}

private struct TreeholePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.66 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
