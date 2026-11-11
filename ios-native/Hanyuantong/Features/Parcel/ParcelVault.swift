import Foundation

/// Cookie/session and pickup records share one atomic encrypted envelope per platform.
/// ProtectedStorage uses AES-GCM, a ThisDeviceOnly Keychain key and backup-excluded files.
/// An unidentified login is never persisted. Dynamic identity images/values are never read or cached.
struct ParcelCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var httpOnly: Bool
    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        expires = cookie.expiresDate; httpOnly = cookie.isHTTPOnly
    }
    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]
        if let expires { properties[.expires] = expires }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}
struct ParcelEnvelope: Codable {
    var version = 1
    var cache: ParcelCache
    var cookies: [ParcelCookie]
    var savedAt: Date
    func validated(provider: ParcelProvider, now: Date = Date()) throws -> Self {
        guard version == 1, cookies.count <= 128, savedAt <= now.addingTimeInterval(300),
              savedAt.timeIntervalSince1970 > 0, now.timeIntervalSince(savedAt) < 7 * 24 * 60 * 60 else { throw ParcelFailure.account }
        let restored = cookies.compactMap(\.cookie)
        guard restored.count == cookies.count, restored.allSatisfy({ ParcelPolicy.cookieAllowed($0, provider: provider, now: now) }),
              try ParcelPolicy.account(restored, provider: provider, now: now) == cache.account else { throw ParcelFailure.account }
        _ = try cache.validated(provider: provider, account: cache.account)
        return self
    }
}
final class ParcelVault {
    private let storage: ProtectedStorage
    init(storage: ProtectedStorage) { self.storage = storage }
    static func filename(_ provider: ParcelProvider) -> String { "parcel-v1-" + provider.rawValue }
    func read(_ provider: ParcelProvider, now: Date = Date()) throws -> ParcelEnvelope? {
        guard let value = try storage.read(Self.filename(provider), as: ParcelEnvelope.self) else { return nil }
        return try value.validated(provider: provider, now: now)
    }
    func write(_ value: ParcelEnvelope, provider: ParcelProvider, now: Date = Date()) throws {
        _ = try value.validated(provider: provider, now: now)
        try storage.write(value, name: Self.filename(provider))
    }
    func remove(_ provider: ParcelProvider) throws { try storage.remove(Self.filename(provider)) }
}
