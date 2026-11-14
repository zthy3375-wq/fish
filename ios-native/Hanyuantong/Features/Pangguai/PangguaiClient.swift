import Foundation

protocol PangguaiRequesting {
    @MainActor func request(_ path: String, fields: [String: String], token: String) async throws -> PGJSON
}

/// One ephemeral task per request, no cookies/cache, redirects rejected before credentials leave the origin.
final class PangguaiClient: PangguaiRequesting {
    @MainActor func request(_ path: String, fields: [String: String] = [:], token: String = "") async throws -> PGJSON {
        let request = try Self.makeRequest(path, fields: fields, token: token)
        let loader = PGBoundedLoader()
        let bytes = try await loader.load(request)
        return try PangguaiProtocol.payload(JSONDecoder().decode(PGJSON.self, from: bytes))
    }
    static func makeRequest(_ path: String, fields: [String: String], token: String, timestamp: String = String(Int64(Date().timeIntervalSince1970 * 1000))) throws -> URLRequest {
        guard PangguaiProtocol.paths.contains(path), fields.count <= 30, token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              fields.allSatisfy({ $0.key.count < 64 && $0.value.utf8.count <= 32768 }),
              let url = URL(string: "https://userapi.qiekj.com/" + path) else { throw PGFailure.format }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.httpMethod = "POST"; r.httpShouldHandleCookies = false
        r.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        r.setValue(PangguaiProtocol.version, forHTTPHeaderField: "Version")
        r.setValue(PangguaiProtocol.channel, forHTTPHeaderField: "channel")
        r.setValue(timestamp, forHTTPHeaderField: "timestamp")
        r.setValue("Apple", forHTTPHeaderField: "phoneBrand")
        r.setValue("Hanyuantong/1.2.1 iOS", forHTTPHeaderField: "User-Agent")
        var values = fields
        if !token.isEmpty {
            r.setValue(token, forHTTPHeaderField: "token"); r.setValue(token, forHTTPHeaderField: "Authorization")
            r.setValue(try PangguaiProtocol.signature(path: path, token: token, timestamp: timestamp), forHTTPHeaderField: "sign")
            values["token"] = token
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        r.httpBody = Data(values.sorted(by: { $0.key < $1.key }).map { k, v in
            (k.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
        return r
    }
}

private final class PGBoundedLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var cancelled = false
    private var done = false
    func load(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { c in
                lock.lock()
                guard !cancelled else { lock.unlock(); c.resume(throwing: CancellationError()); return }
                continuation = c
                let config = URLSessionConfiguration.ephemeral
                config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil; config.urlCredentialStorage = nil
                config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
                let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                session = s; let t = s.dataTask(with: request); task = t
                lock.unlock(); t.resume()
            }
        }, onCancel: { self.cancel() })
    }
    private func cancel() { lock.lock(); cancelled = true; let t = task; lock.unlock(); t?.cancel(); finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock(); guard !done else { lock.unlock(); return }; done = true
        let c = continuation; continuation = nil; let s = session; session = nil; task = nil; lock.unlock()
        s?.invalidateAndCancel(); c?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(PGFailure.network))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let r = response as? HTTPURLResponse, r.url?.scheme == "https", r.url?.host == "userapi.qiekj.com", r.expectedContentLength <= 1_048_576 else {
            completionHandler(.cancel); finish(.failure(PGFailure.format)); return
        }
        let failure: PGFailure? = r.statusCode == 401 ? .auth : [403,429].contains(r.statusCode) ? .verify : !(200...299).contains(r.statusCode) ? .network : nil
        guard failure == nil else { completionHandler(.cancel); finish(.failure(failure!)); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !done, data.count + chunk.count <= 1_048_576 else { lock.unlock(); finish(.failure(PGFailure.format)); return }
        data.append(chunk); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let bytes = data; lock.unlock()
        if let error { finish(.failure(error)) } else { finish(.success(bytes)) }
    }
}
