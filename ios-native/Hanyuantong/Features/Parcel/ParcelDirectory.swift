#if DEBUG
import Foundation
import Combine

struct DirectoryParcel: Codable, Identifiable {
    let source: String
    let carrier: String
    let trackingNumber: String
    let state: Status
    let updatedAt: Int64
    let station: String?
    let pickupCode: String?
    var sources: [String]?

    enum Status: String, Codable {
        case unknown, inTransit = "in_transit", ready, pickedUp = "picked_up"
        var priority: Int { [Self.unknown, .inTransit, .ready, .pickedUp].firstIndex(of: self) ?? 0 }
    }

    var id: String { carrier + ":" + trackingNumber }

    func normalized() throws -> Self {
        let carrier = self.carrier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tracking = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.matches(carrier, pattern: "^[a-z0-9_-]{1,32}$"),
              Self.matches(tracking, pattern: "^[A-Z0-9-]{1,64}$"),
              Self.matches(source, pattern: "^[a-z0-9_-]{1,32}$"),
              (1...4_102_444_800_000).contains(updatedAt) else { throw ParcelDirectory.State.unavailable }
        return Self(source: source, carrier: carrier, trackingNumber: tracking, state: state, updatedAt: updatedAt,
                    station: try station.map { try ParcelDirectory.checked($0, limit: 160) },
                    pickupCode: try pickupCode.map { try ParcelDirectory.checked($0, limit: 64) }, sources: [source])
    }

    func preferred(over other: Self) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if state != other.state { return state.priority > other.state.priority }
        if (pickupCode != nil) != (other.pickupCode != nil) { return pickupCode != nil }
        if source != other.source { return source < other.source }
        if pickupCode != other.pickupCode { return (pickupCode ?? "") < (other.pickupCode ?? "") }
        return (station ?? "") < (other.station ?? "")
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        !value.isEmpty && value.range(of: pattern, options: [.regularExpression, .anchored]) == (value.startIndex..<value.endIndex)
    }
}

@MainActor final class ParcelDirectory: ObservableObject {
    enum State: Error, Equatable {
        case unconfigured, disconnected, pending, waiting, empty, ready, denied, expired, rejected
        case rateLimited, forbidden, incomplete, unavailable
    }
    struct Configuration {
        let origin: URL
        let client: String

        init?(origin: String, client: String) {
            guard let parts = URLComponents(string: origin), parts.scheme == "https",
                  let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.port == nil,
                  parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil,
                  client.range(of: #"^[A-Za-z0-9._-]{1,128}$"#, options: .regularExpression) == (client.startIndex..<client.endIndex),
                  let normalized = URL(string: "https://" + host) else { return nil }
            self.origin = normalized
            self.client = client
        }

        static var app: Self? {
            Self(origin: Bundle.main.object(forInfoDictionaryKey: "ParcelDirectoryOrigin") as? String ?? "",
                 client: Bundle.main.object(forInfoDictionaryKey: "ParcelDirectoryClient") as? String ?? "")
        }
    }
    struct Reply {
        let status: Int
        let data: Data
        let retryAfter: TimeInterval
    }
    private struct DeviceReply: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let verificationUriComplete: String?
        let expiresIn: Int
        let interval: Int?
    }
    private struct TokenReply: Decodable {
        let tokenType: String
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }
    private struct DeviceChallenge {
        let code: String
        let userCode: String
        let uri: URL
        let expiry: Date
        var next: Date
        var interval: TimeInterval
    }
    private struct Page: Decodable { let items: [DirectoryParcel]; let nextCursor: String? }
    private struct OAuthError: Decodable { let error: String }
    struct Snapshot: Codable {
        let items: [DirectoryParcel]
        let updatedAt: Date
    }
    private struct Account: Codable {
        let origin: URL
        let client: String
        let token: String
        let refreshToken: String?
        let expiresAt: Date
        var snapshot: Snapshot?
    }

    typealias Request = (URL, [String: String]?, String?) async throws -> Reply
    private let request: Request
    private let config: Configuration?
    private let load: () throws -> Data?
    private let save: (Data) throws -> Void
    private let clear: () throws -> Void
    private let now: () -> Date
    private var account: Account?
    private var challenge: DeviceChallenge?
    private var loaded = false
    private var lastAttempt = Date.distantPast
    private var retryAt = Date.distantPast
    @Published private(set) var state = State.disconnected
    @Published private(set) var busy = false

    init(config: Configuration?, load: @escaping () throws -> Data?, save: @escaping (Data) throws -> Void,
         clear: @escaping () throws -> Void, request: @escaping Request, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.load = load
        self.save = save
        self.clear = clear
        self.request = request
        self.now = now
        if config == nil { state = .unconfigured }
    }

    convenience init() {
        let key = "parcel-directory-v1"
        self.init(config: .app, load: { try ProtectedStorage().read(key, as: Data.self) },
                  save: { try ProtectedStorage().write($0, name: key) },
                  clear: { try ProtectedStorage().remove(key) }, request: DirectoryHTTP.send)
    }

    var snapshot: Snapshot? { account?.snapshot }
    var connected: Bool { account != nil }
    var userCode: String? { challenge?.userCode }
    var verificationURL: URL? {
        guard let challenge, now() < challenge.expiry else { return nil }
        return challenge.uri
    }

    func begin() async {
        await operation {
            guard let config, account == nil, (challenge?.expiry ?? .distantPast) <= now() else { return }
            let reply = try await send("/oauth/device/code", form: ["client_id": config.client, "scope": "parcels.read offline_access"])
            let device: DeviceReply = try decode(reply, oauth: true)
            guard let baseURI = verificationURL(device.verificationUri, origin: config.origin),
                  (1...3600).contains(device.expiresIn) else {
                throw State.unavailable
            }
            guard (1...3600).contains(device.interval ?? 5) else { throw State.unavailable }
            let interval = TimeInterval(max(5, device.interval ?? 5))
            let uri = device.verificationUriComplete.flatMap { verificationURL($0, origin: config.origin) } ?? baseURI
            challenge = DeviceChallenge(code: try Self.checked(device.deviceCode, limit: 4096),
                                        userCode: try Self.checked(device.userCode, limit: 64), uri: uri,
                                        expiry: now().addingTimeInterval(TimeInterval(device.expiresIn)),
                                        next: now().addingTimeInterval(interval), interval: interval)
        }
    }

    func poll() async {
        await operation {
            guard let config, var pending = challenge else { return }
            guard now() < pending.expiry else { challenge = nil; throw State.expired }
            guard now() >= retryAt else { throw State.rateLimited }
            guard now() >= pending.next else { return }
            pending.next = now().addingTimeInterval(pending.interval)
            challenge = pending
            let reply: Reply
            do {
                reply = try await send("/oauth/token", form: [
                    "client_id": config.client, "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": pending.code,
                ])
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                delayChallenge(pending)
                throw error
            }
            switch oauthError(reply) {
            case "authorization_pending": return
            case "slow_down":
                pending.interval += 5
                pending.next = now().addingTimeInterval(pending.interval)
                challenge = pending
                return
            case "access_denied", "expired_token":
                challenge = nil
                throw oauthError(reply) == "access_denied" ? State.denied : State.expired
            default: break
            }
            guard (200...299).contains(reply.status) else {
                if reply.status >= 500 { delayChallenge(pending) } else { challenge = nil }
                try checkStatus(reply)
                return
            }
            try updateToken(reply, previous: nil)
            challenge = nil
            try await sync(force: true)
        }
    }

    private func verificationURL(_ value: String, origin: URL) -> URL? {
        guard let clean = try? Self.checked(value, limit: 2048),
              let url = URL(string: clean), url.scheme == "https", url.host?.lowercased() == origin.host?.lowercased(),
              url.port == nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private func delayChallenge(_ pending: DeviceChallenge) {
        var delayed = pending
        delayed.interval = max(pending.interval, min(300, pending.interval * 2))
        delayed.next = now().addingTimeInterval(delayed.interval)
        challenge = delayed
    }

    func refresh(force: Bool = false) async { await operation { try await sync(force: force) } }

    func disconnect() async {
        await operation {
            try clear()
            challenge = nil
            account = nil
            lastAttempt = .distantPast
            retryAt = .distantPast
        }
    }

    private func operation(_ work: () async throws -> Void) async {
        guard config != nil, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if !loaded {
                if let data = try load() {
                    let stored = try JSONDecoder().decode(Account.self, from: data)
                    if stored.origin == config?.origin && stored.client == config?.client { account = stored }
                    else { try clear() }
                }
                loaded = true
            }
            try await work()
            if challenge != nil { state = .pending }
            else if let snapshot { state = snapshot.items.isEmpty ? .empty : .ready }
            else { state = connected ? .waiting : .disconnected }
        } catch let error as State {
            if connected && [.expired, .rejected, .forbidden].contains(error) {
                account = nil
                lastAttempt = .distantPast
                do { try clear() } catch { state = .unavailable; return }
            }
            state = error
        }
        catch is CancellationError { }
        catch { state = .unavailable }
    }

    private func sync(force: Bool) async throws {
        guard let current = account else { return }
        guard now() >= retryAt else { throw State.rateLimited }
        if now().timeIntervalSince(lastAttempt) < 10 { return }
        if let cached = current.snapshot, !force, now().timeIntervalSince(cached.updatedAt) < 300,
           current.expiresAt.timeIntervalSince(now()) > 30 { return }
        lastAttempt = now()
        if current.expiresAt.timeIntervalSince(now()) <= 30 { try await renew() }
        let rows: [DirectoryParcel]
        do { rows = try await directory() }
        catch State.rejected {
            try await renew()
            do { rows = try await directory() }
            catch State.rejected { throw State.expired }
        }
        guard var updated = account else { throw State.expired }
        updated.snapshot = Snapshot(items: rows, updatedAt: now())
        try persist(updated)
    }

    private func renew() async throws {
        guard let config, let previous = account, let token = previous.refreshToken else { throw State.expired }
        let reply = try await send("/oauth/token", form: ["client_id": config.client, "grant_type": "refresh_token", "refresh_token": token])
        if oauthError(reply) == "invalid_grant" || reply.status == 401 { throw State.expired }
        try updateToken(reply, previous: previous)
    }

    private func updateToken(_ reply: Reply, previous: Account?) throws {
        guard let config else { throw State.unconfigured }
        let data: TokenReply = try decode(reply, oauth: true)
        let token = try Self.checked(data.accessToken, limit: 8192)
        guard data.tokenType.lowercased() == "bearer", (1...2_592_000).contains(data.expiresIn),
              token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw State.unavailable }
        try persist(Account(origin: config.origin, client: config.client, token: token,
                            refreshToken: try data.refreshToken.map { try Self.checked($0, limit: 8192) } ?? previous?.refreshToken,
                            expiresAt: now().addingTimeInterval(TimeInterval(data.expiresIn)), snapshot: previous?.snapshot))
    }

    private func persist(_ account: Account) throws {
        let data = try JSONEncoder().encode(account)
        guard data.count <= 3_000_000 else { throw State.incomplete }
        try save(data)
        self.account = account
    }

    private func directory() async throws -> [DirectoryParcel] {
        guard let token = account?.token else { throw State.expired }
        var merged: [String: DirectoryParcel] = [:]
        var seen = Set<String>()
        var cursor: String?
        let deadline = now().addingTimeInterval(40)
        for _ in 0..<12 {
            guard now() <= deadline else { throw State.incomplete }
            let page: Page = try decode(await send("/v1/parcels", cursor: cursor, bearer: token))
            guard page.items.count <= 250 else { throw State.incomplete }
            for row in page.items {
                let item = try row.normalized()
                guard let existing = merged[item.id] else { merged[item.id] = item; continue }
                var preferred = item.preferred(over: existing) ? item : existing
                preferred.sources = Set((existing.sources ?? []) + [item.source]).sorted()
                merged[item.id] = preferred
            }
            guard let next = page.nextCursor else {
                return merged.values.filter { $0.state == .ready }.sorted {
                    $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.trackingNumber < $1.trackingNumber
                }
            }
            let checked = try Self.checked(next, limit: 1024)
            guard seen.insert(checked).inserted else { throw State.incomplete }
            cursor = checked
        }
        throw State.incomplete
    }

    private func send(_ path: String, cursor: String? = nil, form: [String: String]? = nil, bearer: String? = nil) async throws -> Reply {
        guard let config, var parts = URLComponents(url: config.origin, resolvingAgainstBaseURL: false) else { throw State.unconfigured }
        guard now() >= retryAt else { throw State.rateLimited }
        parts.path = path
        if let cursor {
            guard let encoded = DirectoryHTTP.formValue(cursor) else { throw State.unavailable }
            parts.percentEncodedQuery = "cursor=" + encoded
        }
        guard let url = parts.url else { throw State.unavailable }
        let reply = try await request(url, form, bearer)
        if reply.status == 429 || (reply.status == 503 && reply.retryAfter > 0) {
            retryAt = now().addingTimeInterval(min(3600, max(30, reply.retryAfter)))
            throw State.rateLimited
        }
        return reply
    }

    private func checkStatus(_ reply: Reply) throws {
        if reply.status == 401 { throw State.rejected }
        if reply.status == 403 { throw State.forbidden }
        guard (200...299).contains(reply.status) else { throw State.unavailable }
    }

    private func decode<T: Decodable>(_ reply: Reply, oauth: Bool = false) throws -> T {
        try checkStatus(reply)
        let decoder = JSONDecoder()
        if oauth { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        return try decoder.decode(T.self, from: reply.data)
    }

    private func oauthError(_ reply: Reply) -> String? {
        (try? JSONDecoder().decode(OAuthError.self, from: reply.data))?.error
    }

    nonisolated static func checked(_ text: String, limit: Int) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf16.count <= limit,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw State.unavailable }
        return value
    }
}

private final class DirectoryHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private static let delegate = DirectoryHTTP()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 7
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func formValue(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    static func send(_ url: URL, _ form: [String: String]?, _ token: String?) async throws -> ParcelDirectory.Reply {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let form {
            let body = try form.map { key, value in
                guard let encoded = formValue(value) else { throw ParcelDirectory.State.unavailable }
                return key + "=" + encoded
            }.joined(separator: "&")
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ParcelDirectory.State.unavailable }
        let maximum = 1_048_576
        guard response.expectedContentLength <= Int64(maximum) else { throw ParcelDirectory.State.incomplete }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else { throw ParcelDirectory.State.incomplete }
            data.append(byte)
        }
        return .init(status: http.statusCode, data: data, retryAfter: Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0)
    }
}
#endif
