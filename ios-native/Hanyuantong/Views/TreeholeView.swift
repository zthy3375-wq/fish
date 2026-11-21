import SwiftUI
import PhotosUI

struct TreeholeView: View {
    @EnvironmentObject var tree: TreeholeStore
    @State private var honorRoute: CampusHonorRoute?
    @State private var showHonorManagement = false
    @State private var buddyRosterPost: TreeholePost?
    private var buddyValid: Bool { guard let buddy = draft.value.buddy else { return true }; return tree.buddiesEnabled && buddy.valid && draft.value.category == "buddies" && draft.value.poll == nil && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @State private var screen = "feed"
    @State private var routes: [TreeholeRouteFrame] = []
    @State private var bio = ""
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("medal.reduce") private var localReduceMotion = false
    private var reduceMotion: Bool { systemReduceMotion || localReduceMotion }
    @State private var pageOffset: CGFloat = 0
    @State private var selectedPhoto: String?
    @State private var composeCollapsed = false
    @State private var feedScrollSample: CGFloat = 0

    private var pageAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.24) }
    @State private var auth = "login"
    @State private var username = ""
    @State private var password = ""
    @State private var showAuthPassword = false
    @FocusState private var authPasswordFocused: Bool
    @State private var nickname = ""
    @State private var registrationNickname = ""
    @State private var recoveryInput = ""
    @State private var registrationRecovery: String?
    @State private var newPassword = ""
    @StateObject private var draft = TreeholeDraftStore()
    @State private var pickedPhotos: [CampusPhotoItem] = []
    @State private var gallery: TreeholeGallerySelection?
    @Environment(\.scenePhase) private var scenePhase
    @State private var communityVisible = false
    private var anonymous: Bool { draft.value.anonymous }
    @State private var replyExpanded = false
    @State private var sendingReply = false
    @State private var replyError: String?
    @State private var publishedReply: UUID?
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
    @State private var pickedReplyPhotos: [CampusPhotoItem] = []
    private var hasReply: Bool { !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !replyPhotos.isEmpty }
    private var replyOverlayVisible: Bool { replyExpanded && screen == "detail" && tree.current != nil && tree.user != nil }
    private var uploadedReplyPhotos: Int { replyPhotos.filter { $0.remote != nil }.count }
    @State private var replyText = ""
    @State private var reportReason = ""
    @State private var commentRequest = UUID().uuidString
    @State private var replyTo: TreeholeComment?
    @State private var moderateTarget:TreeholeTarget?
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
        case "account": return accountPage == "overview" ? "我的社区" : accountPage == "settings" ? "社区设置" : accountPage == "profile" ? "编辑资料" : accountPage == "password" ? "账号安全" : "注销账号"
        case "moderate": return "举报处理"
        default: return "邯院社区"
        }
    }
    private var replyIdentity: TreeholeReplyIdentity {
        TreeholeReplyIdentity(post: tree.current, preferredAnonymous: replyAnonymous)
    }
    var body: some View {
        ScrollViewReader { proxy in
            lifecycle(scrolling(proxy))
                .blur(radius: replyOverlayVisible && !reduceTransparency ? 2.5 : 0)
                .allowsHitTesting(!replyOverlayVisible)
                .accessibilityHidden(replyOverlayVisible)
                .overlay(alignment: .top) {
                    if let publishedReply, screen == "detail", !replyExpanded {
                        replyPublishedBanner(id: publishedReply)
                    }
                }
                .overlay(alignment: .bottom) {
                    if replyOverlayVisible, let post = tree.current {
                        replyOverlay(post)
                    }
                }
        }
    }
    private func scrolling(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                if tree.busy { ProgressView(tree.ready ? "正在处理…" : "正在连接社区").frame(maxWidth: .infinity) }
                if let message = tree.message {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(CampusTheme.text)
                        if !tree.ready { Button("重试连接") { tree.enter() } }
                        else if tree.user != nil && screen == "feed" { Button("重新加载") { tree.perform { try await tree.feed() } } }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CampusTheme.adaptive(light: 0xfff1e9, dark: 0x3a302b), in: RoundedRectangle(cornerRadius: 14))
                }
                if tree.ready && tree.user == nil { authentication }
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
        .onPreferenceChange(TreeholeFeedScrollY.self) { offset in
            guard screen == "feed" && tree.user != nil else { return }
            let y = max(0, offset)
            guard y < 80 || abs(y - feedScrollSample) > 14 else { return }
            composeCollapsed = y >= 80 && y > feedScrollSample
            feedScrollSample = y
        }
        .onPreferenceChange(TreeholeFeedEndOffset.self) { value in feedEndOffset = value; requestNextFeedPage() }
        .onChange(of: tree.busy) { value in if !value { requestNextFeedPage() } }
        .onChange(of: tree.feedRevision) { _ in feedAnchor = nil; if screen == "feed" { DispatchQueue.main.async { proxy.scrollTo("feed-top", anchor: .top) } } }
        .onChange(of: screen) { next in
            if previousScreen == "feed" { feedAnchor = visibleFeedPost }
            previousScreen = next
            composeCollapsed = false
            feedScrollSample = 0
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
        .campusKeyboardDismissal()
        .refreshable {
            guard screen == "feed", tree.user != nil, !tree.busy else { return }
            tree.busy = true; tree.message = nil
            defer { tree.busy = false }
            do { try await tree.feed(); await tree.refreshUnread(force: true) } catch {
                if let error = error as? TreeholeError, error.code == "session_expired" { tree.clear() }
                tree.message = (error as? TreeholeError)?.errorDescription ?? "连接失败，请检查网络后重试"
            }
        }
        .background(screen == "feed" || screen == "detail" || screen == "compose" ? TreeholeTheme.surface : TreeholeTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(tree.busy || screen != "feed")
        .campusTabBarHidden(screen != "feed" || tree.recovery != nil)
        .toolbar { communityToolbar(proxy) }
        .overlay(alignment: .bottomTrailing) {
            if screen == "feed" && tree.user != nil {
                Button(action: startPost) {
                    HStack(spacing: composeCollapsed ? 0 : 8) {
                        Image(systemName: "square.and.pencil").font(.system(size: 20))
                        Text("发帖").font(.subheadline.weight(.semibold)).fixedSize()
                            .frame(maxWidth: composeCollapsed ? 0 : nil).opacity(composeCollapsed ? 0 : 1).clipped()
                    }.padding(.horizontal, composeCollapsed ? 14 : 16).frame(height: 50)
                }.buttonStyle(CampusPressStyle())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: composeCollapsed)
                    .foregroundStyle(TreeholeTheme.onPrimary).background(Color(red: 0.15, green: 0.17, blue: 0.20), in: RoundedRectangle(cornerRadius: 15))
                    .shadow(color: TreeholeTheme.primary.opacity(0.18), radius: 12, y: 5).padding(20).disabled(tree.busy).accessibilityLabel("发帖")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if screen == "detail", let post = tree.current, tree.user != nil { replyBar(post) { scrollIntentUntil = Date().addingTimeInterval(0.65); detailTab = "comments"; withAnimation(pageAnimation) { proxy.scrollTo("comments", anchor: .top) } }.disabled(tree.busy) }
        }
    }
    @ToolbarContentBuilder
    private func communityToolbar(_ proxy: ScrollViewProxy) -> some ToolbarContent {
            ToolbarItem(placement: .principal) {
                if screen == "detail" {
                    HStack(spacing: 28) {
                        detailTabButton("正文", value: "body") { scrollIntentUntil = Date().addingTimeInterval(0.65); withAnimation(pageAnimation) { proxy.scrollTo("post", anchor: .top) } }
                        detailTabButton("评论", value: "comments") { scrollIntentUntil = Date().addingTimeInterval(0.65); withAnimation(pageAnimation) { proxy.scrollTo("comments", anchor: .top) } }
                    }.disabled(replyOverlayVisible)
                } else if screen != "feed" { Text(title).font(.headline) } else { Color.clear.frame(width: 1, height: 1) }
            }
            ToolbarItem(placement: .navigationBarLeading) { if screen == "feed" { CampusRootTitle(title: title) } else { Button { back() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("返回社区").disabled(tree.busy) } }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if screen == "compose" { Button("发布", action: publish).font(.body.weight(.semibold)).disabled(tree.busy || !buddyValid || (bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.value.photos.isEmpty && draft.value.poll == nil) || (draft.value.poll != nil && (!tree.pollsEnabled || draft.value.poll?.valid != true))) }
                else if screen == "account" && accountPage == "overview" {
                    Button { accountPage = "settings" } label: { Image(systemName: "gearshape") }.accessibilityLabel("社区设置")
                }
                else if screen == "feed", let user = tree.user {
                    Button { withAnimation { searchOpen.toggle() } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索帖子")
                    if tree.engagementEnabled { Button(action: showInbox) { Image(systemName: "bell").overlay(alignment: .topTrailing) { if tree.unreadCount > 0 { Text(tree.unreadCount > 99 ? "99+" : "\(tree.unreadCount)").font(.system(size: 9, weight: .bold)).padding(3).background(TreeholeTheme.primary, in: Capsule()).foregroundStyle(.white).offset(x: 9, y: -9) } } }.accessibilityLabel("互动消息") }
                    Button { showAccount(user) } label: { TreeholeAvatar(name: user.nickname, avatar: user.avatar, size: 32) }.accessibilityLabel("我的社区")
                }
            }
        }

    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
        .task { draft.bind(tree.user?.id); if !tree.ready { tree.enter() } }
        .onAppear { openRequestedAccount() }
        .onChange(of: tree.accountEntryRequested) { _ in openRequestedAccount() }
        .onDisappear { draft.flush() }
        .onChange(of: scenePhase) { if $0 != .active { draft.flush() } else { Task { await tree.refreshUnread() } } }
        .task(id: tree.user?.id) {
            guard tree.user != nil else { return }
            if scenePhase == .active && communityVisible { await tree.refreshUnread() }
        }
        .onChange(of: pickedPhotos) { items in loadPhotos(items) }
        .onChange(of: pickedReplyPhotos) { items in loadReplyPhotos(items) }
        .fullScreenCover(item: $gallery) { TreeholeGallery(selection: $0, api: tree.api) }
        .onChange(of: tree.user?.id) { identity in buddyRosterPost = nil; if identity == nil { auth = "login"; routes = [] }; draft.bind(identity); resetReply(); password = ""; newPassword = ""; accountPage = "overview"; screen = "feed"; openRequestedAccount() }
        .sheet(isPresented: Binding(get: { tree.recovery != nil }, set: { if !$0 { tree.recovery = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("保存你的账号恢复码", systemImage: "checkmark.shield").font(.title2.bold())
                Text("忘记密码时，用登录账号和这串恢复码找回。恢复码只在这次显示，请保存到密码管理器或安全位置。")
                Text(tree.recovery ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().background(TreeholeTheme.background).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("请勿发到树洞或分享给他人。").font(.caption).foregroundStyle(.secondary)
                Button("我已保存恢复码") { tree.recovery = nil }.buttonStyle(.borderedProminent)
            }.padding(24).interactiveDismissDisabled()
        }
        .sheet(isPresented: $showHonorManagement) { CampusHonorManagementView(tree: tree) }
        .sheet(item: $honorRoute) { route in CampusHonorCollectionView(tree: tree, route: route) }
        .sheet(item: $buddyRosterPost) { post in TreeholeBuddyRoster(post: post).environmentObject(tree) }
        .sheet(item:$moderateTarget) { t in
            if let me=tree.user {
                ContentModeration(postID:t.postId,commentID:t.commentId,locked:(tree.current ?? tree.posts.first{$0.id == t.postId})?.locked ?? false,viewer:me.id) {
                    routes=[]; tree.leaveDetail(); screen="feed"; tree.perform { try await tree.feed() }
                }
            }
        }
        .sheet(item: $reportTarget) { target in reportSheet(target) }
        .confirmationDialog(confirmation?.title ?? "确认操作", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            Button("确认", role: .destructive) { if let action = confirmation?.action { tree.perform(action) }; confirmation = nil }
            Button("取消", role: .cancel) { confirmation = nil }
        }
        .confirmationDialog("放弃还没发布的内容？", isPresented: $discard, titleVisibility: .visible) {
            if screen == "compose" { Button("保存草稿并返回") { draft.flush(); screen = "feed" } }
            Button("放弃并返回", role: .destructive) { if screen == "compose" { draft.clear() }; resetReply(); returnToFeed() }
            Button("继续编辑", role: .cancel) { }
        }
    }
    private var authentication: some View {
        VStack(spacing: 16) {
            authWelcome
            authForm
            DisclosureGroup {
                Text(Self.rules).font(.caption).foregroundStyle(CampusTheme.muted).padding(.top, 8)
            } label: {
                Label("树洞规则与匿名说明", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(CampusTheme.muted).frame(minHeight: 44)
            }
        }
    }

    private var authWelcome: some View {
        let headline = auth == "login" ? "说说校园里的那些事" : auth == "register" ? "遇见校园里的同频人" : "把账号找回来"
        return VStack(spacing: 12) {
            ZStack {
                Image(systemName: "bubble.left")
                    .font(.system(size: 36)).foregroundStyle(TreeholeTheme.primary)
                    .frame(width: 68, height: 60).background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 21))
                    .rotationEffect(.degrees(-10)).offset(x: -17, y: -3)
                Image(systemName: "theatermasks")
                    .font(.system(size: 23)).foregroundStyle(CampusTheme.adaptive(light: 0x396951, dark: 0xB8D2C2))
                    .frame(width: 48, height: 43).background(CampusTheme.walletGreen, in: RoundedRectangle(cornerRadius: 15))
                    .rotationEffect(.degrees(10)).offset(x: 23, y: 13)
                Image(systemName: "sparkles").font(.title3)
                    .foregroundStyle(CampusTheme.adaptive(light: 0x93662D, dark: 0xE6BE82))
                    .offset(x: 39, y: -25)
            }.frame(height: 84).accessibilityHidden(true)
            Text("邯院通 · 校园社区").font(.caption.weight(.semibold)).foregroundStyle(TreeholeTheme.primary)
            Text(headline).font(.title2.bold())
            Text("分享日常，认真倾听。\n用昵称相遇，也可以匿名说说心里话。")
                .font(.subheadline).foregroundStyle(CampusTheme.muted)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 8)
    }

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text(auth == "login" ? "登录邯院通" : auth == "register" ? "创建邯院通账号" : "找回邯院通账号")
                    .font(.headline)
                Spacer(minLength: 4)
                Text("与教务账号独立").font(.caption).foregroundStyle(CampusTheme.muted)
            }
            authInput("登录账号") {
                TextField("登录账号", text: $username, prompt: authPrompt("中文、数字、邮箱或其他账号"))
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("登录账号")
            }
            if auth == "register" {
                authInput("公开昵称") {
                    TextField("公开昵称", text: $registrationNickname, prompt: authPrompt("2–20 个字符")).textContentType(.nickname)
                        .accessibilityLabel("公开昵称")
                }
            }
            if auth == "recover" {
                authInput("账号恢复码") {
                    TextField("账号恢复码", text: $recoveryInput, prompt: authPrompt("注册时保存的恢复码"))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("账号恢复码")
                }
            }
            authPassword
            if auth == "register" {
                Text("点击「创建账号」即同意下方社区规则。社区会显示你填写的昵称，注册后可修改。")
                    .font(.caption).foregroundStyle(CampusTheme.muted)
            }
            Button(action: authenticate) {
                HStack {
                    Spacer(minLength: 0)
                    Text(auth == "login" ? "登录树洞" : auth == "register" ? "创建账号" : "重设密码并登录")
                        .foregroundColor(CampusTheme.onPrimary)
                    Image(systemName: "chevron.right").font(.caption)
                        .foregroundColor(CampusTheme.onPrimary).accessibilityHidden(true)
                    Spacer(minLength: 0)
                }.font(.subheadline.weight(.semibold)).frame(minHeight: 36)
            }.buttonStyle(.borderedProminent).tint(TreeholeTheme.primary)
                .disabled(tree.busy || (auth == "register" && !tree.registration))
            HStack {
                if auth != "register" && tree.registration { Button("注册账号") { switchAuth(to: "register") }.frame(minHeight: 44) }
                Spacer()
                if auth == "login" { Button("忘记密码") { switchAuth(to: "recover") }.frame(minHeight: 44) }
                else { Button("返回登录") { switchAuth(to: "login") }.frame(minHeight: 44) }
            }.font(.subheadline).foregroundStyle(TreeholeTheme.primary)
            if !tree.registration {
                Text("新账号注册暂未开放，已有账号可以直接登录。").font(.caption).foregroundStyle(CampusTheme.muted)
            }
        }.padding(16)
            .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(CampusTheme.border).allowsHitTesting(false) }
    }

    private func authPrompt(_ text: String) -> Text {
        Text(text).foregroundColor(CampusTheme.muted)
    }

    private func authInput<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).accessibilityHidden(true)
            content().font(.subheadline).padding(.horizontal, 10).frame(minHeight: 44)
                .background(CampusTheme.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(CampusTheme.border).allowsHitTesting(false) }
        }
    }

    private var authPassword: some View {
        let label = auth == "recover" ? "新密码" : "密码"
        return authInput(label) {
            HStack(spacing: 2) {
                Group {
                    if showAuthPassword {
                        TextField(label, text: $password, prompt: authPrompt("至少 10 位"))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        SecureField(label, text: $password, prompt: authPrompt("至少 10 位"))
                            .textContentType(auth == "login" ? .password : .newPassword)
                    }
                }.accessibilityLabel(label).focused($authPasswordFocused)
                    .onSubmit(authenticate)
                Button {
                    let wasFocused = authPasswordFocused
                    showAuthPassword.toggle()
                    if wasFocused {
                        Task { @MainActor in
                            await Task.yield()
                            authPasswordFocused = true
                        }
                    }
                } label: {
                    Image(systemName: showAuthPassword ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(showAuthPassword ? "隐藏密码" : "显示密码")
            }
        }
    }

    private func switchAuth(to mode: String) {
        authPasswordFocused = false
        showAuthPassword = false
        password = ""; recoveryInput = ""; registrationNickname = ""
        auth = mode
        tree.message = nil
    }

    private func authenticate() {
        guard !tree.busy, auth != "register" || tree.registration else { return }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tree.message = "请填写登录账号。"
            return
        }
        if auth == "register", !(2...20).contains(registrationName.utf16.count) {
            tree.message = "公开昵称需为 2–20 个字符。"
            return
        }
        if auth == "recover", recoveryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tree.message = "请填写账号恢复码。"
            return
        }
        if password.utf16.count < 10 {
            tree.message = "密码至少需要 10 位。"
            authPasswordFocused = true
            return
        }
        authPasswordFocused = false
        let mode = auth
        tree.perform {
            var payload: [String: Any] = ["username": username, "password": password]
            if mode == "register" {
                payload["agreed"] = true
                payload["nickname"] = registrationName
            }
            if mode == "recover" { payload["recoveryCode"] = recoveryInput }
            let result = try await tree.api.request(mode, payload)
            password = ""; recoveryInput = ""; registrationNickname = ""; showAuthPassword = false
            tree.user = result.user
            registrationRecovery = mode == "register" ? result.recoveryCode : nil
            tree.recovery = mode == "recover" ? result.recoveryCode : nil
            try await tree.feed()
            await tree.refreshUnread()
        }
    }

    private var registrationName: String {
        registrationNickname.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tree.engagementEnabled {
                TreeholeFeedScopes(tree: tree, select: accountFeed)
            }
            Color.clear.frame(height: 0).background(GeometryReader { bounds in
                Color.clear.preference(key: TreeholeFeedScrollY.self, value: -bounds.frame(in: .named("treehole-scroll")).minY)
            })
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
                    Text(["joined": "我报名的", "mine": "我的帖子", "saved": "我的收藏", "participated": "我参与的", "watching": "关注的讨论"][tree.scope] ?? "广场").font(.caption.weight(.semibold))
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
            TreeholeDiscoveryComposer(draft: $draft.value, enabled: tree.discoveryEnabled, boards:tree.boardsEnabled).disabled(draft.value.buddy != nil)
            TextField("添加标题（选填）", text: $draft.value.title).font(.system(size: 21, weight: .bold)).onChange(of: draft.value.title) { draft.value.title = String($0.prefix(40)) }
            Divider()
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty { Text("分享校园里的新鲜事…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                TextEditor(text: $draft.value.body).campusScrollBackground().frame(minHeight: 190).accessibilityLabel("想说的话").onChange(of: bodyText) { draft.value.body = String($0.prefix(3000)) }
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
                CampusPhotoPicker(selection: $pickedPhotos, maxSelectionCount: 9 - draft.value.photos.count, matching: .images) { Label("添加图片 · \(draft.value.photos.count)/9", systemImage: "photo.on.rectangle").font(.subheadline).padding(12).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 10)) }
            }
            buddyEditor
            if draft.value.poll != nil {
                TreeholePollEditor(poll: Binding(get: { draft.value.poll ?? TreeholePollDraft() }, set: { draft.value.poll = $0 })) { draft.value.poll = nil }
                if !tree.pollsEnabled { Text("投票暂不可用，草稿已保留").font(.caption).foregroundStyle(.secondary) }
            } else if tree.pollsEnabled && draft.value.buddy == nil { Button { draft.value.poll = TreeholePollDraft() } label: { Label("添加投票", systemImage: "chart.bar.xaxis").frame(minHeight: 44) } }
            if !draft.message.isEmpty { Text(draft.message).font(.caption2).foregroundStyle(.secondary) }
            HStack { Label("友善表达，尊重隐私", systemImage: "bubble.left"); Spacer(); Text("\(bodyText.count) / 3000") }.font(.caption2).foregroundStyle(.secondary)
            Divider()
            Label(anonymous ? "其他同学看不到你的昵称和账号。本帖内匿名回复使用同一代号。发布后身份方式固定。" : "帖子显示你的邯院通昵称。发布后身份方式固定。", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(.horizontal, 3).padding(.top, 8)
    }
    @ViewBuilder private var buddyEditor: some View {
        if draft.value.buddy != nil {
            TreeholeBuddyEditor(buddy: Binding(get: { draft.value.buddy ?? TreeholeBuddyDraft() }, set: { draft.value.buddy = $0 })) { draft.value.buddy = nil }.disabled(!tree.buddiesEnabled)
            if !tree.buddiesEnabled { Text("报名功能暂不可用，草稿已保留").font(.caption).foregroundStyle(.secondary) }
        } else if tree.buddiesEnabled && draft.value.category == "buddies" && draft.value.poll == nil {
            Button { draft.value.buddy = TreeholeBuddyDraft() } label: { Label("设置时间、地点和报名", systemImage: "person.2").frame(minHeight: 44) }
        }
    }
    private func loadPhotos(_ items: [CampusPhotoItem]) {
        guard !items.isEmpty else { return }
        tree.perform {
            defer { pickedPhotos = [] }
            for item in items.prefix(max(0, 9 - draft.value.photos.count)) {
                guard let bytes = try await item.loadData() else { throw TreeholeError(code: "invalid_image") }
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
            guard buddyValid else { tree.message = "请补全搭子说明、地点、人数和未来 90 天内的时间"; return }
            guard draft.value.poll == nil || tree.pollsEnabled && draft.value.poll?.valid == true else { return }
            for photo in draft.value.photos where photo.remote == nil {
                guard let remote = try await tree.api.request("media.upload", ["data": photo.data.base64EncodedString(), "requestId": photo.id]).image else { throw TreeholeError(code: "images_unavailable") }
                guard tree.user?.id == member, let index = draft.value.photos.firstIndex(where: { $0.id == photo.id }) else { throw CancellationError() }
                draft.value.photos[index].remote = remote; draft.flush()
            }
            let r = try await tree.api.request("posts.create", ["body": bodyText, "title": draft.value.title, "category": draft.value.category, "interest": ["entertainment","study"].contains(draft.value.category) ? draft.value.interest ?? "" : "", "anonymous": draft.value.category == "treehole" || anonymous, "requestId": draft.value.requestId, "images": draft.value.photos.compactMap { $0.remote?.id }, "buddy": draft.value.buddy?.payload as Any? ?? NSNull(), "poll": draft.value.poll?.payload as Any? ?? NSNull()])
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
    @ViewBuilder private var replyPhotoEditor: some View {
        if !replyPhotos.isEmpty || tree.commentImagesEnabled {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(replyPhotos.enumerated()), id: \.element.id) { index, photo in
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("评论图片预览 \(index + 1)")
                            .overlay(alignment: .topTrailing) {
                                Button { removeReplyPhoto(photo) } label: {
                                    Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundColor(.white)
                                        .frame(width: 24, height: 24).background(.black.opacity(0.62), in: Circle())
                                        .frame(width: 44, height: 44, alignment: .topTrailing).contentShape(Rectangle())
                                }.accessibilityLabel("移除评论图片 \(index + 1)").disabled(tree.busy)
                            }
                    }
                }
                if tree.commentImagesEnabled && replyPhotos.count < 3 {
                    CampusPhotoPicker(selection: $pickedReplyPhotos, maxSelectionCount: 3 - replyPhotos.count, matching: .images) {
                        VStack(spacing: 5) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 20))
                            Text("配图 \(replyPhotos.count)/3").font(.caption2)
                        }.frame(width: 72, height: 72)
                            .background(CampusTheme.background, in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityLabel("添加评论图片").disabled(tree.busy)
                }
            }.buttonStyle(.plain).foregroundStyle(TreeholeTheme.muted)
        }
    }
    private func loadReplyPhotos(_ items: [CampusPhotoItem]) {
        guard !items.isEmpty, tree.commentImagesEnabled else { return }
        let member = tree.user?.id, postId = tree.current?.id
        tree.perform {
            defer { pickedReplyPhotos = [] }
            for item in items.prefix(max(0, 3 - replyPhotos.count)) {
                guard let bytes = try await item.loadData() else { throw TreeholeError(code: "invalid_image") }
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
        guard canSendReply(post), let member = tree.user?.id, tree.current?.id == post.id else { return }
        guard replyPhotos.isEmpty || tree.commentImagesEnabled else {
            replyError = "评论图片暂不可用，已保留当前回复。"
            return
        }
        replyError = nil
        sendingReply = true
        tree.perform {
            defer { sendingReply = false }
            do {
                for photo in replyPhotos where photo.remote == nil {
                    guard let image = try await tree.api.request("media.upload", ["data": photo.data.base64EncodedString(), "requestId": photo.id, "purpose": "comment"]).image else { throw TreeholeError(code: "images_unavailable") }
                    guard member == tree.user?.id, tree.current?.id == post.id, let index = replyPhotos.firstIndex(where: { $0.id == photo.id }) else { throw CancellationError() }
                    replyPhotos[index].remote = image
                }
                _ = try await tree.api.request("comments.create", ["postId": post.id, "body": replyText, "anonymous": replyIdentity.isAnonymous, "requestId": commentRequest, "replyTo": replyTo?.id as Any? ?? NSNull(), "images": replyPhotos.compactMap { $0.remote?.id }])
            } catch is CancellationError {
                return
            } catch {
                guard member == tree.user?.id, tree.current?.id == post.id else { return }
                let failure = error as? TreeholeError
                if failure?.code == "session_expired" { throw error }
                if failure?.code == "image_unavailable" {
                    replyPhotos = replyPhotos.map { TreeholeDraftPhoto(id: UUID().uuidString, data: $0.data) }
                }
                replyError = failure?.errorDescription ?? "连接失败，请检查网络后重试"
                return
            }
            guard member == tree.user?.id, tree.current?.id == post.id else { return }
            closeReply()
            resetReply(keepIdentity: true)
            // A failed read after a confirmed send is a discussion refresh error.
            // The draft has already been committed and must not be submitted again.
            do { try await tree.detail(post) } catch { /* The discussion renders its own retry. */ }
            if member == tree.user?.id, tree.current?.id == post.id { publishedReply = UUID() }
        }
    }

    private func canSendReply(_ post: TreeholePost) -> Bool {
        !tree.busy && !post.locked && hasReply && replyText.utf16.count <= TreeholePresentation.replyLimit
    }

    private func openReply(to comment: TreeholeComment? = nil) {
        guard !tree.busy, let post = tree.current, !post.locked else { return }
        if let comment { replyTo = comment }
        publishedReply = nil
        tree.message = nil
        withAnimation(pageAnimation) { replyExpanded = true }
    }

    private func closeReply() {
        replyFocused = false
        withAnimation(pageAnimation) { replyExpanded = false }
    }

    private func resetReply(keepIdentity: Bool = false) {
        replyFocused = false
        replyExpanded = false
        replyText = ""
        replyPhotos = []
        pickedReplyPhotos = []
        replyTo = nil
        replyError = nil
        publishedReply = nil
        commentRequest = UUID().uuidString
        if !keepIdentity { replyAnonymous = false }
    }
    @ViewBuilder private func discussion(_ post: TreeholePost) -> some View {
        let visible = tree.comments.filter(tree.showsThread)
        postCard(post, full: true).id("post")
        if tree.engagementEnabled {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(post.watching == true ? "正在关注这段讨论" : "想知道后续？").font(.subheadline.weight(.semibold)); Text("新回复会出现在互动消息").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await tree.toggleWatch(post) } } label: { Label(post.watching == true ? "取消关注" : "关注讨论", systemImage: post.watching == true ? "bell.slash" : "bell").font(.caption).frame(minHeight: 44) }.disabled(tree.watchPending)
            }.padding(.vertical, 10)
            Divider()
        }
        if let context = tree.focusedThread, tree.showsThread(context) {
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
        if tree.detailLoading && visible.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 6).fill(TreeholeTheme.background).frame(width: 120, height: 28)
                RoundedRectangle(cornerRadius: 6).fill(TreeholeTheme.background).frame(height: 12)
                HStack { ProgressView(); Text("正在加载评论…").font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 24).frame(maxWidth: .infinity, minHeight: max(180, viewportHeight - 80), alignment: .topLeading)
        }
        else if visible.isEmpty && tree.detailError == nil && tree.commentNext == nil { CampusEmpty(title: "第一句回应，留给你", detail: "认真倾听，也是一种陪伴。", symbol: "bubble.left").frame(minHeight: max(180, viewportHeight - 80), alignment: .top) }
        else {
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, comment in
                    commentRow(comment, post: post, floor: index + 1)
                    if index < visible.count - 1 { Divider().padding(.leading, 44) }
                }
            }.frame(minHeight: max(180, viewportHeight - 80), alignment: .top)
        }
        if tree.commentNext != nil { Button(tree.detailLoading ? "正在加载…" : "加载更多评论") { Task { try? await tree.detail(post, more: true) } }.frame(maxWidth: .infinity, minHeight: 44).disabled(tree.detailLoading) }
        if post.locked { Label("这条讨论已暂停回复", systemImage: "lock").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding() }
    }
    private func commentRow(_ comment: TreeholeComment, post: TreeholePost, floor: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if !comment.deleted {
                TreeholeAvatar(name: comment.author.name, anonymous: comment.author.anonymous, avatar: comment.author.avatar, size: 36)
            }
            VStack(alignment: .leading, spacing: 9) {
                if !comment.deleted {
                    HStack(alignment: .top, spacing: 4) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                HonorByline(name:comment.author.name,badges:comment.author.anonymous ? nil : comment.author.badges).font(.system(size: 14, weight: .semibold))
                                if comment.isOriginalPoster { Text("楼主").font(.system(size: 10)).foregroundStyle(TreeholeTheme.primary).padding(.horizontal, 4).padding(.vertical, 2).background(TreeholeTheme.tint, in: RoundedRectangle(cornerRadius: 4)) }
                            }
                            Text(TreeholePresentation.date(comment.createdAt) + (floor > 0 ? " · \(floor) 楼" : "")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        commentLike(comment, post: post); contentMenu(post, comment: comment)
                    }

                    if !comment.displayBody.isEmpty { Text(comment.displayBody).font(.system(size: 16)).foregroundStyle(TreeholeTheme.text).lineSpacing(5).textSelection(.enabled) }
                    commentImages(comment, post: post)
                    HStack(spacing: 12) {
                        if !post.locked { Button("回复") { openReply(to: comment) }.font(.caption) }
                        if post.acceptedAnswerId == comment.id {
                            Label("已采纳", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(TreeholeTheme.primary)
                        }
                        if tree.autoAchievementsEnabled, post.category == "help", post.author.mine, !post.anonymous,
                           !post.locked, !comment.author.mine, !comment.author.anonymous, comment.replyTo == nil {
                            Button(post.acceptedAnswerId == comment.id ? "取消采纳" : "采纳回答") {
                                tree.perform { try await tree.setAcceptedAnswer(comment, on: post) }
                            }.font(.caption)
                        }
                    }.padding(.vertical, 4)
                }
                if tree.visibleReplyCount(comment) > 0 || tree.replyPages[comment.id] != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(comment.liveReplies.prefix(tree.expandedReplies.contains(comment.id) ? Int.max : 2))) { child in
                            VStack(alignment: .leading, spacing: 2) {
                                HonorByline(name: child.author.name, badges: child.author.anonymous ? nil : child.author.badges)
                                    .font(.subheadline.weight(.medium))
                                if let target = comment.replyRecipient(for: child) {
                                    Text("回复 " + target).font(.caption2).foregroundStyle(.secondary)
                                }
                                if child.isOriginalPoster { Text("楼主").font(.caption2).foregroundStyle(TreeholeTheme.primary) }
                                if !child.displayBody.isEmpty {
                                    Button { openReply(to: child) } label: {
                                        Text(child.displayBody).font(.subheadline).multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).disabled(post.locked)
                                } else if !post.locked {
                                    Button("回复") { openReply(to: child) }.font(.caption)
                                }
                                commentImages(child, post: post)
                                if tree.expandedReplies.contains(comment.id) { HStack { Text(TreeholePresentation.date(child.createdAt)).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); commentLike(child, post: post); contentMenu(post, comment: child) } }
                            }
                        }
                        if !tree.expandedReplies.contains(comment.id) || tree.replyPages[comment.id] != nil {
                            Divider()
                            Button(tree.loadingThreads.contains(comment.id) ? "正在加载…" : tree.expandedReplies.contains(comment.id) ? "加载更多回复" : "全部 \(tree.visibleReplyCount(comment)) 条回复") { tree.expand(comment, post: post) }.font(.caption).frame(maxWidth: .infinity, minHeight: 30).disabled(tree.loadingThreads.contains(comment.id))
                        }
                        if tree.expandedReplies.contains(comment.id) { Button("收起回复") { tree.collapse(comment) }.font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 30).disabled(tree.loadingThreads.contains(comment.id)) }
                    }.padding(10).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }.padding(.vertical, 20)
    }
    private func commentLike(_ comment: TreeholeComment, post: TreeholePost) -> some View {
        Button { tree.likeComment(comment, post: post) } label: { Label("\(comment.likeCount ?? 0)", systemImage: comment.liked == true ? "hand.thumbsup.fill" : "hand.thumbsup").font(.caption2) }.foregroundStyle(comment.liked == true ? TreeholeTheme.primary : TreeholeTheme.muted).disabled(tree.pendingCommentLikes.contains(comment.id)).accessibilityLabel(comment.liked == true ? "取消评论点赞" : "评论点赞")
    }
    private func detailTabButton(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        Button { detailTab = value; action() } label: {
            VStack(spacing: 7) { Text(label).font(.system(size: 16, weight: detailTab == value ? .semibold : .regular)); Capsule().fill(detailTab == value ? TreeholeTheme.text : .clear).frame(height: 3) }
        }.foregroundStyle(detailTab == value ? TreeholeTheme.text : TreeholeTheme.muted).accessibilityAddTraits(detailTab == value ? .isSelected : [])
    }
    private func replyBar(_ post: TreeholePost, showComments: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button { openReply() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil").font(.system(size: 16)).accessibilityHidden(true)
                    Text(post.locked ? "讨论已暂停" : hasReply ? "继续编辑回复…" : "说点什么吧…").lineLimit(1)
                    Spacer(minLength: 0)
                }.font(.subheadline).foregroundStyle(TreeholeTheme.muted)
                    .padding(.horizontal, 11).frame(minHeight: 44)
                    .background(CampusTheme.background, in: Capsule())
                    .contentShape(Capsule())
            }.disabled(post.locked).accessibilityIdentifier("community-quick-reply")
            Button { tree.react(post, kind: "like") } label: { barAction(post.likeCount > 0 ? "\(post.likeCount)" : "点赞", icon: post.liked ? "heart.fill" : "heart") }.modifier(ReactionFeedback(active: post.liked)).foregroundStyle(post.liked ? Color(hex: 0xc45c74) : TreeholeTheme.muted).disabled(tree.pendingReactions.contains(post.id + ":like")).accessibilityLabel(post.liked ? "取消点赞" : "点赞")
            Button { tree.react(post, kind: "save") } label: { barAction(post.saved ? "已收藏" : "收藏", icon: post.saved ? "bookmark.fill" : "bookmark") }.modifier(ReactionFeedback(active: post.saved)).foregroundStyle(post.saved ? TreeholeTheme.primary : TreeholeTheme.muted).disabled(tree.pendingReactions.contains(post.id + ":save")).accessibilityLabel(post.saved ? "取消收藏" : "收藏")
            Button(action: showComments) { barAction(post.commentCount > 0 ? "\(post.commentCount)" : "评论", icon: "bubble.right") }.foregroundStyle(TreeholeTheme.muted).accessibilityLabel("查看评论")
        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 680)
            .frame(maxWidth: .infinity).background(TreeholeTheme.surface)
            .overlay(alignment: .top) { Divider() }
    }

    private func barAction(_ label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20))
            Text(label).font(.caption2).lineLimit(1)
        }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    private func replyPublishedBanner(id: UUID) -> some View {
        Label("回复已发布", systemImage: "checkmark")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CampusTheme.adaptive(light: 0x396951, dark: 0xB8D2C2))
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(CampusTheme.walletGreen, in: Capsule())
            .padding(.top, 8).allowsHitTesting(false)
            .task(id: id) {
                do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { return }
                if publishedReply == id { publishedReply = nil }
            }
    }

    private func replyOverlay(_ post: TreeholePost) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.26).ignoresSafeArea(.container)
                .onTapGesture { if !tree.busy { closeReply() } }
                .accessibilityHidden(true)
                .transition(.opacity)
            replyEditor(post)
                .padding(.top, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func replyEditor(_ post: TreeholePost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(CampusTheme.border).frame(width: 32, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 6).accessibilityHidden(true)
            HStack {
                Text(replyTo.map { "回复 " + $0.author.name } ?? "写评论").font(.headline)
                Spacer()
                Button(action: closeReply) {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("收起回复编辑器").disabled(tree.busy).foregroundStyle(TreeholeTheme.muted)
            }
            ViewThatFits(in: .vertical) {
                replyFields(post).fixedSize(horizontal: false, vertical: true)
                ScrollView { replyFields(post) }
            }
            Divider().padding(.top, 7)
            replyFooter(post).padding(.vertical, 7)
        }.buttonStyle(.plain)
            .padding(.horizontal, 16).frame(maxWidth: 680)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(TreeholeTheme.surface)
                    .padding(.bottom, -22).ignoresSafeArea(.container, edges: .bottom)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(.escape) { if !tree.busy { closeReply() } }
            .task {
                await Task.yield()
                if replyExpanded { replyFocused = true }
            }
    }

    private func replyFields(_ post: TreeholePost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTo {
                HStack(spacing: 8) {
                    Text(replyTo.displayBody.isEmpty ? "[图片]" : replyTo.displayBody)
                        .font(.footnote).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    Button { self.replyTo = nil } label: {
                        Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("取消回复").disabled(tree.busy)
                }.padding(.leading, 10).foregroundStyle(TreeholeTheme.muted)
                    .background(CampusTheme.tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }
            CampusMultilineField("说说你的想法…", text: $replyText, minimum: 4, maximum: 5)
                .focused($replyFocused).font(.body).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
                .background(replyFocused ? CampusTheme.background : .clear)
                .accessibilityLabel("你的回复").accessibilityIdentifier("community-reply-input")
                .onChange(of: replyText) { if $0.utf16.count > TreeholePresentation.replyLimit { replyText = TreeholePresentation.boundedReply($0) } }
                .disabled(tree.busy)
            replyPhotoEditor
            if sendingReply || replyError != nil { replyStatus(post) }
            if let message = tree.message, !sendingReply, replyError == nil {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func replyStatus(_ post: TreeholePost) -> some View {
        let hasError = replyError != nil
        return HStack(alignment: .top, spacing: 8) {
            if hasError { Image(systemName: "exclamationmark.circle").foregroundStyle(.red).accessibilityHidden(true) }
            else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                Text(hasError ? "发布未完成" : uploadedReplyPhotos < replyPhotos.count ? "正在上传图片…" : "正在发布回复…")
                    .font(.footnote.weight(.semibold))
                if !replyPhotos.isEmpty {
                    Text("已上传 \(uploadedReplyPhotos) / \(replyPhotos.count) 张图片").font(.caption)
                }
                if let replyError { Text(replyError).font(.caption).foregroundStyle(TreeholeTheme.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if hasError {
                Button("重试回复") { sendComment(post) }.font(.footnote.weight(.semibold))
                    .foregroundStyle(TreeholeTheme.primary).frame(minHeight: 44)
                    .disabled(!canSendReply(post))
            }
        }.padding(10).background(CampusTheme.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func replyFooter(_ post: TreeholePost) -> some View {
        CampusAdaptiveRow {
            HStack(spacing: 8) {
                replyAnonymousControl
                Spacer(minLength: 0)
                replyCharacterCount
                replySendButton(post)
            }
        } fallback: {
            VStack(alignment: .leading, spacing: 4) {
                replyAnonymousControl
                HStack { Spacer(); replyCharacterCount; replySendButton(post) }
            }
        }
    }

    private var replyAnonymousControl: some View {
        let identity = replyIdentity
        return Button { replyAnonymous.toggle() } label: {
            Label(identity.label, systemImage: "theatermasks")
                .font(.caption).fixedSize().padding(.horizontal, 8).frame(minHeight: 36)
                .foregroundStyle(identity.isAnonymous ? TreeholeTheme.primary : TreeholeTheme.muted)
                .background(identity.isAnonymous ? CampusTheme.tint : TreeholeTheme.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(CampusTheme.border).allowsHitTesting(false) }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.disabled(tree.busy || identity.isRequired)
            .accessibilityValue(identity.isAnonymous ? "已开启" : "已关闭")
            .accessibilityAddTraits(identity.isAnonymous ? .isSelected : [])
    }

    private var replyCharacterCount: some View {
        Text("\(replyText.utf16.count) / \(TreeholePresentation.replyLimit)")
            .font(.caption2.monospacedDigit()).foregroundStyle(TreeholeTheme.muted).fixedSize()
    }

    private func replySendButton(_ post: TreeholePost) -> some View {
        let enabled = canSendReply(post)
        return Button { sendComment(post) } label: {
            HStack(spacing: 5) {
                Text("发布回复").font(.footnote.weight(.semibold))
                Image(systemName: "arrow.up").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }.fixedSize().padding(.horizontal, 11).frame(minHeight: 44)
                .foregroundColor(CampusTheme.onPrimary)
                .background(TreeholeTheme.primary.opacity(enabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 9))
        }.disabled(!enabled)
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
            if let buddy = post.buddy { TreeholeBuddyCard(buddy: buddy, mine: post.author.mine, locked: post.locked, enabled: tree.buddiesEnabled, pending: tree.pendingBuddies.contains(post.id), join: { enabled in Task { await tree.buddyAction(post, action: "join", enabled: enabled) } }, close: { closed in Task { await tree.buddyAction(post, action: "close", enabled: closed) } }, members: { buddyRosterPost = post }) }
            if let poll = post.poll { TreeholePollCard(poll: poll, enabled: tree.pollsEnabled && !post.locked, pending: tree.pendingVotes.contains(post.id)) { option in Task { await tree.vote(post, optionId: option) } } }
            if let images = post.images, !images.isEmpty { TreeholeImageGrid(postId: post.id, images: images, full: full, api: tree.api) { index in gallery = TreeholeGallerySelection(postId: post.id, images: images, index: index) } }
            if !full, let count = post.newReplyCount, count > 0 { Button("\(count) 条新回复 · 接着聊") { open(post, comments: true) }.font(.caption).frame(minHeight: 40) }
            if tree.responsesEnabled { TreeholeResponses(post: post, disabled: tree.pendingResponses.contains(post.id), choose:{ tree.respond(post, kind:$0) }, kinds:tree.responseKinds) }
            if post.locked { Label("已暂停回复", systemImage: "lock").font(.caption2).foregroundStyle(.secondary) }
            HStack {
                Button { if hasReply { tree.message = "请先发布回复，或返回时选择放弃"; return }; selectDiscovery(post.category ?? "daily", interest: post.interest ?? "") } label: { Text("# " + (TreeholeCategories.interestName(post.interest).isEmpty ? TreeholeCategories.name(post.category) : "兴趣 · " + TreeholeCategories.interestName(post.interest))).font(.caption).foregroundStyle(TreeholeTheme.muted).padding(.horizontal, 8).padding(.vertical, 5).background(TreeholeTheme.background, in: RoundedRectangle(cornerRadius: 6)).frame(minHeight: 44) }
                Spacer()
                if !full {
                    Button { open(post, comments: true) } label: { Label("\(post.commentCount)", systemImage: "bubble.right").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("查看评论，共 \(post.commentCount) 条")
                    Button { tree.react(post, kind: "like") } label: { Label("\(post.likeCount)", systemImage: post.liked ? "heart.fill" : "heart").frame(minWidth: 44, minHeight: 44) }.modifier(ReactionFeedback(active:post.liked)).foregroundStyle(post.liked ? Color(hex:0xc45c74) : TreeholeTheme.muted).disabled(tree.pendingReactions.contains(post.id + ":like"))
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
                HonorByline(name:author.name,badges:author.anonymous ? nil : author.badges).font(full ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                Text(TreeholePresentation.date(date)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func startPost() { resetReply(); if !draft.value.hasContent { draft.value.category = tree.category == "all" ? "daily" : tree.category; draft.value.interest = tree.category == "entertainment" ? tree.interest : nil; if draft.value.category == "treehole" { draft.value.anonymous = true } }; screen = "compose" }
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
            if tree.moderationEnabled, tree.user?.permits("content") == true { Button("管理这条内容") { moderateTarget=target } }
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
    private func showAccount(_ user: TreeholeMember) {
        nickname = user.nickname
        bio = user.bio ?? ""
        password = ""
        newPassword = ""
        accountPage = "overview"
        screen = "account"
    }

    private func openRequestedAccount() {
        guard tree.accountEntryRequested, let user = tree.user else { return }
        tree.accountEntryRequested = false
        // Keep an in-progress edit when returning through another tab.
        guard screen != "compose", !(screen == "detail" && hasReply) else { return }
        showAccount(user)
    }

    @ViewBuilder private func account(_ user: TreeholeMember) -> some View {
        if accountPage == "overview" {
            HStack(alignment:.center,spacing:14) {
                TreeholeAvatar(name:user.nickname,avatar:user.avatar,size:56)
                VStack(alignment:.leading,spacing:4) {
                    HonorByline(name:user.nickname,badges:user.badges).font(.title3.weight(.semibold))
                    Text("@" + user.username).font(.caption).foregroundStyle(.secondary)
                    if let bio=user.bio, !bio.isEmpty { Text(bio).font(.subheadline).lineLimit(3) }
                }
                Spacer()
            }.padding(.vertical,12)
            ProfileSocialBar(member:user,following:showFollowing,open:showProfile)
            HonorShelfLink(badges: user.badges, pins: user.showcase ?? [], collection: user.collectionShowcase ?? [])
            if tree.honorCollectionEnabled {
                settingsRow("荣誉档案与佩戴", symbol: "seal") { honorRoute = CampusHonorRoute(memberId: user.id) }
            }
            HStack(spacing: 0) {
                Button { accountFeed("mine") } label: { VStack(spacing: 10) { Image(systemName: "bubble.left").font(.title3); Text("我的帖子").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }
                Divider()
                Button { accountFeed("saved") } label: { VStack(spacing: 10) { Image(systemName: "bookmark").font(.title3); Text("我的收藏").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }
            }.fixedSize(horizontal: false, vertical: true).campusCard()
            if tree.engagementEnabled {
                HStack { Button { accountFeed("participated") } label: { Label("我参与的", systemImage: "bubble.left.and.bubble.right").frame(maxWidth: .infinity, minHeight: 44) }; Button(action: showInbox) { Label("互动消息", systemImage: "bell").frame(maxWidth: .infinity, minHeight: 44) } }.font(.subheadline).campusCard()
            }
            if tree.buddiesEnabled { settingsRow("我报名的", symbol: "person.2") { accountFeed("joined") } }
            settingsRow("编辑资料", symbol: "person.crop.circle") { accountPage = "profile" }
        } else if accountPage == "settings" {
            if tree.honorsEnabled && (user.permits("users") || user.permits("recommend")) {
                NavigationLink { HonorManagement() } label: { Label("身份与荣誉管理",systemImage:"shield") }
            }
            VStack(spacing: 0) {
                if let registrationRecovery {
                    settingsRow("保存账号恢复码", symbol: "key") {
                        tree.recovery = registrationRecovery
                        self.registrationRecovery = nil
                    }
                }
                settingsRow("账号安全", symbol: "lock.shield") { password = ""; newPassword = ""; accountPage = "password" }
                if user.badges?.official?.code == "developer" {
                    NavigationLink { NativeMemberDirectory(viewer: user.id) } label: {
                        Label("注册成员列表", systemImage: "person.2")
                    }.frame(minHeight: 44)
                }
                if tree.honorCollectionEnabled && user.badges?.official?.code == "developer" {
                    settingsRow("荣誉与年度", symbol: "seal") { showHonorManagement = true }
                }
                Divider()
                settingsRow("恢复已屏蔽的内容", symbol: "eye.slash") { confirmation = TreeholeConfirmation(title: "恢复所有已屏蔽的内容？") { _ = try await tree.api.request("blocks.clear"); tree.feedNeedsRefresh = true; tree.message = "已恢复屏蔽的内容" } }
                if tree.moderationEnabled && user.permits("content") { NavigationLink("内容与审计") { ModerationBrowser(viewer:user.id) } }
                if user.permits("reports") || (user.role == "moderator" && !tree.moderationEnabled) { Divider(); settingsRow("处理举报", symbol: "flag") { tree.perform { tree.reports = try await tree.api.request("admin.reports").reports ?? []; screen = "moderate" } } }
            }.campusCard()
            Button { confirmation = TreeholeConfirmation(title: "退出邯院通账号？") { _ = try await tree.api.request("logout"); draft.clear(); registrationRecovery = nil; tree.clear(); screen = "feed" } } label: { Label("退出邯院通账号", systemImage: "rectangle.portrait.and.arrow.right").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 6) }.campusCard()
            Button("注销邯院通账号") { password = ""; accountPage = "delete" }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                if accountPage == "profile" {
                    Text("其他同学会看到这个昵称。").font(.subheadline).foregroundStyle(.secondary)
                    if tree.avatarsEnabled { TreeholeAvatarEditor(tree:tree) }
                    TextField("公开昵称", text: $nickname).textContentType(.nickname)
                    if tree.engagementEnabled { CampusMultilineField("个人简介（选填）", text: $bio, minimum: 2, maximum: 4).onChange(of: bio) { bio = String($0.prefix(120)) } }
                    Button("保存资料") { tree.perform { var body = ["nickname": nickname]; if tree.engagementEnabled { body["bio"] = bio }; tree.user = try await tree.api.request("profile.update", body).user; tree.feedNeedsRefresh = true; accountPage = "overview" } }.buttonStyle(.borderedProminent).disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                } else if accountPage == "password" {
                    Text("修改后其他设备会退出登录，并生成新的恢复码。").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("当前密码", text: $password).textContentType(.password)
                    SecureField("新密码 · 至少 10 位", text: $newPassword).textContentType(.newPassword)
                    Button("修改密码") { tree.perform { let r = try await tree.api.request("password.change", ["password": password, "newPassword": newPassword]); password = ""; newPassword = ""; tree.recovery = r.recoveryCode; accountPage = "overview" } }.buttonStyle(.borderedProminent).disabled(password.isEmpty || newPassword.count < 10)
                } else {
                    Text("注销会删除你的帖子、评论和登录状态。学校课表保留。请输入当前密码确认身份。").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("当前密码", text: $password).textContentType(.password)
                    Button("注销邯院通账号", role: .destructive) { confirmation = TreeholeConfirmation(title: "注销账号并删除全部社区内容？") { _ = try await tree.api.request("account.delete", ["password": password]); password = ""; draft.clear(); registrationRecovery = nil; tree.clear(); screen = "feed" } }.buttonStyle(.bordered).disabled(password.isEmpty)
                }
            }.textFieldStyle(.roundedBorder).campusCard()
        }
    }
    private func settingsRow(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 12) { Image(systemName: symbol).frame(width: 22).foregroundStyle(TreeholeTheme.muted); Text(label).foregroundStyle(TreeholeTheme.text); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }.font(.subheadline).padding(.vertical, 14) }.buttonStyle(.plain)
    }
    private func accountFeed(_ scope: String) { tree.perform { try await tree.selectScope(scope); routes = []; searchOpen = false; screen = "feed" } }
    private func reportSheet(_ target: TreeholeTarget) -> some View {
        CampusNavigation {
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
            routes.append(frame); resetReply()
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
                HonorByline(name:profile.nickname,badges:profile.badges).font(.title2.bold())
                HonorShelfLink(badges: profile.badges, pins: profile.showcase ?? [], collection: profile.collectionShowcase ?? [], memberID: profile.id)
                if tree.messagesEnabled, let me=tree.user, me.id != profile.id { NavigationLink { NativeMessages(viewer:me.id,member:profile.id) } label: { Label("发私信",systemImage:"envelope") } }
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
        resetReply()
        tree.openDetail(post); screen = "detail"
    }
    private func back() {
        guard !tree.busy else { return }
        if replyExpanded { closeReply(); return }
        replyFocused = false
        if screen == "account" && accountPage != "overview" { accountPage = ["password", "delete"].contains(accountPage) ? "settings" : "overview"; password = ""; newPassword = ""; return }
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
private struct TreeholeFeedScrollY: PreferenceKey {
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
