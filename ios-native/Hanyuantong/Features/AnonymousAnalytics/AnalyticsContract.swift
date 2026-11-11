import Foundation

/// These are the only accepted counters. Never accept event names or properties from school/service data.
enum AnalyticsFeature: String, Codable, CaseIterable {
    case schedule, tasks, learning, shower, wallet, water, laundry, parcel, grades, map
}
enum AnalyticsChoice: String, Codable { case unset, on, off }

struct AnalyticsBuild: Equatable {
    let version: String
    let number: Int
    /// A deliberate release review is required, even if a later build happens to satisfy Android's floor.
    let rolloutReviewed: Bool
    static var current: AnalyticsBuild {
        AnalyticsBuild(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                       number: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0,
                       rolloutReviewed: false)
    }
    var unavailableReason: String? {
        guard version.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil,
              (102...2_147_483_647).contains(number) else {
            return "当前 iPhone 开发版与统计服务的版本校验尚不兼容，暂不开放参与；不会生成统计身份、记录使用次数或上报。"
        }
        guard rolloutReviewed else {
            return "iPhone 统计接入、删除保障和隐私披露尚待完成上线核验，暂不开放参与；不会采集或上报。"
        }
        return nil
    }
}

struct AnalyticsIdentity: Codable, Equatable {
    let id: String
    let token: String
    var isValid: Bool {
        id.range(of: #"^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$"#, options: .regularExpression) != nil &&
        token.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
    }
}

struct AnalyticsCounters: Codable, Equatable {
    var day: String
    var features: [String: Int] = [:]
    mutating func increment(_ feature: AnalyticsFeature, on day: String) {
        if self.day != day { self.day = day; features = [:] }
        features[feature.rawValue] = min(1000, (features[feature.rawValue] ?? 0) + 1)
    }
    var isValid: Bool {
        day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil &&
        features.allSatisfy { AnalyticsFeature(rawValue: $0.key) != nil && (0...1000).contains($0.value) }
    }
}

struct AnalyticsRecord: Codable, Equatable {
    var schema = 1
    var choice: AnalyticsChoice = .unset
    var identity: AnalyticsIdentity?
    var deletePending = false
    /// Persisted BEFORE enroll. A transport failure may leave an unacknowledged enroll running server-side.
    var enrollmentInFlight = false
    /// The existing server has no deletion tombstone. Do not claim erasure after an ambiguous enrollment.
    var enrollmentUncertain = false
    var enrolled = false
    var counters: AnalyticsCounters?
    var dirty = false
    var lastSent: Date?
    var sentDay: String?
    var sentBuild: Int?
    var isValid: Bool {
        schema == 1 && (identity == nil || identity?.isValid == true) &&
        (counters == nil || counters?.isValid == true) &&
        (choice != .on || identity != nil) && (!deletePending || (choice == .off && identity != nil)) &&
        (!(enrolled || enrollmentInFlight || enrollmentUncertain) || identity != nil) &&
        (lastSent == nil || lastSent!.timeIntervalSince1970.isFinite)
    }
}

struct AnalyticsState: Equatable {
    var choice: AnalyticsChoice = .unset
    var deletePending = false
    var deletionUncertain = false
    var lastSent: Date?
    var hasIdentity = false
}

enum AnalyticsFailure: Error { case invalid, storage, response, oversized, redirect }
enum AnalyticsAction: String { case enroll, record, delete }
struct AnalyticsResponse: Equatable { let status: Int; let ok: Bool }

enum AnalyticsContract {
    static let endpoint = URL(string: "https://hanyuantong-d8gjzt1jh12370215-1527874185.ap-shanghai.app.tcloudbase.com/hyt-analytics/api/metrics")!
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func request(_ action: AnalyticsAction, identity: AnalyticsIdentity, build: AnalyticsBuild,
                        counters: AnalyticsCounters? = nil, now: Date = Date()) throws -> URLRequest {
        guard identity.isValid else { throw AnalyticsFailure.invalid }
        var body: [String: Any] = ["id": identity.id]
        if action == .record {
            guard build.unavailableReason == nil, let counters, counters.isValid,
                  [day(now), day(now.addingTimeInterval(-86400))].contains(counters.day) else { throw AnalyticsFailure.invalid }
            body["day"] = counters.day; body["version"] = build.version
            body["versionCode"] = build.number; body["features"] = counters.features
        }
        // Keep the production schema, which rejects additional fields, but never impersonate Android.
        var request = URLRequest(url: endpoint.appendingPathComponent(action.rawValue), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(identity.token, forHTTPHeaderField: "X-Hyt-Token")
        let version = build.version.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) == nil ? "unknown" : build.version
        request.setValue("Hanyuantong/\(version) iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        guard request.httpBody!.count <= 2048 else { throw AnalyticsFailure.invalid }
        return request
    }
}
