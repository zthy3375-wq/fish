import SwiftUI

struct TreeholeView: View {
    @EnvironmentObject var tree: TreeholeStore
    @State private var screen = "feed"
    @State private var auth = "login"
    @State private var username = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var invitation = ""
    @State private var recoveryInput = ""
    @State private var newPassword = ""
    @State private var agreed = false
    @State private var anonymous = false
    @State private var replyAnonymous = false
    @State private var bodyText = ""
    @State private var replyText = ""
    @State private var reportReason = ""
    @State private var postRequest = UUID().uuidString
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
        case "compose": return "发树洞"
        case "detail": return "树洞详情"
        case "account": return accountPage == "overview" ? "我的树洞" : accountPage == "profile" ? "修改昵称" : accountPage == "password" ? "账号安全" : "注销账号"
        case "moderate": return "举报处理"
        default: return "邯院树洞"
        }
    }
    private var forceAnonymous: Bool { tree.current?.anonymous == true && tree.current?.author.mine == true }
    var body: some View {
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
                    default: feed
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, screen == "feed" ? 88 : 24).frame(maxWidth: 680).frame(maxWidth: .infinity).disabled(tree.busy)
        }
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
        .background(CampusTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(tree.busy || screen != "feed")
        .toolbar {
            if screen != "feed" { ToolbarItem(placement: .navigationBarLeading) { Button { back() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("返回树洞").disabled(tree.busy) } }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if screen == "compose" { Button("发布", action: publish).fontWeight(.semibold).disabled(tree.busy || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                else if screen == "feed", let user = tree.user {
                    Button { withAnimation { searchOpen.toggle() } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索帖子")
                    Button { nickname = user.nickname; password = ""; newPassword = ""; accountPage = "overview"; screen = "account" } label: { TreeholeAvatar(name: user.nickname, size: 32) }.accessibilityLabel("我的树洞")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if screen == "feed" && tree.user != nil {
                Button(action: startPost) { Label("发树洞", systemImage: "square.and.pencil").font(.subheadline.weight(.semibold)).padding(.horizontal, 19).padding(.vertical, 16) }
                    .foregroundStyle(CampusTheme.onPrimary).background(CampusTheme.primary, in: RoundedRectangle(cornerRadius: 22))
                    .shadow(color: CampusTheme.primary.opacity(0.18), radius: 12, y: 5).padding(20).disabled(tree.busy).accessibilityLabel("发帖")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if screen == "detail", let post = tree.current, !post.locked, tree.user != nil { replyBar(post).disabled(tree.busy) }
        }
        .task { tree.enter() }
        .onChange(of: tree.user?.id) { identity in if identity == nil { auth = "login" }; bodyText = ""; replyText = ""; password = ""; newPassword = ""; replyTo = nil; accountPage = "overview"; screen = "feed" }
        .sheet(isPresented: Binding(get: { tree.recovery != nil }, set: { if !$0 { tree.recovery = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("保存你的账号恢复码", systemImage: "checkmark.shield").font(.title2.bold())
                Text("忘记密码时，用登录账号和这串恢复码找回。恢复码只在这次显示，请保存到密码管理器或安全位置。")
                Text(tree.recovery ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled).padding().background(CampusTheme.background).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("请勿发到树洞或分享给他人。").font(.caption).foregroundStyle(.secondary)
                Button("我已保存恢复码") { tree.recovery = nil }.buttonStyle(.borderedProminent)
            }.padding(24).interactiveDismissDisabled()
        }
        .sheet(item: $reportTarget) { target in reportSheet(target) }
        .confirmationDialog(confirmation?.title ?? "确认操作", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            Button("确认", role: .destructive) { if let action = confirmation?.action { tree.perform(action) }; confirmation = nil }
            Button("取消", role: .cancel) { confirmation = nil }
        }
        .confirmationDialog("放弃还没发布的文字？", isPresented: $discard, titleVisibility: .visible) {
            Button("放弃并返回", role: .destructive) { bodyText = ""; replyText = ""; replyTo = nil; screen = "feed" }
            Button("继续编辑", role: .cancel) { }
        }
    }
    private var authentication: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 42)).foregroundStyle(CampusTheme.primary)
                    .frame(width: 96, height: 96).background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 30)).rotationEffect(.degrees(-7)).accessibilityHidden(true)
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
                    password = ""; recoveryInput = ""; tree.user = result.user; tree.recovery = result.recoveryCode; try await tree.feed()
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label("校园里的小小回声", systemImage: "leaf").font(.caption).foregroundStyle(CampusTheme.primary)
                Text("平常的一天，也有值得分享的小事。").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
            Button(action: startPost) {
                HStack(spacing: 12) {
                    TreeholeAvatar(name: tree.user?.nickname ?? "")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("今天，想说点什么？").font(.subheadline.weight(.medium)).foregroundStyle(CampusTheme.text)
                        Text("分享日常，或匿名留下心里话").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pencil.line").foregroundStyle(CampusTheme.primary)
                }.frame(maxWidth: .infinity, alignment: .leading).campusCard()
            }.buttonStyle(.plain)
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
            HStack(spacing: 24) {
                ForEach([("all", "最新"), ("mine", "我的帖子"), ("saved", "收藏")], id: \.0) { scope, label in
                    Button { tree.scope = scope; reloadFeed() } label: {
                        VStack(spacing: 10) {
                            Text(label).font(.subheadline.weight(tree.scope == scope ? .semibold : .regular)).foregroundStyle(tree.scope == scope ? CampusTheme.text : CampusTheme.muted)
                            Capsule().fill(tree.scope == scope ? CampusTheme.primary : Color.clear).frame(width: 18, height: 3)
                        }.padding(.top, 10)
                    }.accessibilityAddTraits(tree.scope == scope ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button(action: reloadFeed) { Image(systemName: "arrow.clockwise").frame(width: 32, height: 44) }.accessibilityLabel("刷新树洞")
            }.buttonStyle(.plain)
            if tree.posts.isEmpty && !tree.busy && tree.message == nil {
                CampusEmpty(title: tree.query.isEmpty ? "这里还很安静" : "还没找到这段回声", detail: tree.query.isEmpty ? (tree.scope == "saved" ? "遇见喜欢的文字，点一下收藏。" : tree.scope == "mine" ? "你的第一条树洞，从一句话开始。" : "从一句想说的话开始。") : "换个关键词试试", symbol: "bubble.left.and.bubble.right")
            }
            ForEach(tree.posts) { post in postCard(post) }
            if tree.feedNext != nil { Button("加载更多") { tree.perform { try await tree.feed(more: true) } }.frame(maxWidth: .infinity).padding() }
            else if !tree.posts.isEmpty { Text("暂时就这些，过一会儿再来看看吧").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 22) }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                TreeholeAvatar(name: anonymous ? "匿名同学" : tree.user?.nickname ?? "", anonymous: anonymous)
                VStack(alignment: .leading, spacing: 5) {
                    Text(anonymous ? "匿名同学" : tree.user?.nickname ?? "").font(.subheadline.weight(.semibold))
                    Text(anonymous ? "这一次，放心做匿名的自己" : "用自己的昵称，分享校园日常").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            Toggle("匿名发布", isOn: $anonymous).font(.subheadline).tint(CampusTheme.primary)
            Divider()
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty { Text("今天有什么想分享的？\n开心的小事、偶尔的烦恼，都可以写在这里。").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                TextEditor(text: $bodyText).scrollContentBackground(.hidden).frame(minHeight: 290).accessibilityLabel("想说的话").onChange(of: bodyText) { bodyText = String($0.prefix(3000)) }
            }.font(.body).lineSpacing(7)
            HStack { Label("一句简单的话，也会有回声", systemImage: "bubble.left"); Spacer(); Text("\(bodyText.count) / 3000") }.font(.caption2).foregroundStyle(.secondary)
            Divider()
            Label(anonymous ? "其他同学看不到你的昵称和账号。本帖内匿名回复使用同一代号。发布后身份方式固定。" : "帖子显示你的邯院通昵称。发布后身份方式固定。", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(.horizontal, 3).padding(.top, 8)
    }
    private func publish() {
        tree.perform {
            let r = try await tree.api.request("posts.create", ["body": bodyText, "anonymous": anonymous, "requestId": postRequest])
            bodyText = ""; postRequest = UUID().uuidString
            if let post = r.post { tree.posts.insert(post, at: 0); try await tree.detail(post); screen = "detail" }
        }
    }
    @ViewBuilder private func discussion(_ post: TreeholePost) -> some View {
        postCard(post, full: true)
        HStack { Text("聊一聊").font(.headline); Text("\(post.commentCount)").font(.caption).foregroundStyle(.secondary); Spacer(); Text("友善交流，认真倾听").font(.caption2).foregroundStyle(.secondary) }.padding(.top, 12)
        if tree.comments.isEmpty { CampusEmpty(title: "第一句回应，留给你", detail: "认真倾听，也是一种陪伴。", symbol: "bubble.left") }
        else {
            VStack(spacing: 0) {
                ForEach(Array(tree.comments.enumerated()), id: \.element.id) { index, comment in
                    commentRow(comment, post: post, floor: index + 1)
                    if index < tree.comments.count - 1 { Divider().padding(.leading, 44) }
                }
            }.campusCard()
        }
        if tree.commentNext != nil { Button("加载更多评论") { tree.perform { try await tree.detail(post, more: true) } }.frame(maxWidth: .infinity) }
        if post.locked { Label("这条讨论已暂停回复", systemImage: "lock").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding() }
    }
    private func commentRow(_ comment: TreeholeComment, post: TreeholePost, floor: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TreeholeAvatar(name: comment.author.name, anonymous: comment.author.anonymous, size: 32)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(comment.author.name).font(.caption.weight(.semibold))
                            if comment.isOriginalPoster { Text("楼主").font(.system(size: 10)).foregroundStyle(CampusTheme.primary).padding(.horizontal, 4).padding(.vertical, 2).background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 4)) }
                        }
                        Text(TreeholePresentation.date(comment.createdAt) + " · \(floor) 楼").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !comment.deleted { contentMenu(post, comment: comment) }
                }
                if let parentID = comment.replyTo {
                    Text(quote(parentID)).font(.caption).foregroundStyle(.secondary).lineLimit(3).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(CampusTheme.background, in: RoundedRectangle(cornerRadius: 8))
                }
                Text(comment.body).font(.subheadline).foregroundStyle(comment.deleted ? CampusTheme.muted : CampusTheme.text).lineSpacing(5).textSelection(.enabled)
                if !comment.deleted && !post.locked { Button("回复") { replyTo = comment; replyFocused = true }.font(.caption).padding(.vertical, 4) }
            }
        }.padding(.vertical, 13)
    }
    private func quote(_ id: String) -> String {
        guard let parent = tree.comments.first(where: { $0.id == id }) else { return "回复的评论暂不可见" }
        return parent.deleted ? "这条评论已删除" : parent.author.name + "：" + parent.body
    }
    private func replyBar(_ post: TreeholePost) -> some View {
        VStack(spacing: 10) {
            if let replyTo {
                HStack { Text("回复 " + replyTo.author.name).font(.caption).lineLimit(1); Spacer(); Button { self.replyTo = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("取消回复") }.foregroundStyle(CampusTheme.primary)
            }
            TextField("留下一句温柔的回应…", text: $replyText, axis: .vertical).lineLimit(2...4).focused($replyFocused).font(.subheadline).padding(11).background(CampusTheme.background, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("你的回复").onChange(of: replyText) { replyText = String($0.prefix(1000)) }
            HStack(spacing: 12) {
                Button { replyAnonymous.toggle() } label: {
                    Label(forceAnonymous ? "保持楼主匿名身份" : replyAnonymous ? "匿名回复" : "昵称回复", systemImage: replyAnonymous || forceAnonymous ? "theatermasks" : "person.crop.circle")
                        .font(.caption2).padding(.horizontal, 10).padding(.vertical, 9).background(CampusTheme.tint, in: Capsule())
                }.disabled(forceAnonymous).accessibilityValue(replyAnonymous || forceAnonymous ? "匿名" : "昵称")
                Spacer(minLength: 0)
                Button {
                    tree.perform {
                        _ = try await tree.api.request("comments.create", ["postId": post.id, "body": replyText, "anonymous": replyAnonymous || forceAnonymous, "requestId": commentRequest, "replyTo": replyTo?.id as Any? ?? NSNull()])
                        replyText = ""; replyTo = nil; replyFocused = false; commentRequest = UUID().uuidString; try await tree.detail(post)
                    }
                } label: { Label("发布回复", systemImage: "arrow.up").font(.caption.weight(.semibold)) }
                    .buttonStyle(.borderedProminent).disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: 680).frame(maxWidth: .infinity).background(CampusTheme.surface).overlay(alignment: .top) { Divider() }
    }
    private func postCard(_ post: TreeholePost, full: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) { author(post.author, date: post.createdAt); Spacer(minLength: 3); contentMenu(post) }
            if full { Text(post.body).font(.body).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            else { Button { open(post) } label: { Text(post.body).font(.body).lineSpacing(7).lineLimit(6).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading) }.buttonStyle(.plain) }
            if post.locked { Label("已暂停回复", systemImage: "lock").font(.caption2).foregroundStyle(.secondary) }
            Divider()
            actions(post)
        }.campusCard()
    }
    private func author(_ author: TreeholeAuthor, date: String) -> some View {
        HStack(spacing: 10) {
            TreeholeAvatar(name: author.name, anonymous: author.anonymous)
            VStack(alignment: .leading, spacing: 5) {
                Text(author.name).font(.subheadline.weight(.semibold))
                HStack(spacing: 5) { Text(TreeholePresentation.date(date)); if author.mine { Text("我").foregroundStyle(CampusTheme.primary).padding(.horizontal, 4).background(CampusTheme.tint, in: RoundedRectangle(cornerRadius: 3)) } }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func actions(_ post: TreeholePost) -> some View {
        HStack {
            Button { tree.react(post, kind: "like") } label: { Label(post.likeCount == 0 ? "赞" : "\(post.likeCount)", systemImage: post.liked ? "heart.fill" : "heart") }.foregroundStyle(post.liked ? CampusTheme.primary : CampusTheme.muted).accessibilityLabel(post.liked ? "取消点赞" : "点赞")
            Spacer()
            Button { if screen == "detail" { replyFocused = true } else { open(post) } } label: { Label(post.commentCount == 0 ? "评论" : "\(post.commentCount)", systemImage: "bubble.right") }.foregroundStyle(CampusTheme.muted)
            Spacer()
            Button { tree.react(post, kind: "save") } label: { Label(post.saved ? "已收藏" : "收藏", systemImage: post.saved ? "bookmark.fill" : "bookmark") }.foregroundStyle(post.saved ? CampusTheme.primary : CampusTheme.muted)
        }.font(.caption).buttonStyle(.plain).padding(.vertical, 2)
    }
    private func startPost() { bodyText = ""; anonymous = false; postRequest = UUID().uuidString; screen = "compose" }
    private func reloadFeed() { tree.perform { try await tree.feed() } }
    private func contentMenu(_ post: TreeholePost, comment: TreeholeComment? = nil) -> some View {
        let mine = comment?.author.mine ?? post.author.mine
        let anon = comment?.author.anonymous ?? post.anonymous
        let target = TreeholeTarget(postId: post.id, commentId: comment?.id)
        return Menu {
            if mine {
                Button("删除", role: .destructive) { confirmation = TreeholeConfirmation(title: "删除这条内容？") {
                    _ = try await tree.api.request(comment == nil ? "posts.delete" : "comments.delete", target.payload)
                    if comment == nil { screen = "feed"; tree.current = nil; try await tree.feed() } else { try await tree.detail(post) }
                } }
            } else {
                Button("举报") { reportReason = ""; reportTarget = target }
                Button(anon ? "隐藏这条讨论" : "屏蔽昵称发言") { confirmation = TreeholeConfirmation(title: anon ? "隐藏这条讨论？" : "屏蔽此人的昵称发言？匿名内容不会关联屏蔽。") {
                    _ = try await tree.api.request("blocks.set", target.payload); tree.current = nil; screen = "feed"; try await tree.feed()
                } }
            }
        } label: { Image(systemName: "ellipsis").padding(10) }.accessibilityLabel("内容操作")
    }
    @ViewBuilder private func account(_ user: TreeholeMember) -> some View {
        if accountPage == "overview" {
            VStack(spacing: 12) {
                TreeholeAvatar(name: user.nickname, size: 66)
                Text(user.nickname).font(.title2.bold())
                Text("@" + user.username).font(.caption).foregroundStyle(.secondary)
                Text("用自己的昵称，留下校园里的回声。").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
            HStack(spacing: 0) {
                Button { accountFeed("mine") } label: { VStack(spacing: 10) { Image(systemName: "bubble.left").font(.title3); Text("我的帖子").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }
                Divider()
                Button { accountFeed("saved") } label: { VStack(spacing: 10) { Image(systemName: "bookmark").font(.title3); Text("我的收藏").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8) }
            }.fixedSize(horizontal: false, vertical: true).campusCard()
            VStack(spacing: 0) {
                settingsRow("修改昵称", symbol: "person.crop.circle") { accountPage = "profile" }
                Divider()
                settingsRow("账号安全", symbol: "lock.shield") { password = ""; newPassword = ""; accountPage = "password" }
                Divider()
                settingsRow("恢复已屏蔽的内容", symbol: "eye.slash") { confirmation = TreeholeConfirmation(title: "恢复所有已屏蔽的内容？") { _ = try await tree.api.request("blocks.clear"); tree.message = "已恢复屏蔽的内容" } }
                if user.role == "moderator" { Divider(); settingsRow("处理举报", symbol: "flag") { tree.perform { tree.reports = try await tree.api.request("admin.reports").reports ?? []; screen = "moderate" } } }
            }.campusCard()
            Button { confirmation = TreeholeConfirmation(title: "退出邯院通账号？") { _ = try await tree.api.request("logout"); tree.clear(); screen = "feed" } } label: { Label("退出邯院通账号", systemImage: "rectangle.portrait.and.arrow.right").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 6) }.campusCard()
            Button("注销邯院通账号") { password = ""; accountPage = "delete" }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                if accountPage == "profile" {
                    Text("其他同学会看到这个昵称。").font(.subheadline).foregroundStyle(.secondary)
                    TextField("公开昵称", text: $nickname).textContentType(.nickname)
                    Button("保存昵称") { tree.perform { tree.user = try await tree.api.request("profile.update", ["nickname": nickname]).user; accountPage = "overview" } }.buttonStyle(.borderedProminent).disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                } else if accountPage == "password" {
                    Text("修改后其他设备会退出登录，并生成新的恢复码。").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("当前密码", text: $password).textContentType(.password)
                    SecureField("新密码 · 至少 10 位", text: $newPassword).textContentType(.newPassword)
                    Button("修改密码") { tree.perform { let r = try await tree.api.request("password.change", ["password": password, "newPassword": newPassword]); password = ""; newPassword = ""; tree.recovery = r.recoveryCode; accountPage = "overview" } }.buttonStyle(.borderedProminent).disabled(password.isEmpty || newPassword.count < 10)
                } else {
                    Text("注销会删除你的帖子、评论和登录状态。学校课表保留。请输入当前密码确认身份。").font(.subheadline).foregroundStyle(.secondary)
                    SecureField("当前密码", text: $password).textContentType(.password)
                    Button("注销邯院通账号", role: .destructive) { confirmation = TreeholeConfirmation(title: "注销账号并删除全部社区内容？") { _ = try await tree.api.request("account.delete", ["password": password]); password = ""; tree.clear(); screen = "feed" } }.buttonStyle(.bordered).disabled(password.isEmpty)
                }
            }.textFieldStyle(.roundedBorder).campusCard()
        }
    }
    private func settingsRow(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 12) { Image(systemName: symbol).frame(width: 22).foregroundStyle(CampusTheme.muted); Text(label).foregroundStyle(CampusTheme.text); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }.font(.subheadline).padding(.vertical, 14) }.buttonStyle(.plain)
    }
    private func accountFeed(_ scope: String) { tree.scope = scope; tree.query = ""; searchOpen = false; screen = "feed"; reloadFeed() }
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
                        Button(label) { confirmation = TreeholeConfirmation(title: "确认\(label)？") { _ = try await tree.api.request("admin.resolve", ["reportId": report.id, "decision": decision, "reason": report.reason]); tree.reports = try await tree.api.request("admin.reports").reports ?? [] } }
                    } }.font(.caption)
                }.campusCard()
            }
        }
    }
    private func open(_ post: TreeholePost) { tree.perform { try await tree.detail(post); replyText = ""; replyTo = nil; replyAnonymous = false; commentRequest = UUID().uuidString; screen = "detail" } }
    private func back() {
        replyFocused = false
        if screen == "account" && accountPage != "overview" { accountPage = "overview"; password = ""; newPassword = ""; return }
        if screen == "moderate" { screen = "account"; return }
        if (screen == "compose" && !bodyText.isEmpty) || (screen == "detail" && !replyText.isEmpty) { discard = true; return }
        screen = "feed"; password = ""; newPassword = ""; tree.perform { try await tree.feed() }
    }
    static let rules = "尊重同学，勿发布他人隐私、辱骂、骚扰、垃圾广告或违法内容。可以举报、删除自己的内容和注销账号。匿名会对其他用户隐藏昵称与账号，后台保留账号关联用于处理举报；不同帖子使用不同匿名代号，同一帖子内的匿名发言可关联。请留意文字本身是否暴露身份。账号服务保存登录账号、昵称、密码加密摘要、帖子、互动与举报记录，用于登录及社区服务。教务账号与课表不会上传到社区。可以在账号设置中注销。"
}
// Derive presentation only from the public alias, never an account identifier.
private struct TreeholeAvatar: View {
    let name: String
    var anonymous = false
    var size: CGFloat = 42
    private var tone: Color {
        let palette = ["green", "blue", "purple", "orange"]
        let index = name.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return CampusTheme.course(palette[index])
    }
    var body: some View {
        Group {
            if anonymous { Image(systemName: "theatermasks").font(.system(size: size * 0.43, weight: .medium)) }
            else { Text(String(name.prefix(1))).font(.system(size: size * 0.43, weight: .medium)) }
        }.foregroundStyle(tone).frame(width: size, height: size).background(tone.opacity(0.13), in: RoundedRectangle(cornerRadius: anonymous ? size / 2 : size * 0.34)).accessibilityHidden(true)
    }
}
private struct TreeholeTarget: Identifiable {
    let postId: String; let commentId: String?
    var id: String { postId + (commentId ?? "") }
    var payload: [String: Any] { var value: [String: Any] = ["postId": postId]; if let commentId { value["commentId"] = commentId }; return value }
}
private struct TreeholeConfirmation { let title: String; let action: @MainActor () async throws -> Void }
