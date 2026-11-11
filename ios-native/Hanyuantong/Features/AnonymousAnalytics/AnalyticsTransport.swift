import Foundation

@MainActor protocol AnalyticsTransporting {
    func send(_ request: URLRequest) async throws -> AnalyticsResponse
}

/// No shared cookies, URL cache, stored credentials, redirects, or response/body logging.
@MainActor final class AnalyticsHTTPTransport: AnalyticsTransporting {
    private let protocolClasses: [AnyClass]?
    init(protocolClasses: [AnyClass]? = nil) { self.protocolClasses = protocolClasses }
    func send(_ request: URLRequest) async throws -> AnalyticsResponse {
        guard let url = request.url, AnalyticsContract.action(for: url) != nil,
              request.httpMethod == "POST" else { throw AnalyticsFailure.invalid }
        return try await AnalyticsBoundedRequest(protocolClasses: protocolClasses).run(request)
    }
}

private final class AnalyticsBoundedRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let protocolClasses: [AnyClass]?
    private var continuation: CheckedContinuation<AnalyticsResponse, Error>?
    private var session: URLSession?
    private var bytes = Data()
    private var status: Int?
    private var expectedURL: URL?
    private var cancelled = false
    private var finished = false
    init(protocolClasses: [AnyClass]?) { self.protocolClasses = protocolClasses }
    func run(_ request: URLRequest) async throws -> AnalyticsResponse {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation; expectedURL = request.url
                let config = URLSessionConfiguration.ephemeral
                config.httpCookieStorage = nil; config.httpShouldSetCookies = false
                config.urlCache = nil; config.urlCredentialStorage = nil
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
                if let protocolClasses { config.protocolClasses = protocolClasses }
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: request)
                lock.unlock(); task.resume()
            }
        }, onCancel: { self.cancel() })
    }
    private func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<AnalyticsResponse, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation; self.continuation = nil
        let session = self.session; self.session = nil
        lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(AnalyticsFailure.redirect))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.url?.absoluteString == expectedURL?.absoluteString,
              response.expectedContentLength <= 4096 else {
            completionHandler(.cancel); finish(.failure(AnalyticsFailure.oversized)); return
        }
        lock.lock(); status = response.statusCode; lock.unlock()
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard bytes.count + data.count <= 4096 else { lock.unlock(); finish(.failure(AnalyticsFailure.oversized)); return }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let bytes = bytes, status = status; lock.unlock()
        if let error { finish(.failure(error)); return }
        struct Reply: Decodable { let ok: Bool? }
        guard let status, let reply = try? JSONDecoder().decode(Reply.self, from: bytes) else {
            // Non-Boolean ok and non-JSON responses are never accepted.
            finish(.failure(AnalyticsFailure.response)); return
        }
        finish(.success(AnalyticsResponse(status: status, ok: reply.ok == true)))
    }
}
