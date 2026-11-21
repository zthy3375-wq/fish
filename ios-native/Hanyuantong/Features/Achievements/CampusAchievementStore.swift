import Foundation
import Combine

/// Keep codes, names and award conditions aligned with src/domain/globalAchievements.ts.
/// Only device events are persisted here. School/Learning awards are projected from the
/// currently verified account snapshot; community awards are always server-authoritative.
struct CampusAchievement: Identifiable {
    let code: String
    let name: String
    let group: String
    let tier: String
    let source: String
    let symbol: String
    let condition: String
    let story: String
    let hidden: Bool

    var id: String { code }
    init(_ code: String, _ name: String, _ group: String, _ tier: String,
         _ source: String, _ symbol: String, _ condition: String, _ story: String) {
        self.code = code; self.name = name; self.group = group; self.tier = tier
        self.source = source; self.symbol = symbol; self.condition = condition
        self.story = story; self.hidden = group == "隐藏"
    }
}

enum CampusAchievementCatalog {
    static let groups = ["全部", "初识", "学习", "生活", "社区", "时光", "隐藏"]
    static let entries: [CampusAchievement] = [
        .init("welcome", "你好，邯院", "初识", "普通", "device", "sunrise", "首次打开带有收藏馆的邯院通", "小金鱼为你留了一张空白纪念册。"),
        .init("arrival", "破壳而出", "初识", "普通", "community", "circle.hexagongrid", "首次注册邯院通社区账号", "欢迎来到邯院的这一角。"),
        .init("identity", "身份确认", "初识", "普通", "school", "key", "成功连接学校教务系统", "通往教务处的小门打开了。"),
        .init("profile", "小金鱼的朋友", "初识", "普通", "device", "person.crop.circle", "在本机填写昵称与专业，并保存资料", "以后就这样称呼你。"),
        .init("schedule", "我的第一张课表", "学习", "普通", "school", "calendar", "成功获取并保存一张含课程的学校课表", "新学期有了坐标。"),
        .init("offline", "断网也不怕", "学习", "稀有", "school", "wifi.slash", "断网时打开已缓存的学校课表", "信号消失，下一节课还在。"),
        .init("exam", "考试将至", "学习", "普通", "school", "calendar.badge.clock", "打开考试安排，并看到学校返回的考试", "在学期末的日历上圈一个日期。"),
        .init("grade", "成绩揭晓", "学习", "普通", "school", "graduationcap", "从教务系统成功读取成绩", "这一页，记着你的努力。"),
        .init("learning", "学习通已连接", "学习", "普通", "learning", "books.vertical", "成功同步学习通的课程列表", "散落的课程有了同一个书架。"),
        .init("tasks", "任务清零", "学习", "稀有", "device", "checkmark.circle", "完成一个自建待办和其中至少两个子任务", "最后一个勾，留给自己。"),
        .init("water", "生命之源", "生活", "稀有", "device", "drop", "成功扫描并识别直饮水设备", "一杯水的故事，从这里开始。"),
        .init("bath", "洗去疲惫", "生活", "普通", "device", "shower", "进入趣智校园钱包", "忙完一天，给自己留一点热气。"),
        .init("laundry", "生活技能 +1", "生活", "普通", "device", "washer", "进入胖乖生活钱包", "校园生活，又熟悉了一点。"),
        .init("map", "校园探险家", "生活", "普通", "device", "map", "成功加载一张校园平面图", "下一次迷路，就来找这张图。"),
        .init("life", "生活家", "生活", "稀有", "device", "leaf", "体验趣智、胖乖和校园地图三个功能", "熟悉校园，从这些小事开始。"),
        .init("firstpost", "第一声", "社区", "普通", "community", "square.and.pencil", "发布第一篇有效帖子", "你在邯院通留下了第一篇帖子。"),
        .init("hello", "搭个话吧", "社区", "普通", "community", "bubble.left", "发表第一条有效评论", "一场讨论，因为你多了一句话。"),
        .init("liked", "有人喜欢", "社区", "普通", "community", "heart", "收到其他同学的第一个有效赞", "有人喜欢你留下的内容。"),
        .init("sprout", "开始发芽", "社区", "普通", "community", "leaf", "累计发布 5 篇有效帖子", "第五篇帖子，你的故事还在生长。"),
        .init("neighbor", "温暖的回应", "社区", "稀有", "community", "person.2", "在 10 篇不同帖子下参与有效讨论", "十场讨论里，都有你的身影。"),
        .init("popular", "小有名气", "社区", "稀有", "community", "star", "帖子与评论累计收到 30 个有效赞", "你的表达被更多同学看到了。"),
        .init("collector", "故事收藏家", "社区", "稀有", "community", "bookmark", "收藏 20 篇不同的有效帖子", "你为二十个故事留下了书签。"),
        .init("month", "时光初见", "时光", "稀有", "community", "clock", "邯院通社区账号注册满 30 天", "从初见，到熟悉的日常。"),
        .init("year", "四季流转", "时光", "史诗", "community", "hourglass", "邯院通社区账号注册满 365 天", "你与邯院，已经走过春夏秋冬。"),
        .init("goldfish", "你发现我了！", "隐藏", "稀有", "device", "fish", "在关于页连续轻点版本号七次", "好奇心是个好东西。"),
        .init("puff", "别戳啦！", "隐藏", "稀有", "device", "hand.tap", "连续轻点首页小金鱼五次", "鱼也是有脾气的！"),
        .init("dream", "鱼也会做梦吗？", "隐藏", "稀有", "device", "moon.zzz", "长按首页小金鱼三秒", "嘘，它梦见了一片没有尽头的海。"),
        .init("timewalk", "时间旅行者", "隐藏", "稀有", "device", "clock.arrow.circlepath", "在本学期课表切到第一周，再回到本周", "时间可以倒流，作业不行。"),
        .init("freeday", "今天没有课！", "隐藏", "稀有", "device", "cup.and.saucer", "打开课表里一个没有课程的日期", "今天属于你自己。"),
        .init("mapfish", "原来你在这里", "隐藏", "稀有", "device", "mappin", "找到校园平面图里的小金鱼", "没想到吧，我藏在这里。"),
        .init("emptyfish", "空空如也", "隐藏", "稀有", "device", "tray", "在真正清空的待办清单里找到小鱼", "什么都没有，也挺好。"),
        .init("lastline", "我全都看完了", "隐藏", "稀有", "device", "text.book.closed", "翻到更新日志最后，轻点页尾的落款", "谢谢你认真读到这里。")
    ]
    static let byCode = Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
    static let lifeCodes: Set<String> = ["bath", "laundry", "map"]
}

struct CampusAchievementJournal: Codable, Equatable {
    var version = 1
    var stamps: [String: Date] = [:]
    var pins: [String] = []

    func validated() throws -> Self {
        guard version == 1, stamps.count <= 32, pins.count <= 3,
              Set(pins).count == pins.count,
              stamps.allSatisfy({ code, date in
                  CampusAchievementCatalog.byCode[code]?.source == "device"
                      && date.timeIntervalSince1970 > 0 && date <= Date().addingTimeInterval(86400)
              }),
              pins.allSatisfy({ stamps[$0] != nil }) else {
            throw CampusAchievementFailure.invalid
        }
        return self
    }
}

enum CampusAchievementFailure: LocalizedError {
    case invalid, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: return "荣誉收藏数据暂时无法读取，原记录已保留。"
        case .unavailable: return "荣誉收藏安全存储不可用，请解锁设备后重试。"
        }
    }
}

protocol CampusAchievementPersisting {
    func load() throws -> CampusAchievementJournal?
    func save(_ value: CampusAchievementJournal) throws
}
private struct ProtectedAchievementPersistence: CampusAchievementPersisting {
    let vault: ProtectedStorage
    init() throws { vault = try ProtectedStorage() }
    func load() throws -> CampusAchievementJournal? { try vault.read("achievements-device-v1", as: CampusAchievementJournal.self) }
    func save(_ value: CampusAchievementJournal) throws { try vault.write(value, name: "achievements-device-v1") }
}

@MainActor
final class CampusAchievementStore: ObservableObject {
    @Published private(set) var journal = CampusAchievementJournal()
    @Published private(set) var error: String?
    private var persistence: CampusAchievementPersisting?

    init(persistence: CampusAchievementPersisting? = nil) {
        do {
            let vault: CampusAchievementPersisting = try persistence ?? ProtectedAchievementPersistence()
            journal = try (vault.load() ?? CampusAchievementJournal()).validated()
            self.persistence = vault
        } catch {
            self.error = CampusAchievementFailure.invalid.localizedDescription
        }
    }

    var pins: [CampusAchievement] { journal.pins.compactMap { CampusAchievementCatalog.byCode[$0] } }
    func date(for code: String) -> Date? { journal.stamps[code] }

    /// Save before updating the view. A read/save failure must never overwrite prior awards.
    func record(_ code: String, at: Date = Date()) {
        guard let definition = CampusAchievementCatalog.byCode[code],
              definition.source == "device", journal.stamps[code] == nil,
              at.timeIntervalSince1970 > 0, at <= Date().addingTimeInterval(86400),
              let persistence else { return }
        var next = journal
        next.stamps[code] = at
        if CampusAchievementCatalog.lifeCodes.isSubset(of: Set(next.stamps.keys)),
           next.stamps["life"] == nil {
            next.stamps["life"] = CampusAchievementCatalog.lifeCodes.compactMap { next.stamps[$0] }.max() ?? at
        }
        do {
            try persistence.save(try next.validated())
            journal = next; error = nil
        } catch {
            self.error = "荣誉收藏保存失败，原有记录保持不变。"
        }
    }

    func togglePin(_ code: String) {
        guard journal.stamps[code] != nil, let persistence else { return }
        var next = journal
        if next.pins.contains(code) { next.pins.removeAll { $0 == code } }
        else {
            guard next.pins.count < 3 else { return }
            next.pins.append(code)
        }
        do {
            try persistence.save(try next.validated())
            journal = next; error = nil
        } catch {
            self.error = "荣誉展示设置保存失败，原有选择保持不变。"
        }
    }
}