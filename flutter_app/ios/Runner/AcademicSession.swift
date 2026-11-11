import Flutter
import UIKit
import WebKit
import Security

/// Native-only school authentication. There is deliberately no WKScriptMessageHandler.
/// Channel registration belongs to AppDelegate: org.handancampus.flutter/academic.
final class AcademicSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let origin = "https://jwgl.hdc.edu.cn"
    private static let loginURL = URL(string: origin + "/xtgl/login_slogin.html")!
    private static let homeURL = URL(string: origin + "/xtgl/index_initMenu.html")!
    private weak var presenter: FlutterViewController?
    private var web: WKWebView?
    private var screen: UIViewController?
    private var pending: FlutterResult?
    private var generation = 0
    private var interactive = false
    private var started = false
    private var scope: String?
    private var term: [String: String] = [:]
    private var rendered: [String: Any]?
    private var script = ""
    private var reader = ""
    private var timeout: DispatchWorkItem?
    private var captchaShown = false
    private var renderedPolling = false
    private var finishing = false
    private let vault = AcademicKeychain()

    init(controller: FlutterViewController) {
        presenter = controller
        super.init()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handle(call, result: result) }
            return
        }
        switch call.method {
        case "logout":
            cancel()
            guard vault.clear() else {
                // Dart logout intentionally has no payload: failure must cross as a platform error.
                result(FlutterError(code: "STORAGE", message: "无法清除学校会话，请稍后重试", details: nil))
                return
            }
            scope = nil
            result(["session": "disconnected"])
        case "login", "getTimetable":
            if call.method == "getTimetable", pending != nil {
                result(response(["session": "error", "code": "BUSY"]))
                return
            }
            cancel()
            interactive = call.method == "login"
            // A new interactive login never inherits the previous account's cookies.
            if interactive {
                guard vault.clear() else { result(response(["session": "unknown", "code": "STORAGE"])); return }
                scope = nil
            }
            pending = result
            started = false
            finishing = false
            captchaShown = false
            renderedPolling = false
            term = [:]
            if let args = call.arguments as? [String: Any], args["xnm"] != nil || args["xqm"] != nil {
                guard let year = args["xnm"] as? String, let code = args["xqm"] as? String,
                      validTerm(year, code) else { fail("TERM"); return }
                term = ["xnm": year, "xqm": code]
            }
            let token = generation
            let deadline = DispatchWorkItem { [weak self] in
                guard let self = self, self.generation == token else { return }
                self.fail("NETWORK")
            }
            timeout = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + (interactive ? 300 : 90), execute: deadline)
            prepare(token)
        default: result(FlutterMethodNotImplemented)
        }
    }

    func dispose() { cancel() }

    private func validTerm(_ year: String, _ code: String) -> Bool {
        year.range(of: "^20[0-9]{2}$", options: .regularExpression) != nil && ["3", "12"].contains(code)
    }
    private static func allowed(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return url.scheme == "https" && url.host == "jwgl.hdc.edu.cn" &&
            url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    private func current(_ token: Int) -> Bool { generation == token && pending != nil }
    private func later(_ token: Int, seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.current(token) == true { work() }
        }
    }
    private func asset(_ name: String) throws -> String {
        let key = FlutterDartProject.lookupKey(forAsset: "assets/" + name)
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else { throw AcademicFailure.asset }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func prepare(_ token: Int) {
        do { script = try asset("handan-academic.js"); reader = try asset("handan-rendered-reader.js") }
        catch { fail("NATIVE"); return }
        // Applies to subresources as well as navigations. No external host, HTTP or alternate port.
        let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https://jwgl\\.hdc\\.edu\\.cn(:443)?/"},"action":{"type":"ignore-previous-rules"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "school-origin-only-v1", encodedContentRuleList: rules) { [weak self] rule, error in
            DispatchQueue.main.async {
                guard let self = self, self.current(token) else { return }
                guard error == nil, let rule = rule else { self.fail("NATIVE"); return }
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.preferences.javaScriptCanOpenWindowsAutomatically = false
                config.userContentController.add(rule)
                let web = WKWebView(frame: .zero, configuration: config)
                if #available(iOS 16.4, *) { web.isInspectable = false }
                web.navigationDelegate = self
                web.uiDelegate = self
                self.web = web
                // Keep rendering attached even during background read, without exposing school content.
                web.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
                web.alpha = 0.01
                web.isUserInteractionEnabled = false
                web.accessibilityElementsHidden = true
                self.presenter?.view.addSubview(web)
                if self.interactive {
                    self.showOfficialPage(captcha: false)
                    web.load(URLRequest(url: Self.loginURL))
                } else {
                    guard let saved = self.vault.restore() else {
                        self.finish(["session": "expired"]); return
                    }
                    self.scope = saved.scope
                    let group = DispatchGroup()
                    for cookie in saved.cookies.compactMap({ $0.cookie }) {
                        group.enter()
                        web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
                    }
                    group.notify(queue: .main) { [weak self, weak web] in
                        guard let self = self, self.current(token) else { return }
                        web?.load(URLRequest(url: Self.homeURL))
                    }
                }
            }
        }
    }

    private func showOfficialPage(captcha: Bool) {
        guard screen == nil, let web = web, let presenter = presenter,
              presenter.presentedViewController == nil else { return }
        let page = UIViewController()
        page.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = captcha ? "请在学校官方页面完成验证码，再点查询\njwgl.hdc.edu.cn" : "邯郸学院官方登录\njwgl.hdc.edu.cn"
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 14)
        let button = UIButton(type: .system)
        button.setTitle("取消", for: .normal)
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let bar = UIStackView(arrangedSubviews: [button, label])
        bar.spacing = 16
        bar.translatesAutoresizingMaskIntoConstraints = false
        page.view.addSubview(bar)
        web.removeFromSuperview()
        web.alpha = 1
        web.isUserInteractionEnabled = true
        web.accessibilityElementsHidden = false
        web.translatesAutoresizingMaskIntoConstraints = false
        page.view.addSubview(web)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: page.view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: page.view.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: page.view.trailingAnchor, constant: -16),
            bar.heightAnchor.constraint(equalToConstant: 64),
            web.topAnchor.constraint(equalTo: bar.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: page.view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: page.view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: page.view.safeAreaLayoutGuide.bottomAnchor)
        ])
        page.modalPresentationStyle = .fullScreen
        page.isModalInPresentation = true
        screen = page
        presenter.present(page, animated: true)
    }
    private func hideOfficialPage() {
        guard let web = web else { return }
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = true
        web.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        presenter?.view.addSubview(web)
        screen?.dismiss(animated: false)
        screen = nil
    }
    @objc private func cancelTapped() { fail("CANCELLED") }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.allowed(navigationAction.request.url) ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let accepted = Self.allowed(navigationResponse.response.url)
        decisionHandler(accepted ? .allow : .cancel)
        if accepted, navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 { fail("HTTP") }
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default platform TLS trust evaluation, never trust a certificate manually.
        completionHandler(.performDefaultHandling, nil)
    }
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    private func navigationFailed(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail("NETWORK") }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("NATIVE") }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard pending != nil, Self.allowed(webView.url) else { return }
        let path = webView.url?.path ?? ""
        if path.contains("/xtgl/login") || path.contains("/cas/") || path.contains("/auth/") {
            if !interactive || started { finish(["session": "expired"]) }
            return
        }
        if rendered != nil {
            guard !renderedPolling else { return }
            renderedPolling = true
            let click = "(function(){const b=document.querySelector('#search_go');if(b&&!document.querySelector('#kbgrid_table_0 .timetable_con')&&!['1','3'].includes(document.querySelector('#sfxyyzm')?.value))b.click();})()"
            evaluate(click, token: generation) { [weak self] _, _ in
                guard let self = self else { return }
                self.readRendered(0, token: self.generation)
            }
        } else if !started { checkAuthenticated(0, token: generation) }
    }
    private func evaluate(_ source: String, token: Int, completion: @escaping (Any?, Error?) -> Void) {
        web?.evaluateJavaScript(source) { [weak self] value, error in
            guard self?.current(token) == true else { return }
            completion(value, error)
        }
    }
    private func checkAuthenticated(_ attempt: Int, token: Int) {
        guard current(token), !started else { return }
        let source = "!!document.querySelector('#menu,#navbar_container,#yhxm,#xnm,[data-gnmkdm],a[onclick*=clickMenu],a[href*=login_logout]')&&!document.querySelector('input[type=password]')"
        evaluate(source, token: token) { [weak self] value, error in
            guard let self = self, !self.started else { return }
            if error == nil, value as? Bool == true {
                self.started = true
                if self.interactive {
                    self.scope = UUID().uuidString
                    self.hideOfficialPage()
                }
                self.saveSession(token) { success in
                    guard success else { self.fail("STORAGE"); return }
                    self.execute(token)
                }
            } else if attempt < 30 {
                self.later(token, seconds: 0.3) { self.checkAuthenticated(attempt + 1, token: token) }
            } else { self.fail("SCHEMA") }
        }
    }
    private func execute(_ token: Int) {
        guard let data = try? JSONSerialization.data(withJSONObject: term),
              let json = String(data: data, encoding: .utf8) else { fail("TERM"); return }
        evaluate("window.__handanResult=null;(\(script))('timetable',\(json));void 0;", token: token) { [weak self] _, error in
            guard let self = self else { return }
            if error != nil { self.fail("SCHEMA") } else { self.poll(token) }
        }
    }
    private func poll(_ token: Int) {
        evaluate("window.__handanResult == null ? null : JSON.stringify(window.__handanResult)", token: token) { [weak self] value, error in
            guard let self = self else { return }
            if error != nil { self.fail("SCHEMA"); return }
            guard let value = value as? String else {
                self.later(token, seconds: 0.25) { self.poll(token) }; return
            }
            guard let result = self.decode(value, limit: 700000) else { self.fail("SCHEMA"); return }
            if result["session"] as? String == "expired" { self.finish(["session": "expired"]); return }
            if let fallback = result["renderedPage"] as? [String: Any] {
                guard let route = fallback["url"] as? String,
                      let url = URL(string: route, relativeTo: Self.homeURL)?.absoluteURL,
                      Self.allowed(url),
                      url.path.range(of: "^/kbcx/xskbcx_cx(?:Xsgrkb(?:Index)?|XskbcxIndex)\\.html$", options: .regularExpression) != nil else {
                    self.fail("SCHEMA"); return
                }
                self.rendered = result
                self.web?.load(URLRequest(url: url))
            } else { self.finish(result) }
        }
    }
    private func decode(_ value: String, limit: Int) -> [String: Any]? {
        guard value.utf8.count <= limit, let data = value.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    private func readRendered(_ attempt: Int, token: Int) {
        guard current(token), rendered != nil else { return }
        evaluate("JSON.stringify({captcha:['1','3'].includes(document.querySelector('#sfxyyzm')?.value),password:!!document.querySelector('input[type=password]')})", token: token) { [weak self] value, _ in
            guard let self = self else { return }
            if let text = value as? String, let state = self.decode(text, limit: 1000) {
                if state["password"] as? Bool == true { self.finish(["session": "expired"]); return }
                if state["captcha"] as? Bool == true, !self.captchaShown {
                    self.captchaShown = true
                    self.showOfficialPage(captcha: true)
                }
            }
            self.evaluate("(\(self.reader))()", token: token) { [weak self] value, _ in
                guard let self = self, var result = self.rendered else { return }
                guard let text = value as? String, let payload = self.decode(text, limit: 400000),
                      let observation = payload["observation"] as? [String: Any],
                      let rows = payload["kbList"] as? [[String: Any]] else { self.fail("SCHEMA"); return }
                let year = observation["termYear"] as? String ?? ""
                let code = observation["termCode"] as? String ?? ""
                let practice = payload["practice"] as? [[String: Any]] ?? []
                var module: [String: Any]?
                if (!rows.isEmpty || !practice.isEmpty), rows.count <= 500, practice.count <= 500,
                   observation["invalidCount"] as? Int == 0,
                   observation["specialArrangements"] as? Bool != true, observation["frameLimit"] as? Bool != true,
                   self.validTerm(year, code) {
                    let source = (result["renderedPage"] as? [String: Any])?["term"] as? [String: String]
                    if source?["xnm"] != year || source?["xqm"] != code {
                        module = ["status": "error", "code": "TERM"]
                    } else {
                        module = ["status": "ok", "data": ["term": ["xnm": year, "xqm": code],
                            "kbList": rows, "practice": practice]]
                    }
                } else if attempt < (self.captchaShown ? 110 : 30) {
                    self.later(token, seconds: 0.7) { self.readRendered(attempt + 1, token: token) }
                    return
                } else { module = ["status": "error", "code": self.captchaShown ? "CAPTCHA" : "LIVE_EMPTY"] }
                var modules = result["modules"] as? [String: Any] ?? [:]
                modules["timetable"] = module
                result["modules"] = modules
                result.removeValue(forKey: "renderedPage")
                self.finish(result)
            }
        }
    }
    private func saveSession(_ token: Int, completion: @escaping (Bool) -> Void) {
        guard let web = web, let scope = scope else { completion(false); return }
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self, self.current(token) else { return }
            completion(self.vault.save(scope: scope, cookies: cookies))
        }
    }
    private func response(_ value: [String: Any]) -> [String: Any] {
        var value = value
        if let scope = scope { value["sessionScope"] = scope }
        return value
    }
    private func finish(_ value: [String: Any]) {
        guard pending != nil, !finishing else { return }
        if value["session"] as? String == "valid", scope != nil {
            finishing = true
            saveSession(generation) { [weak self] success in
                guard let self = self else { return }
                self.finishing = false
                self.deliver(success ? value : ["session": "unknown", "code": "STORAGE",
                    "modules": ["timetable": ["status": "error", "code": "STORAGE"]]])
            }
        } else { deliver(value) }
    }
    private func deliver(_ value: [String: Any]) {
        guard let reply = pending else { return }
        let output = response(value)
        pending = nil
        cleanup()
        reply(output)
    }
    private func fail(_ code: String) { deliver(["session": "unknown", "code": code, "modules": ["timetable": ["status": "error", "code": code]]]) }
    private func cancel() { if pending != nil { fail("CANCELLED") } else { cleanup() } }
    private func cleanup() {
        generation += 1
        timeout?.cancel(); timeout = nil
        rendered = nil
        finishing = false
        web?.navigationDelegate = nil
        web?.uiDelegate = nil
        web?.stopLoading()
        web?.removeFromSuperview()
        web = nil
        screen?.dismiss(animated: false)
        screen = nil
    }
}

private enum AcademicFailure: Error { case asset }

/// Cookie values (including HttpOnly) never leave native code; Keychain is device-only.
private final class AcademicKeychain {
    struct Cookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let httpOnly: Bool
        let expires: Date?
        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
            secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly; expires = cookie.expiresDate
        }
        var cookie: HTTPCookie? {
            guard ["jwgl.hdc.edu.cn", ".jwgl.hdc.edu.cn", "hdc.edu.cn", ".hdc.edu.cn"].contains(domain),
                  expires.map({ $0 > Date() }) ?? true else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path,
                .secure: secure ? "TRUE" : "FALSE"]
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let expires = expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }
    }
    struct Session: Codable { let scope: String; let cookies: [Cookie] }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.handancampus.flutter.academic.session.v1", kSecAttrAccount as String: "school"] }
    func save(scope: String, cookies: [HTTPCookie]) -> Bool {
        let accepted = cookies.filter { ["jwgl.hdc.edu.cn", ".jwgl.hdc.edu.cn", "hdc.edu.cn", ".hdc.edu.cn"].contains($0.domain) }
        guard !accepted.isEmpty, let data = try? JSONEncoder().encode(Session(scope: scope, cookies: accepted.map(Cookie.init))), data.count <= 65536 else { return false }
        let attrs: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
    func restore() -> Session? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count <= 65536,
              let session = try? JSONDecoder().decode(Session.self, from: data),
              UUID(uuidString: session.scope) != nil, !session.cookies.compactMap({ $0.cookie }).isEmpty else { return nil }
        return session
    }
    func clear() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
