import Foundation
import Combine
import UIKit
import WebKit

/// Visible official browser, isolated per platform. There is no app JavaScript message handler.
/// Authentication is manual; only the explicit Read button performs a one-shot DOM observation.
@MainActor
final class ParcelSession: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let provider: ParcelProvider
    @Published private(set) var web: WKWebView?
    @Published private(set) var status = "正在打开官方页面…"
    @Published private(set) var isLoading = false
    @Published private(set) var isReading = false
    @Published private(set) var canRead = false
    private var generation = 0
    private var closed = false
    private var knownAccount: String?
    private var invalidationReported = false
    private var navigationDeadline: Task<Void, Never>?
    private var readDeadline: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var received: ((ParcelReadBatch, String, [HTTPCookie]) throws -> Void)?
    private var invalidated: (() -> Void)?
    init(provider: ParcelProvider, account: String?,
         received: @escaping (ParcelReadBatch, String, [HTTPCookie]) throws -> Void,
         invalidated: @escaping () -> Void) {
        self.provider = provider; knownAccount = account; self.received = received; self.invalidated = invalidated
    }
    func prepare(cookies: [HTTPCookie], identity: Bool) async {
        guard !closed, web == nil else { return }
        let ticket = generation
        do {
            // Disallow insecure requests, media and local resources. The official HTTPS page owns its own subresources.
            let rules = #"[{"trigger":{"url-filter":"^http:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^(file|ftp):"},"action":{"type":"block"}},{"trigger":{"url-filter":".*","resource-type":["media"]},"action":{"type":"block"}}]"#
            let compiled = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "parcel-https-v1", encodedContentRuleList: rules)
            guard !closed, generation == ticket, let compiled else { return }
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            config.allowsInlineMediaPlayback = false
            config.mediaTypesRequiringUserActionForPlayback = .all
            config.userContentController.add(compiled)
            for cookie in cookies where ParcelPolicy.cookieAllowed(cookie, provider: provider) {
                await config.websiteDataStore.httpCookieStore.setCookie(cookie)
                guard !closed, generation == ticket else { return }
            }
            let view = WKWebView(frame: .zero, configuration: config)
            if #available(iOS 16.4, *) { view.isInspectable = false }
            view.navigationDelegate = self; view.uiDelegate = self
            view.allowsLinkPreview = false; view.isOpaque = true; view.backgroundColor = .white
            web = view
            open(identity: identity)
        } catch { status = ParcelFailure.unavailable.localizedDescription }
    }
    func open(identity: Bool) {
        guard let web, !closed else { return }
        stopRead()
        generation += 1; canRead = false
        web.load(URLRequest(url: identity ? provider.identityURL : provider.parcelURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }
    func refresh() {
        guard let web, !closed, ParcelPolicy.allowed(web.url, provider: provider) else { return }
        stopRead(); generation += 1; canRead = false; web.reload()
    }
    func stop() {
        guard !closed else { return }
        stopRead(); generation += 1; navigationDeadline?.cancel(); navigationDeadline = nil
        web?.stopLoading(); isLoading = false; canRead = false
        status = "已停止。本次未读取完成，可重新打开待取包裹页。"
    }
    func close() {
        guard !closed else { return }
        closed = true; generation += 1
        stopRead(); navigationDeadline?.cancel(); navigationDeadline = nil
        web?.isHidden = true; web?.stopLoading()
        web?.navigationDelegate = nil; web?.uiDelegate = nil
        web?.configuration.userContentController.removeAllUserScripts()
        web = nil; received = nil; invalidated = nil
    }
    private func stopRead() {
        readTask?.cancel(); readTask = nil; readDeadline?.cancel(); readDeadline = nil; isReading = false
    }
    private func invalidateAccount() {
        knownAccount = nil
        guard !invalidationReported else { return }
        invalidationReported = true; invalidated?()
    }
    func readCurrent() {
        guard !isReading, !isLoading, !closed, let web,
              ParcelPolicy.readable(web.url, provider: provider) else { status = ParcelFailure.unrecognized.localizedDescription; return }
        let ticket = generation
        isReading = true; status = "正在读取当前官方待取页…"
        readDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self, self.generation == ticket, self.isReading, !self.closed else { return }
            self.generation += 1; self.stopRead(); self.status = ParcelFailure.timeout.localizedDescription
        }
        readTask = Task { [weak self, weak web] in
            guard let self, let web else { return }
            do {
                let before = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
                try self.check(ticket)
                let account = try ParcelPolicy.account(before, provider: self.provider)
                if let known = self.knownAccount, known != account { self.invalidateAccount() }
                let raw = try await web.callAsyncJavaScript(ParcelReader.script,
                    arguments: ["requestedProvider": self.provider.rawValue], in: nil, contentWorld: .defaultClient)
                try self.check(ticket)
                let after = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
                try self.check(ticket)
                guard account == (try ParcelPolicy.account(after, provider: self.provider)),
                      ParcelPolicy.readable(web.url, provider: self.provider) else { throw ParcelFailure.account }
                guard let raw = raw as? String else { throw ParcelFailure.unrecognized }
                let batch = try ParcelReadBatch.decode(raw, provider: self.provider)
                switch batch.phase {
                case .login: throw ParcelFailure.login
                case .verify: throw ParcelFailure.verification
                case .loading, .unrecognized: throw ParcelFailure.unrecognized
                case .partial, .empty: break
                }
                let cookies = after.filter { ParcelPolicy.cookieAllowed($0, provider: self.provider) }
                guard cookies.count <= 128 else { throw ParcelFailure.limit }
                try self.received?(batch, account, cookies)
                try self.check(ticket)
                self.knownAccount = account; self.invalidationReported = false
                self.status = batch.phase == .empty
                    ? "当前官方页面明确显示暂无待取；历史取件记录仍保留，未确认全量包裹状态。"
                    : "已读取当前页 \(batch.items.count) 个取件码。返回可查看原生卡片；未读取全部订单。"
            } catch {
                guard !self.closed, self.generation == ticket else { return }
                if let failure = error as? ParcelFailure, failure == .login || failure == .account { self.invalidateAccount() }
                self.status = (error as? ParcelFailure ?? .unrecognized).localizedDescription
            }
            guard !self.closed, self.generation == ticket else { return }
            self.isReading = false; self.readDeadline?.cancel(); self.readDeadline = nil; self.readTask = nil
        }
    }
    private func check(_ ticket: Int) throws {
        try Task.checkCancellation()
        guard !closed, generation == ticket else { throw ParcelFailure.cancelled }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !closed, ParcelPolicy.allowed(navigationAction.request.url, provider: provider) else {
            if navigationAction.targetFrame?.isMainFrame != false { status = "已拦截未核验的跳转。可关闭此页，使用固定官方 App / 系统入口。" }
            decisionHandler(.cancel); return
        }
        if navigationAction.targetFrame?.isMainFrame == true && ParcelPolicy.authPage(navigationAction.request.url) { invalidateAccount() }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { webView.load(navigationAction.request) }
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let mime = navigationResponse.response.mimeType?.lowercased()
        guard !closed, ParcelPolicy.allowed(navigationResponse.response.url, provider: provider),
              navigationResponse.canShowMIMEType, mime == "text/html" || mime == "application/xhtml+xml",
              http.map({ (200..<400).contains($0.statusCode) }) ?? true else {
            if http?.statusCode == 401 || http?.statusCode == 403 { invalidateAccount() }
            status = ParcelFailure.unavailable.localizedDescription
            isLoading = false; canRead = false; navigationDeadline?.cancel()
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        generation += 1; stopRead(); canRead = false; isLoading = true
        status = "请在官方页面操作；密码和验证码只输入此页。"
        navigationDeadline?.cancel()
        let ticket = generation
        navigationDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard let self, self.generation == ticket, !self.closed else { return }
            self.stop(); self.status = ParcelFailure.timeout.localizedDescription
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDeadline?.cancel(); navigationDeadline = nil; isLoading = false
        canRead = ParcelPolicy.readable(webView.url, provider: provider)
        status = canRead ? "登录完成并看到待取包裹后，点“读取取件码”。只读取当前页，不保证覆盖全部订单。" : "此处为官方页面。查看身份码无需读取；登录完成后可点“待取包裹”。"
        let ticket = generation
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard !self.closed, ticket == self.generation, let known = self.knownAccount else { return }
            if (try? ParcelPolicy.account(cookies, provider: self.provider)) != known { self.invalidateAccount() }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard !closed, (error as NSError).code != NSURLErrorCancelled else { return }
        stop(); status = ParcelFailure.unavailable.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { stop(); status = ParcelFailure.unavailable.localizedDescription }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default system TLS validation only. No invalid-certificate acceptance or app-supplied credentials.
        completionHandler(.performDefaultHandling, nil)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}
