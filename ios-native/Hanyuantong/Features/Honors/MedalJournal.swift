import Foundation
import CryptoKit
import Combine

struct CampusMedal: Decodable, Identifiable {
    let code, name, group, tier, source, color, condition, description: String
    let goal: Int
    let hidden: Bool?
    let metric: String?
    var id: String { code }
    static let catalog: [CampusMedal] = {
        guard let file = Bundle.main.url(forResource: "medals", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let rows = try? JSONDecoder().decode([CampusMedal].self, from: data) else { return [] }
        return rows
    }()
    static let byCode = Dictionary(uniqueKeysWithValues: catalog.map { ($0.code, $0) })
    var symbol: String {
        ["welcome":"sunrise.fill","arrival":"sparkle","identity":"key.fill","profile":"person.crop.circle",
         "schedule":"calendar","offline":"wifi.slash","exam":"calendar.badge.clock","grade":"graduationcap.fill",
         "learning":"antenna.radiowaves.left.and.right","tasks":"checklist","water":"drop.fill","bath":"cloud.drizzle.fill",
         "laundry":"tshirt.fill","map":"map.fill","life":"leaf.fill","firstpost":"pencil","hello":"bubble.left.fill",
         "liked":"heart.fill","sprout":"leaf.arrow.circlepath","neighbor":"person.2.fill","popular":"star.fill","collector":"bookmark.fill",
         "month":"moon.stars.fill","year":"sun.max.fill","goldfish":"magnifyingglass","puff":"bubble.right.fill",
         "dream":"bed.double.fill","timewalk":"clock.arrow.circlepath","freeday":"cup.and.saucer.fill",
         "mapfish":"location.fill","emptyfish":"tray.fill","lastline":"text.book.closed.fill"][code] ?? "rosette"
    }
}

struct HonorStamp: Codable, Equatable, Identifiable {
    let code: String
    let at: String?
    var id: String { code }
}
struct MemberBadges: Codable, Equatable {
    let official, worn: HonorStamp?
    var visible: [HonorStamp] {
        [official.flatMap { ["developer","moderator"].contains($0.code) ? $0 : nil },
         worn.flatMap { ["seed","creator","contributor"].contains($0.code) ? $0 : nil }].compactMap { $0 }
    }
}
struct NativeHonorHall: Codable, Equatable {
    let id, nickname: String
    let badges: MemberBadges
    let honors: [HonorStamp]
    let showcase: [String]
    let total: Int
    let awards: [String:String]
    let progress: [String:Int]?
}
enum MedalDates {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
}

@MainActor final class MedalJournal: ObservableObject {
    static let shared = MedalJournal()
    private let defaults: UserDefaults
    @Published private(set) var records: [String:[String:Date]]
    @Published private(set) var pins:[String:[String]]
    @Published var notice: CampusMedal?
    private var queue: [CampusMedal] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pins=defaults.dictionary(forKey:"campus.medal-pins.v1") as? [String:[String]] ?? [:]
        records = (defaults.dictionary(forKey:"campus.medals.v1") as? [String:[String:Date]]) ?? [:]
    }
    func bucket(source: String, scope: String?) -> String? {
        if source == "device" { return source }
        guard let scope, !scope.isEmpty, ["school","learning","community"].contains(source) else { return nil }
        return source + "." + SHA256.hash(data:Data(scope.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    func stamp(_ medal: CampusMedal, scope: String?) -> Date? {
        bucket(source:medal.source,scope:scope).flatMap { records[$0]?[medal.code] }
    }
    func pinned(school:String?,learning:String?) -> [String] {
        let keys=[bucket(source:"device",scope:nil),bucket(source:"school",scope:school),bucket(source:"learning",scope:learning)].compactMap{$0}
        return Array(keys.flatMap { key in (pins[key] ?? []).filter { records[key]?[$0] != nil } }.prefix(3))
    }
    func togglePin(_ medal:CampusMedal,school:String?,learning:String?) {
        let scope = medal.source == "school" ? school : learning
        guard medal.source != "community", let key=bucket(source:medal.source,scope:scope),
              stamp(medal,scope:scope) != nil else {return}
        var selected=pins[key] ?? []
        if selected.contains(medal.code) { selected.removeAll{$0 == medal.code} }
        else { guard pinned(school:school,learning:learning).count<3 else{return}; selected.append(medal.code) }
        pins[key]=selected; defaults.set(pins,forKey:"campus.medal-pins.v1")
    }
    func unlock(_ code: String, scope: String? = nil) {
        guard let medal = CampusMedal.byCode[code], medal.source != "community",
              let key = bucket(source:medal.source,scope:scope), records[key]?[code] == nil else { return }
        records[key,default:[:]][code] = Date()
        defaults.set(records,forKey:"campus.medals.v1")
        enqueue(medal)
        if ["bath","laundry","map"].contains(code), ["bath","laundry","map"].allSatisfy({records[key]?[$0] != nil}) { unlock("life") }
    }
    // Account-bound delivery markers suppress duplicates on retries. They never confer an award.
    func delivered(_ codes: [String], owner: String) {
        guard let key = bucket(source:"community",scope:owner) else { return }
        let storageKey = "campus.notices." + key
        var seen = Set(defaults.stringArray(forKey:storageKey) ?? [])
        for code in codes {
            if let medal = CampusMedal.byCode[code], medal.source == "community", seen.insert(code).inserted { enqueue(medal) }
        }
        defaults.set(Array(seen),forKey:storageKey)
    }
    func clearCommunityNotices() {
        queue.removeAll { $0.source == "community" }
        if let m=notice, m.source == "community" { advance(m.code) }
    }
    private func enqueue(_ medal: CampusMedal) {
        if notice == nil { notice = medal } else { queue.append(medal) }
    }
    func advance(_ code: String) {
        if notice?.code == code { notice = queue.isEmpty ? nil : queue.removeFirst() }
    }
}
