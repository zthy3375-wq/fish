import Foundation
import UIKit
import WebKit
import Security
import CryptoKit

/// A native-only connector. Official remote pages never receive an app message bridge.
/// Cookies live in an ephemeral WebKit store and the device-only Keychain, never UserDefaults.
@MainActor
final class LearningSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private weak var presenter: UIViewController?
    private var web: WKWebView?
    private var screen: UIViewController?
    private var parser: WKWebView?
    private var cookies: [HTTPCookie] = []
    private let vault = LearningSessionVault()
    private var restored = false
    private var generation = 0
    private var lastRequest: Date?
    private var activeRead: LearningHTTPRead?
    private var pageReply: CheckedContinuation<Void, Error>?
    private var pageTask: Task<Void, Never>?
    private var loginMode = false
    private var probing = false
    private var proof: LearningVerification?
    private var expectedAccount: String?
    private var pageMessage: UILabel?
    private var verifiedCourses: CourseList?

    struct CourseList { let account: String; let courses: [LearningCourse]; let complete: Bool }
    func attachPresenter(_ controller: UIViewController) { if screen == nil { presenter = controller } }
    func savedAccount() throws -> String? { try vault.restore()?.account }
    func restore() throws {
        guard !restored else { return }
        if let saved = try vault.restore() {
            cookies = saved.cookies.compactMap(\.cookie)
            proof = saved.verification
            expectedAccount = saved.account
        }
        restored = true
    }
    func account() throws -> String {
        let ids = Set(cookies.filter { Self.cookie($0, matches: LearningPolicy.homeURL) && $0.name == "_uid" }.map(\.value))
        guard ids.count == 1, let id = ids.first, LearningPolicy.numeric(id) else { throw LearningError(code: "AUTH") }
        return SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24).description
    }
    private func check(_ token: Int) throws {
        try Task.checkCancellation()
        guard token == generation else { throw LearningError(code: "CANCELLED") }
    }
    private func checkAccount() throws {
        if let expectedAccount, try account() != expectedAccount { throw LearningError(code: "ACCOUNT_CHANGED") }
    }
    private func save() throws {
        try vault.save(account: account(), cookies: cookies, verification: proof)
    }
    func login() async throws -> CourseList {
        try restore()
        let previous = try? account()
        let start = previous == expectedAccount ? (proof?.show ?? LearningPolicy.loginURL) : LearningPolicy.loginURL
        verifiedCourses = nil
        try await showPage(start, login: true)
        guard let result = verifiedCourses, try account() == result.account else { throw LearningError(code: "AUTH") }
        verifiedCourses = nil
        expectedAccount = result.account
        proof = nil
        try save()
        return result
    }
    /// Explicit user navigation only. No answer submission, marking read or activity playback is automated.
    func open(_ url: URL) async throws {
        try restore(); try checkAccount()
        guard LearningPolicy.allowed(url) else { throw LearningError(code: "URL") }
        try await showPage(url, login: false)
        try checkAccount(); try save()
    }
    func cancel() {
        generation += 1
        activeRead?.cancel(); activeRead = nil
        pageTask?.cancel(); pageTask = nil
        finishPage(.failure(LearningError(code: "CANCELLED")))
        parser?.stopLoading(); parser = nil
    }
    func logout() throws {
        cancel()
        try vault.clear()
        cookies = []; expectedAccount = nil; proof = nil; restored = true
    }

    private static func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
        guard let host = url.host, LearningPolicy.allowed(url), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = cookie.domain.hasPrefix(".") ? (host == domain || host.hasSuffix("." + domain)) : host == domain
        let path = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        return domainMatches && (path == cookiePath || path.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/"))
    }
    private func merge(_ incoming: [HTTPCookie]) throws {
        for cookie in incoming {
            guard LearningSessionVault.Cookie(cookie).allowed else { continue }
            cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if cookie.expiresDate.map({ $0 > Date() }) ?? true { cookies.append(cookie) }
        }
        guard cookies.count <= 256 else { throw LearningError(code: "LIMIT") }
    }
    private func read(_ start: URL, form: [String: String]? = nil, referer: URL = LearningPolicy.homeURL) async throws -> LearningPage {
        try restore()
        guard LearningPolicy.safeRead(start) else { throw LearningError(code: "URL") }
        let token = generation
        var url = start, post = form
        for _ in 0..<7 {
            try check(token); try checkAccount()
            guard LearningPolicy.safeRead(url) else { throw LearningError(code: "URL") }
            if let lastRequest {
                let delay = 1.2 - Date().timeIntervalSince(lastRequest)
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }
            try check(token)
            lastRequest = Date()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue(LearningPolicy.allowed(referer) ? referer.absoluteString : LearningPolicy.homeURL.absoluteString, forHTTPHeaderField: "Referer")
            let accepted = cookies.filter { Self.cookie($0, matches: url) }
            if !accepted.isEmpty { request.setValue(HTTPCookie.requestHeaderFields(with: accepted)["Cookie"], forHTTPHeaderField: "Cookie") }
            if let post {
                guard url == LearningPolicy.noticesURL || url.absoluteString == "https://mooc1-1.chaoxing.com/visit/courselistdata" else { throw LearningError(code: "METHOD") }
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                var components = URLComponents(); components.queryItems = post.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
                request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            }
            let read = LearningHTTPRead()
            activeRead = read
            let (data, response) = try await read.run(request)
            activeRead = nil
            try check(token)
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in result[String(describing: pair.key)] = String(describing: pair.value) }
            try merge(HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)); try checkAccount()
            if (300..<400).contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"), let next = URL(string: location, relativeTo: url)?.absoluteURL, LearningPolicy.allowed(next) else { throw LearningError(code: "URL") }
                if LearningPolicy.loginPage(next) { throw LearningError(code: "AUTH") }
                if next.absoluteString.lowercased().contains("antispider") { try remember(show: next, read: start, form: form, referer: referer); throw LearningError(code: "VERIFY") }
                url = next; post = nil; continue
            }
            if response.statusCode == 401 { throw LearningError(code: "AUTH") }
            if response.statusCode == 429 { throw LearningError(code: "RATE_LIMIT") }
            guard (200..<300).contains(response.statusCode), let body = String(data: data, encoding: .utf8) else { throw LearningError(code: "HTTP_\(response.statusCode)") }
            let page = LearningPage(url: url, body: body)
            let state: LearningNavigation = try await parse("navigation", page: page)
            if response.statusCode == 202 || state.challenge { try remember(show: url, read: start, form: form, referer: referer); throw LearningError(code: "VERIFY") }
            if state.auth { throw LearningError(code: "AUTH") }
            return page
        }
        throw LearningError(code: "REDIRECT")
    }
    private func remember(show: URL, read: URL, form: [String: String]?, referer: URL) throws {
        proof = LearningVerification(show: show, read: read, form: form, referer: referer)
        try save()
    }
    func fetchCourses() async throws -> CourseList {
        try restore()
        let key = try account()
        var page: LearningPage?
        do { page = try await read(LearningPolicy.coursesURL) }
        catch let error as LearningError { if ["AUTH", "ACCOUNT_CHANGED", "VERIFY", "RATE_LIMIT", "CANCELLED"].contains(error.code) { throw error } }
        if let page, let result = try LearningHTML.coursesJSON(page.body) {
            guard try account() == key else { throw LearningError(code: "ACCOUNT_CHANGED") }
            try save()
            return CourseList(account: key, courses: result.courses, complete: result.complete)
        }
        let base = try await read(LearningPolicy.homeURL)
        let navigation: LearningNavigation = try await parse("navigation", page: base)
        let fallback: LearningPage
        if let fid = navigation.fid, LearningPolicy.numeric(fid) {
            let target = LearningPolicy.params("https://mooc2-ans.chaoxing.com/mooc2-ans/visit/courselistdata", values: ["courseType": "1", "courseFid": fid, "courseTeacherid": "0", "courseOrderBy": "0"])
            fallback = try await read(target)
        } else {
            fallback = try await read(URL(string: "https://mooc1-1.chaoxing.com/visit/courselistdata")!, form: ["courseType": "1", "courseFolderId": "0", "courseFolderSize": "-1", "digest": "_all"])
        }
        let parsed: LearningParsedCourses = try await parse("coursesResult", page: fallback)
        let list = parsed.courses
        let nav: LearningNavigation = try await parse("navigation", page: fallback)
        guard !list.isEmpty || nav.emptyCourses else { throw LearningError(code: "COURSES_SCHEMA") }
        guard try account() == key else { throw LearningError(code: "ACCOUNT_CHANGED") }
        try save()
        return CourseList(account: key, courses: list, complete: parsed.complete)
    }
    func courseWork(_ course: LearningCourse) async throws -> LearningParsedWork {
        let token = generation
        var queue: [(URL, URL)] = [(URL(string: course.url)!, LearningPolicy.homeURL)]
        var seen = Set<URL>(), first: LearningPage?
        while !queue.isEmpty && seen.count < 4 {
            let (url, referer) = queue.removeFirst()
            guard seen.insert(url).inserted else { continue }
            let page = try await read(url, referer: referer)
            let nav: LearningNavigation = try await parse("navigation", page: page, course: course)
            if nav.accessDenied { throw LearningError(code: "WORK_ACCESS") }
            if LearningPolicy.workList(page.url) { first = page; break }
            var target = nav.menu ?? nav.workFrame
            if target == nil, !nav.workEnc.isEmpty {
                target = LearningPolicy.params("https://mooc1.chaoxing.com/mooc2/work/list", values: ["courseId": course.courseId, "classId": course.classId, "cpi": course.cpi, "ut": "s", "enc": nav.workEnc, "openc": nav.openc, "stuenc": nav.stuenc, "isdisplaytable": "2"]).absoluteString
            }
            if let target, let destination = URL(string: target), LearningPolicy.safeRead(destination), LearningPolicy.sameCourse(destination, course: course) { first = try await read(destination, referer: page.url); break }
            for frame in nav.courseFrames {
                if let target = URL(string: frame), LearningPolicy.safeRead(target), LearningPolicy.sameCourse(target, course: course), !seen.contains(target) { queue.append((target, page.url)) }
            }
        }
        guard var page = first else { throw LearningError(code: "WORK_ENC") }
        var records: [String: LearningItem] = [:], visited = Set<URL>(), rejected = 0, complete = false
        do {
        for index in 0..<15 {
            try check(token)
            guard visited.insert(page.url).inserted else { break }
            var frames = Set([page.url])
            for _ in 0..<3 {
                let nav: LearningNavigation = try await parse("navigation", page: page, course: course)
                if nav.accessDenied { throw LearningPartialFailure(code: "WORK_ACCESS", items: Array(records.values)) }
                guard let frame = nav.workFrame, let target = URL(string: frame), frames.insert(target).inserted else { break }
                page = try await read(target, referer: page.url)
            }
            let parsed: LearningParsedWork = try await parse("work", page: page, course: course)
            guard parsed.recognized else { throw LearningPartialFailure(code: "WORK_SCHEMA", items: Array(records.values)) }
            rejected += parsed.rejected
            let added = parsed.records.filter { records[$0.id] == nil }.count
            for item in parsed.records { records[item.id] = item }
            guard records.count <= 1000 else { throw LearningPartialFailure(code: "LIMIT", items: Array(records.values.prefix(1000))) }
            complete = rejected == 0 && parsed.nextURL == nil && (parsed.complete || parsed.total == records.count)
            guard let next = parsed.nextURL, let target = URL(string: next), LearningPolicy.safeRead(target), LearningPolicy.sameCourse(target, course: course), target.path == page.url.path, (added > 0 || index == 0) else { break }
            do { page = try await read(target, referer: page.url) }
            catch { throw LearningPartialFailure(code: (error as? LearningError)?.code ?? (error is CancellationError ? "CANCELLED" : "NETWORK"), items: Array(records.values)) }
        }
        } catch let error as LearningPartialFailure { throw error }
        catch { throw LearningPartialFailure(code: (error as? LearningError)?.code ?? (error is CancellationError ? "CANCELLED" : "NETWORK"), items: Array(records.values)) }
        try checkAccount(); try save()
        return LearningParsedWork(records: Array(records.values), recognized: true, complete: complete, rejected: rejected, nextURL: nil, total: nil)
    }
    func exams() async throws -> LearningParsedWork {
        let page = try await read(LearningPolicy.examsURL)
        let result: LearningParsedWork = try await parse("exams", page: page)
        guard result.recognized else { throw LearningError(code: "EXAMS_SCHEMA") }
        try checkAccount(); try save(); return result
    }
    func notices() async throws -> [LearningNotice] {
        let page = try await read(LearningPolicy.noticesURL, form: ["type": "0", "notice_type": "0", "lastValue": "", "sort": "0", "folderUUID": "", "kw": ""])
        let notices = try LearningHTML.noticesJSON(page.body)
        try checkAccount(); try save(); return notices
    }
    private func parse<T: Decodable>(_ operation: String, page: LearningPage, course: LearningCourse? = nil) async throws -> T {
        let token = generation
        try check(token)
        guard page.body.utf8.count <= 1_500_000 else { throw LearningError(code: "LIMIT") }
        if parser == nil {
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            let rule = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "learning-inert-parser-v1", encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#)
            try check(token)
            guard let rule else { throw LearningError(code: "NATIVE") }
            config.userContentController.add(rule)
            parser = WKWebView(frame: .zero, configuration: config)
        }
        guard let parser else { throw LearningError(code: "NATIVE") }
        try check(token)
        let courseObject: Any = try course.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        let raw = try await parser.callAsyncJavaScript(LearningHTML.script, arguments: ["operation": operation, "html": page.body, "baseURL": page.url.absoluteString, "course": courseObject, "item": NSNull()], in: nil, contentWorld: .defaultClient)
        try check(token)
        guard let string = raw as? String, string.utf8.count <= 2_000_000, let data = string.data(using: .utf8) else { throw LearningError(code: "SCHEMA") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func showPage(_ url: URL, login: Bool) async throws {
        guard LearningPolicy.allowed(url), pageReply == nil, let presenter, presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { throw LearningError(code: "PRESENTATION") }
        let token = generation
        let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https://([a-zA-Z0-9-]+\\.)*chaoxing\\.com(:443)?/"},"action":{"type":"ignore-previous-rules"}}]"#
        guard let rule = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "learning-official-https-v1", encodedContentRuleList: rules) else { throw LearningError(code: "NATIVE") }
        try check(token)
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(rule)
        let view = WKWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) { view.isInspectable = false }
        view.navigationDelegate = self; view.uiDelegate = self
        for cookie in cookies { await config.websiteDataStore.httpCookieStore.setCookie(cookie) }
        try check(token)
        web = view; loginMode = login; probing = false
        let controller = UIViewController(); controller.view.backgroundColor = .systemBackground
        let close = UIButton(type: .system); close.setTitle(login ? "取消" : "返回并刷新", for: .normal); close.addTarget(self, action: #selector(closePage), for: .touchUpInside)
        let label = UILabel(); label.text = "学习通官方页面\nchaoxing.com"; label.numberOfLines = 2; label.font = .systemFont(ofSize: 12); pageMessage = label
        let bar = UIStackView(arrangedSubviews: [close, label]); bar.axis = .horizontal; bar.spacing = 12; bar.distribution = .fill
        if login { let button = UIButton(type: .system); button.setTitle("登录/验证后继续", for: .normal); button.titleLabel?.font = .systemFont(ofSize: 13); button.addTarget(self, action: #selector(continueLogin), for: .touchUpInside); bar.addArrangedSubview(button) }
        for child in [bar, view] { child.translatesAutoresizingMaskIntoConstraints = false; controller.view.addSubview(child) }
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -12), bar.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor), bar.heightAnchor.constraint(equalToConstant: 58), view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor), view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor), view.topAnchor.constraint(equalTo: bar.bottomAnchor), view.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor)])
        controller.modalPresentationStyle = .fullScreen; controller.isModalInPresentation = true; screen = controller
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pageReply = continuation
                presenter.present(controller, animated: true)
                var request = URLRequest(url: url)
                if let proof, login { request.setValue(proof.referer.absoluteString, forHTTPHeaderField: "Referer") }
                view.load(request)
                pageTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                    guard let self, token == self.generation else { return }
                    self.finishPage(.failure(LearningError(code: "TIMEOUT")))
                }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.finishPage(.failure(LearningError(code: "CANCELLED"))) } })
    }
    @objc private func closePage() {
        if loginMode { finishPage(.failure(LearningError(code: "CANCELLED"))); return }
        let token = generation
        Task { [weak self] in
            guard let self, let web = self.web else { return }
            let current = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard self.generation == token, self.pageReply != nil else { return }
            do { self.cookies = []; try self.merge(current); try self.checkAccount(); try self.save(); self.finishPage(.success(())) }
            catch { self.finishPage(.failure(error)) }
        }
    }
    @objc private func continueLogin() {
        guard !probing, let web else { return }
        probing = true
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                let current = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
                try self.check(token)
                self.cookies = []; try self.merge(current)
                let key = try self.account()
                let same = self.expectedAccount == key
                self.expectedAccount = key
                if !same { self.proof = nil }
                if let proof = self.proof { _ = try await self.read(proof.read, form: proof.form, referer: proof.referer) }
                self.verifiedCourses = try await self.fetchCourses()
                try self.check(token); self.proof = nil; try self.save()
                self.finishPage(.success(()))
            } catch {
                guard token == self.generation, self.pageReply != nil else { return }
                self.probing = false
                let code = (error as? LearningError)?.code ?? "NETWORK"
                if ["AUTH", "VERIFY", "RATE_LIMIT"].contains(code) {
                    self.pageMessage?.text = code == "AUTH" ? "请先完成官方登录" : "请在官方页面完成验证\n再点顶部继续"
                    if code == "VERIFY", let proof = self.proof, let web = self.web {
                        do { try await self.copyCookies(to: web, token: token) }
                        catch { if token == self.generation { self.finishPage(.failure(error)) }; return }
                        guard token == self.generation, self.pageReply != nil else { return }
                        if web.url != proof.show {
                            var request = URLRequest(url: proof.show)
                            request.setValue(proof.referer.absoluteString, forHTTPHeaderField: "Referer")
                            web.load(request)
                        }
                    }
                } else { self.finishPage(.failure(error)) }
            }
        }
    }
    private func copyCookies(to web: WKWebView, token: Int) async throws {
        let store = web.configuration.websiteDataStore.httpCookieStore
        let existing = await store.allCookies()
        try check(token)
        for cookie in existing {
            if !cookies.contains(where: { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }) {
                await store.deleteCookie(cookie); try check(token)
            }
        }
        for cookie in cookies { await store.setCookie(cookie); try check(token) }
    }
    private func finishPage(_ result: Result<Void, Error>) {
        guard let reply = pageReply else { return }
        pageReply = nil; generation += 1; activeRead?.cancel(); activeRead = nil; pageTask?.cancel(); pageTask = nil
        web?.stopLoading(); web?.navigationDelegate = nil; web?.uiDelegate = nil; web?.removeFromSuperview(); web = nil
        screen?.dismiss(animated: false); screen = nil; pageMessage = nil; probing = false
        reply.resume(with: result)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) { decisionHandler(LearningPolicy.allowed(navigationAction.request.url) ? .allow : .cancel) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { decisionHandler(LearningPolicy.allowed(navigationResponse.response.url) ? .allow : .cancel) }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(.performDefaultHandling, nil) }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finishPage(.failure(LearningError(code: "NATIVE"))) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { finishPage(.failure(LearningError(code: "NETWORK"))) } }
}

struct LearningPartialFailure: Error { let code: String; let items: [LearningItem] }
private struct LearningVerification: Codable { let show: URL; let read: URL; let form: [String: String]?; let referer: URL }

private final class LearningSessionVault {
    struct Cookie: Codable {
        let name: String; let value: String; let domain: String; let path: String; let secure: Bool; let httpOnly: Bool; let expires: Date?
        init(_ cookie: HTTPCookie) { name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly; expires = cookie.expiresDate }
        var allowed: Bool {
            let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return (host == "chaoxing.com" || host.hasSuffix(".chaoxing.com")) && name.count <= 256 && value.utf8.count <= 8192 && path.hasPrefix("/") && path.count <= 2048
        }
        var cookie: HTTPCookie? {
            guard allowed, expires.map({ $0 > Date() }) ?? true else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: secure ? "TRUE" : "FALSE"]
            if let expires { properties[.expires] = expires }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }
    struct Record: Codable { let account: String; let cookies: [Cookie]; let verification: LearningVerification? }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.handancampus.ios.learning.session.v1", kSecAttrAccount as String: "chaoxing", kSecAttrSynchronizable as String: false] }
    func restore() throws -> Record? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 200_000, let record = try? JSONDecoder().decode(Record.self, from: data), record.account.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil, record.cookies.count <= 256 else { throw LearningError(code: "STORAGE") }
        if let proof = record.verification { guard LearningPolicy.allowed(proof.show), LearningPolicy.safeRead(proof.read), LearningPolicy.allowed(proof.referer) else { throw LearningError(code: "STORAGE") } }
        return record
    }
    func save(account: String, cookies: [HTTPCookie], verification: LearningVerification?) throws {
        let data = try JSONEncoder().encode(Record(account: account, cookies: cookies.map(Cookie.init).filter(\.allowed), verification: verification))
        guard data.count <= 200_000 else { throw LearningError(code: "LIMIT") }
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound, SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw LearningError(code: "STORAGE") }
    }
    func clear() throws { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw LearningError(code: "STORAGE") } }
}

/// Per-request bounded streaming, no shared CookieStorage, cache or credentials, and no automatic redirects.
private final class LearningHTTPRead: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var reply: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var data = Data()
    private var response: HTTPURLResponse?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    func run(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                reply = continuation
                let config = URLSessionConfiguration.ephemeral
                config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil; config.urlCredentialStorage = nil
                config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
                self.session = session; let task = session.dataTask(with: request); self.task = task
                lock.unlock(); task.resume()
            }
        }, onCancel: { self.cancel() })
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock(); finish(.failure(CancellationError())) }
    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock(); let pending = reply; reply = nil; let current = session; session = nil; task = nil; lock.unlock()
        current?.invalidateAndCancel(); pending?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, LearningPolicy.allowed(http.url), response.expectedContentLength <= 1_500_000 else { completionHandler(.cancel); finish(.failure(LearningError(code: "LIMIT"))); return }
        self.response = http; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= 1_500_000 else { finish(.failure(LearningError(code: "LIMIT"))); return }
        self.data.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if let response { finish(.success((data, response))) }
        else { finish(.failure(LearningError(code: "NETWORK"))) }
    }
}
