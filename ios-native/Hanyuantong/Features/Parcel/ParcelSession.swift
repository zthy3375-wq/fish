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
    @Published private(set) var isSuspended = false
    private var showingIdentity: Bool?
    private var canReloadCurrentPage = false
    private var currentNavigation: WKNavigation?
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
            view.isHidden = isSuspended
            web = view
            open(identity: identity)
        } catch { status = ParcelFailure.unavailable.localizedDescription }
    }
    func open(identity: Bool) {
        guard let web, !closed, !(isLoading && showingIdentity == identity) else { return }
        showingIdentity = identity
        markLoading()
        let url = identity ? provider.identityURL : provider.parcelURL
        watch(web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)))
    }
    func refresh() {
        guard let web, !closed, !isLoading, !isSuspended else { return }
        guard canReloadCurrentPage, ParcelPolicy.allowed(web.url, provider: provider) else {
            open(identity: showingIdentity ?? false)
            return
        }
        markLoading()
        watch(web.reload())
    }
    func setForeground(_ active: Bool) {
        let suspended = !active
        guard !closed, isSuspended != suspended else { return }
        isSuspended = suspended
        web?.isHidden = suspended
        if !active && isReading {
            stopRead()
            status = "已暂停读取，返回后可继续操作官方页面。"
        }
    }
    private func markLoading() {
        stopRead()
        generation += 1
        canRead = false
        canReloadCurrentPage = false
        isLoading = true
        status = "正在打开官方页面…"
    }
    private func watch(_ navigation: WKNavigation?) {
        currentNavigation = navigation
        navigationDeadline?.cancel()
        navigationDeadline = nil
        guard navigation != nil else {
            isLoading = false
            status = ParcelFailure.unavailable.localizedDescription
            return
        }
        let ticket = generation
        navigationDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard let self, self.generation == ticket, !self.closed else { return }
            self.stop()
            self.status = ParcelFailure.timeout.localizedDescription
        }
    }
    func stop() {
        guard !closed else { return }
        stopRead(); generation += 1; navigationDeadline?.cancel(); navigationDeadline = nil
        currentNavigation = nil
        canReloadCurrentPage = false
        web?.stopLoading(); isLoading = false; canRead = false
        status = "已停止。本次未读取完成，可重新打开待取包裹页。"
    }
    func close() {
        guard !closed else { return }
        closed = true; generation += 1
        currentNavigation = nil
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
        guard !isSuspended, !isReading, !isLoading, !closed, let web,
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
                guard !Task.isCancelled, !self.closed, self.generation == ticket else { return }
                if let failure = error as? ParcelFailure, failure == .login || failure == .account { self.invalidateAccount() }
                self.status = (error as? ParcelFailure ?? .unrecognized).localizedDescription
            }
            guard !Task.isCancelled, !self.closed, self.generation == ticket else { return }
            self.isReading = false; self.readDeadline?.cancel(); self.readDeadline = nil; self.readTask = nil
        }
    }
    private func check(_ ticket: Int) throws {
        try Task.checkCancellation()
        guard !closed, generation == ticket else { throw ParcelFailure.cancelled }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !closed, ParcelPolicy.allowed(navigationAction.request.url, provider: provider) else {
            decisionHandler(.cancel)
            if !closed && navigationAction.targetFrame?.isMainFrame != false {
                stop()
                status = ParcelFailure.origin.localizedDescription
            }
            return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated {
                markLoading()
                watch(webView.load(navigationAction.request))
            }
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let mime = navigationResponse.response.mimeType?.lowercased()
        let allowed = !closed && ParcelPolicy.allowed(navigationResponse.response.url, provider: provider)
            && navigationResponse.canShowMIMEType && (mime == "text/html" || mime == "application/xhtml+xml")
            && (http.map { (200..<400).contains($0.statusCode) } ?? true)
        if allowed { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if navigationResponse.isForMainFrame && isLoading && !closed {
            if http?.statusCode == 401 { invalidateAccount() }
            stop()
            status = http?.statusCode == 401 ? ParcelFailure.login.localizedDescription :
                http?.statusCode == 403 ? ParcelFailure.verification.localizedDescription : ParcelFailure.unavailable.localizedDescription
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !closed, let navigation else { return }
        if currentNavigation !== navigation {
            markLoading()
            watch(navigation)
        }
        status = "请在官方页面操作；密码和验证码只输入此页。"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed, let navigation, currentNavigation === navigation else { return }
        navigationDeadline?.cancel(); navigationDeadline = nil; currentNavigation = nil
        isLoading = false
        canReloadCurrentPage = true
        canRead = ParcelPolicy.readable(webView.url, provider: provider)
        if ParcelPolicy.verificationPage(webView.url) {
            status = ParcelFailure.verification.localizedDescription
        } else if ParcelPolicy.authPage(webView.url) {
            if knownAccount != nil { invalidateAccount() }
            status = "请在官方页面登录，完成后再打开待取包裹。"
        } else {
            status = canRead ? "看到待取包裹后，点“读取当前页取件码”。" : "可在此查看官方页面，或切换至待取包裹。"
        }
        guard canRead else { return }
        let ticket = generation
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard !self.closed, ticket == self.generation, let known = self.knownAccount,
                  let current = try? ParcelPolicy.account(cookies, provider: self.provider) else { return }
            if current != known { self.invalidateAccount() }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(navigation, error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(navigation, error) }
    private func failed(_ navigation: WKNavigation?, _ error: Error) {
        guard !closed, let navigation, currentNavigation === navigation else { return }
        stop()
        status = (error as NSError).code == NSURLErrorCancelled
            ? ParcelFailure.cancelled.localizedDescription : ParcelFailure.unavailable.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { stop(); status = ParcelFailure.unavailable.localizedDescription }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default system TLS validation only. No invalid-certificate acceptance or app-supplied credentials.
        completionHandler(.performDefaultHandling, nil)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}
