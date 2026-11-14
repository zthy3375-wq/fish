import Foundation

protocol QuzhiTransport {
    func request(path: String, values: [String: String], post: Bool) async throws -> Data
}

/// TLS remains the system default. Redirects, shared cookies, URL caching and automatic retries are disabled.
final class QuzhiClient: NSObject, QuzhiTransport, URLSessionTaskDelegate {
    static func allowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "v3-api.china-qzxy.cn" &&
            (url.port == nil || url.port == 443) && url.user == nil && url.password == nil &&
            url.fragment == nil && QuzhiProtocol.paths.contains(String(url.path.dropFirst()))
    }
    static func form(_ values: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed)! }
        return values.keys.sorted().map { encode($0) + "=" + encode(values[$0]!) }.joined(separator: "&")
    }
    static func makeRequest(path: String, values: [String: String], post: Bool) throws -> URLRequest {
        guard QuzhiProtocol.paths.contains(path) else { throw QuzhiFailure.request }
        // Only the two known authentication methods are POST operations.
        guard post == ["user/login", "user/registerAndLogin"].contains(path) else { throw QuzhiFailure.request }
        let body = form(values)
        guard let url = URL(string: QuzhiProtocol.base.absoluteString + path + (post ? "" : "?" + body)), allowed(url) else { throw QuzhiFailure.request }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = post ? "POST" : "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Hanyuantong/1.0 iOS", forHTTPHeaderField: "User-Agent")
        if post {
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    func request(path: String, values: [String: String], post: Bool = false) async throws -> Data {
        let request = try Self.makeRequest(path: path, values: values, post: post)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, Self.allowed(response.url) else { throw QuzhiFailure.request }
            if response.statusCode == 401 { throw QuzhiFailure.auth }
            if [403, 429].contains(response.statusCode) { throw QuzhiFailure.verify }
            guard (200...299).contains(response.statusCode) else { throw QuzhiFailure.network }
            guard response.expectedContentLength <= Int64(QuzhiProtocol.responseLimit) else { throw QuzhiFailure.format }
            var result = Data(); result.reserveCapacity(4096)
            for try await byte in bytes {
                if result.count % 4096 == 0 { try Task.checkCancellation() }
                guard result.count < QuzhiProtocol.responseLimit else { throw QuzhiFailure.format }
                result.append(byte)
            }
            try Task.checkCancellation()
            return result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw QuzhiFailure.classify(error)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
