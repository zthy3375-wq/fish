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
                    HStack {
                        if screen != "feed" { Button { back() } label: { Label("返回树洞", systemImage: "chevron.left") } }
                        else { Label("校园里的小小回声", systemImage: "leaf").foregroundStyle(.secondary) }
                        Spacer()
                        if screen == "feed" { Button(user.nickname) { nickname = user.nickname; password = ""; newPassword = ""; screen = "account" } }
                    }.font(.caption)
                    switch screen {
                    case "compose": composer
                    case "detail": if let post = tree.current { discussion(post) }
                    case "account": account(user)
                    case "moderate": moderation
                    default: feed
                    }
                }
            }.padding(20).frame(maxWidth: 680).disabled(tree.busy)
        }
        .background(CampusTheme.background).navigationTitle("树洞").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(tree.busy || screen != "feed")
        .toolbar { if screen != "feed" { ToolbarItem(placement: .navigationBarLeading) { Button("返回") { back() }.disabled(tree.busy) } } }
        .task { tree.enter() }
        .onChange(of: tree.user?.id) { identity in if identity == nil { auth = "login" }; bodyText = ""; replyText = ""; password = ""; newPassword = ""; replyTo = nil; screen = "feed" }
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
            Image(systemName: "leaf.circle.fill").font(.system(size: 42)).foregroundStyle(.green)
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
        }.textFieldStyle(.roundedBorder).campusCard()
    }
    private var feed: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading) { Text("邯院树洞").font(.title2.bold()); Text("分享日常，也听听彼此。").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { bodyText = ""; anonymous = false; postRequest = UUID().uuidString; screen = "compose" } label: { Label("发帖", systemImage: "plus") }.buttonStyle(.borderedProminent) }
            Picker("帖子筛选", selection: $tree.scope) { Text("最新").tag("all"); Text("我的帖子").tag("mine"); Text("收藏").tag("saved") }.pickerStyle(.segmented).onChange(of: tree.scope) { _ in tree.perform { try await tree.feed() } }
            HStack { TextField("搜索树洞里的文字", text: $tree.query).textFieldStyle(.roundedBorder).onSubmit { tree.perform { try await tree.feed() } }; Button("搜索") { tree.perform { try await tree.feed() } }; Button { tree.perform { try await tree.feed() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新树洞") }
            if tree.posts.isEmpty && !tree.busy && tree.message == nil { CampusEmpty(title: "这里还很安静", detail: tree.query.isEmpty ? "从一句想说的话开始。" : "换个关键词试试", symbol: "bubble.left.and.bubble.right") }
            ForEach(tree.posts) { post in
                VStack(alignment: .leading, spacing: 12) {
                    author(post.author, date: post.createdAt)
                    Button { open(post) } label: { Text(post.body).lineLimit(5).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading) }.buttonStyle(.plain)
                    actions(post)
                }.campusCard()
            }
            if tree.feedNext != nil { Button("加载更多") { tree.perform { try await tree.feed(more: true) } }.frame(maxWidth: .infinity) }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发一条树洞").font(.title2.bold())
            TextEditor(text: $bodyText).frame(minHeight: 210).accessibilityLabel("想说的话").onChange(of: bodyText) { bodyText = String($0.prefix(3000)) }
            Text("\(bodyText.count) / 3000").font(.caption).foregroundStyle(.secondary)
            Toggle("匿名发布", isOn: $anonymous)
            Text("发布身份：" + (anonymous ? "匿名同学" : tree.user?.nickname ?? "")).font(.subheadline.bold())
            Text(anonymous ? "其他同学看不到你的昵称和账号。本帖内匿名回复使用同一代号。发布后身份方式固定。" : "帖子显示你的邯院通昵称。发布后身份方式固定。").font(.caption).foregroundStyle(.secondary)
            Button(anonymous ? "匿名发布" : "以昵称发布") {
                tree.perform {
                    let r = try await tree.api.request("posts.create", ["body": bodyText, "anonymous": anonymous, "requestId": postRequest])
                    bodyText = ""; postRequest = UUID().uuidString
                    if let post = r.post { tree.posts.insert(post, at: 0); try await tree.detail(post); screen = "detail" }
                }
            }.buttonStyle(.borderedProminent).disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.campusCard()
    }
    @ViewBuilder private func discussion(_ post: TreeholePost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { author(post.author, date: post.createdAt); Spacer(); contentMenu(post) }
            Text(post.body).textSelection(.enabled); actions(post)
        }.campusCard()
        Text("聊一聊 · \(post.commentCount)").font(.headline)
        if tree.comments.isEmpty { Text("还没有评论。").font(.caption).foregroundStyle(.secondary) }
        ForEach(tree.comments) { comment in
            VStack(alignment: .leading, spacing: 10) {
                HStack { author(comment.author, date: comment.createdAt); if comment.isOriginalPoster { Text("楼主").font(.caption).foregroundStyle(.green) }; Spacer(); if !comment.deleted { contentMenu(post, comment: comment) } }
                if comment.replyTo != nil { Text("回复了一条评论").font(.caption).foregroundStyle(.secondary) }
                Text(comment.body).textSelection(.enabled)
                if !comment.deleted && !post.locked { Button("回复") { replyTo = comment }.font(.caption) }
            }.campusCard()
        }
        if tree.commentNext != nil { Button("加载更多评论") { tree.perform { try await tree.detail(post, more: true) } } }
        if post.locked { Text("这条讨论已暂停回复。").foregroundStyle(.secondary) }
        else {
            VStack(alignment: .leading, spacing: 12) {
                if let replyTo { HStack { Text("回复 \(replyTo.author.name)").font(.caption); Spacer(); Button("取消") { self.replyTo = nil } } }
                TextEditor(text: $replyText).frame(minHeight: 90).accessibilityLabel("你的回复").onChange(of: replyText) { replyText = String($0.prefix(1000)) }
                Toggle(forceAnonymous ? "保持楼主匿名身份" : "匿名回复", isOn: Binding(get: { replyAnonymous || forceAnonymous }, set: { replyAnonymous = $0 })).disabled(forceAnonymous)
                Text(replyAnonymous || forceAnonymous ? "匿名同学 · 本帖内代号保持一致" : "以 \(tree.user?.nickname ?? "") 的昵称回复").font(.caption).foregroundStyle(.secondary)
                Button("发布回复") {
                    tree.perform {
                        _ = try await tree.api.request("comments.create", ["postId": post.id, "body": replyText, "anonymous": replyAnonymous || forceAnonymous, "requestId": commentRequest, "replyTo": replyTo?.id as Any? ?? NSNull()])
                        replyText = ""; replyTo = nil; commentRequest = UUID().uuidString; try await tree.detail(post)
                    }
                }.buttonStyle(.borderedProminent).disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.campusCard()
        }
    }
    private func author(_ author: TreeholeAuthor, date: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: author.anonymous ? "leaf.circle.fill" : "person.crop.circle.fill").font(.title2).foregroundStyle(author.anonymous ? Color.green : CampusTheme.primary)
            VStack(alignment: .leading, spacing: 3) { Text(author.name + (author.mine ? " · 我" : "")).font(.subheadline.weight(.semibold)); Text(TreeholePresentation.date(date)).font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func actions(_ post: TreeholePost) -> some View {
        HStack {
            Button { tree.react(post, kind: "like") } label: { Label("\(post.likeCount)", systemImage: post.liked ? "heart.fill" : "heart") }
            Spacer(); Button { open(post) } label: { Label("\(post.commentCount)", systemImage: "bubble.right") }
            Spacer(); Button { tree.react(post, kind: "save") } label: { Label(post.saved ? "已收藏" : "收藏", systemImage: post.saved ? "bookmark.fill" : "bookmark") }
        }.font(.caption).padding(.top, 6)
    }
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
    private func account(_ user: TreeholeMember) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("邯院通账号").font(.title2.bold()); Text("登录账号：\(user.username)")
            Text("公开昵称与学校资料分别管理。").font(.caption).foregroundStyle(.secondary)
            TextField("公开昵称", text: $nickname).textContentType(.nickname)
            Button("保存昵称") { tree.perform { tree.user = try await tree.api.request("profile.update", ["nickname": nickname]).user } }
            Divider(); SecureField("当前密码", text: $password).textContentType(.password); SecureField("新密码 · 至少 10 位", text: $newPassword).textContentType(.newPassword)
            Button("修改密码") { tree.perform { let r = try await tree.api.request("password.change", ["password": password, "newPassword": newPassword]); password = ""; newPassword = ""; tree.recovery = r.recoveryCode; tree.message = "密码已更新，其他设备已退出" } }.disabled(password.isEmpty || newPassword.count < 10)
            Divider()
            if user.role == "moderator" { Button("处理举报") { tree.perform { tree.reports = try await tree.api.request("admin.reports").reports ?? []; screen = "moderate" } } }
            Button("恢复已屏蔽的内容") { tree.perform { _ = try await tree.api.request("blocks.clear"); tree.message = "已恢复屏蔽的内容" } }
            Button("退出邯院通账号") { confirmation = TreeholeConfirmation(title: "退出邯院通账号？") { _ = try await tree.api.request("logout"); tree.clear(); screen = "feed" } }
            Button("注销邯院通账号", role: .destructive) { confirmation = TreeholeConfirmation(title: "注销后将删除你的帖子、评论和登录状态。学校课表保留。确认注销？") { _ = try await tree.api.request("account.delete", ["password": password]); password = ""; tree.clear(); screen = "feed" } }.disabled(password.isEmpty)
            Text("注销账号需先填写当前密码。").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder).campusCard()
    }
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
        if (screen == "compose" && !bodyText.isEmpty) || (screen == "detail" && !replyText.isEmpty) { discard = true; return }
        screen = "feed"; password = ""; newPassword = ""; tree.perform { try await tree.feed() }
    }
    static let rules = "尊重同学，勿发布他人隐私、辱骂、骚扰、垃圾广告或违法内容。可以举报、删除自己的内容和注销账号。匿名会对其他用户隐藏昵称与账号，后台保留账号关联用于处理举报；不同帖子使用不同匿名代号，同一帖子内的匿名发言可关联。请留意文字本身是否暴露身份。账号服务保存登录账号、昵称、密码加密摘要、帖子、互动与举报记录，用于登录及社区服务。教务账号与课表不会上传到社区。可以在账号设置中注销。"
}
private struct TreeholeTarget: Identifiable {
    let postId: String; let commentId: String?
    var id: String { postId + (commentId ?? "") }
    var payload: [String: Any] { var value: [String: Any] = ["postId": postId]; if let commentId { value["commentId"] = commentId }; return value }
}
private struct TreeholeConfirmation { let title: String; let action: @MainActor () async throws -> Void }
