import Foundation

enum GradeOutcome: String, CaseIterable { case passed, failed, pending, unknown
    var title: String { switch self { case .passed: return "已通过"; case .failed: return "未通过"; case .pending: return "待公布"; case .unknown: return "待核对" } }
}
struct AnalyzedGrade: Identifiable {
    let id: String
    let raw: GradeRecord
    let state: GradeOutcome
    let numeric: Double?
    let credit: Double?
    let gpa: Double?
    let term: String
    let order: Int?
    var kind: String
    var band: String {
        guard let numeric else { return state == .pending ? "待公布" : state == .unknown ? "未识别" : "等级/两级制" }
        return numeric < 60 ? "0–59" : numeric < 70 ? "60–69" : numeric < 80 ? "70–79" : numeric < 90 ? "80–89" : "90–100"
    }
}
struct GradeCourseGroup {
    let rows: [AnalyzedGrade]
    let ambiguous: Bool
    let state: GradeOutcome
    let resolved: Bool
    let credit: Double?
    let creditTerm: String?
    let representative: AnalyzedGrade?
}
struct NativeGradeSummary {
    let courses: Int, records: Int, numericCount: Int, weightedCount: Int, gpaCount: Int, excluded: Int, creditCount: Int
    let mean: Double?, weightedMean: Double?, gpa: Double?, earnedCredits: Double, min: Double?, max: Double?
}
struct NativeGradeReport {
    let records: [AnalyzedGrade]
    let groups: [GradeCourseGroup]
    let invalid: Int
    let duplicates: Int
    static func clean(_ value: String) -> String { value.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    static func finite(_ value: Double?) -> Double? { guard let value, value.isFinite, value >= 0 else { return nil }; return value }
    static func value(_ score: String) -> (GradeOutcome, Double?) {
        let text = clean(score)
        let number = matches(text, "^[0-9]+(?:\\.[0-9]+)?(?:分)?$") ? Double(text.replacingOccurrences(of: "分", with: "")) : nil
        let numeric = number.flatMap { (0...100).contains($0) ? $0 : nil }
        if ["", "—", "-", "待公布", "未公布", "暂无", "缓考", "待考", "未录入", "未发布"].contains(text) { return (.pending, numeric) }
        if let numeric { return (numeric >= 60 ? .passed : .failed, numeric) }
        if ["优秀", "良好", "中等", "及格", "合格", "通过"].contains(text) { return (.passed, nil) }
        if ["不及格", "不合格", "未通过", "不通过"].contains(text) { return (.failed, nil) }
        return (.unknown, nil)
    }
    static func term(_ grade: GradeRecord) -> (String, Int?) {
        let raw = clean(grade.term)
        let year = clean(grade.year).isEmpty ? raw.range(of: "20[0-9]{2}", options: .regularExpression).map { String(raw[$0]) } ?? "" : clean(grade.year)
        var season = clean(grade.termCode)
        if season.isEmpty {
            if matches(raw, "秋|第一|第1|[-–—][0-9]{4}\\s*[- ]?1$|\\s3$") { season = "3" }
            else if matches(raw, "春|第二|第2|[-–—][0-9]{4}\\s*[- ]?2$|\\s12$") { season = "12" }
        }
        if matches(year, "^20[0-9]{2}$"), let y = Int(year), ["3", "12"].contains(season) {
            return ("\(y)–\(y + 1) \(season == "3" ? "秋季" : "春季")", y * 10 + (season == "3" ? 1 : 2))
        }
        return (raw.isEmpty ? "学期未提供" : raw, nil)
    }
    init(_ source: [GradeRecord]) {
        var rows: [AnalyzedGrade] = [], seen = Set<String>(), invalid = max(0, source.count - 2000), duplicates = 0
        for sourceRow in source.prefix(2000) {
            var raw = sourceRow
            raw.name = Self.clean(raw.name); raw.score = raw.score.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.name.isEmpty, raw.name.count <= 150, raw.score.count <= 40 else { invalid += 1; continue }
            raw.term = Self.clean(raw.term); raw.kind = Self.clean(raw.kind); raw.courseCode = Self.clean(raw.courseCode)
            raw.recordId = Self.clean(raw.recordId); raw.year = Self.clean(raw.year); raw.termCode = Self.clean(raw.termCode); raw.examType = Self.clean(raw.examType)
            let credit = Self.finite(Double(Self.clean(raw.credit))), gpa = Self.finite(raw.schoolGPA)
            let signature = [raw.courseCode, raw.recordId, raw.name, raw.score, credit.map { String($0) } ?? "null", gpa.map { String($0) } ?? "null", raw.term, raw.year, raw.termCode, raw.kind, raw.examType]
            let key = String(data: try! JSONEncoder().encode(signature), encoding: .utf8)!
            guard seen.insert(key).inserted else { duplicates += 1; continue }
            let (state, numeric) = Self.value(raw.score), (term, order) = Self.term(raw)
            rows.append(AnalyzedGrade(id: key, raw: raw, state: state, numeric: numeric, credit: credit, gpa: gpa, term: term, order: order, kind: raw.kind.isEmpty ? "性质未提供" : raw.kind))
        }
        let missingCodes = Set(rows.filter { $0.raw.courseCode.isEmpty }.map { $0.raw.name })
        let clusters = Dictionary(grouping: rows) { missingCodes.contains($0.raw.name) ? "name:" + $0.raw.name : "code:" + $0.raw.courseCode }
        var groups: [GradeCourseGroup] = [], normalized: [AnalyzedGrade] = []
        for key in clusters.keys.sorted() {
            var list = clusters[key]!
            if Set(list.map(\.kind)).count > 1 { list = list.map { var row = $0; row.kind = "性质待核对"; return row } }
            normalized += list
            let ambiguous = key.hasPrefix("name:") && list.count > 1
            let passed = list.filter { $0.state == .passed }, failed = list.contains { $0.state == .failed }
            let state: GradeOutcome = ambiguous ? .unknown : !passed.isEmpty ? .passed : list.contains { $0.state == .pending } ? .pending : list.allSatisfy { $0.state == .failed } ? .failed : .unknown
            let credits = Set(passed.map(\.credit))
            let credit: Double? = !ambiguous && !passed.isEmpty && credits.count == 1 ? passed[0].credit : nil
            let published = list.filter { $0.state != .pending }
            let firstPass = passed.sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }.first
            groups.append(GradeCourseGroup(rows: list, ambiguous: ambiguous, state: state, resolved: !ambiguous && !passed.isEmpty && failed, credit: credit, creditTerm: firstPass?.term, representative: !ambiguous && published.count == 1 ? published[0] : nil))
        }
        self.records = normalized; self.groups = groups; self.invalid = invalid; self.duplicates = duplicates
    }
    var terms: [String] { Array(Set(records.map(\.term))).sorted { a,b in
        let x = records.first { $0.term == a }?.order ?? Int.max, y = records.first { $0.term == b }?.order ?? Int.max
        return x == y ? a < b : x < y
    } }
    func summary(term: String = "all") -> NativeGradeSummary {
        let selected = groups.filter { term == "all" || $0.rows.contains { $0.term == term } }
        let representatives = selected.compactMap(\.representative).filter { term == "all" || $0.term == term }
        let nums = representatives.filter { $0.numeric != nil }, weighted = nums.filter { ($0.credit ?? 0) > 0 }, gpas = representatives.filter { $0.gpa != nil && ($0.credit ?? 0) > 0 }
        let weight = weighted.reduce(0) { $0 + $1.credit! }, gpaWeight = gpas.reduce(0) { $0 + $1.credit! }
        let earned = groups.filter { $0.credit != nil && (term == "all" || $0.creditTerm == term) }
        return NativeGradeSummary(courses: selected.count, records: records.filter { term == "all" || $0.term == term }.count, numericCount: nums.count, weightedCount: weighted.count, gpaCount: gpas.count, excluded: selected.filter { $0.representative == nil }.count, creditCount: earned.count,
            mean: nums.isEmpty ? nil : nums.reduce(0) { $0 + $1.numeric! } / Double(nums.count),
            weightedMean: weight > 0 ? weighted.reduce(0) { $0 + $1.numeric! * $1.credit! } / weight : nil,
            gpa: gpaWeight > 0 ? gpas.reduce(0) { $0 + $1.gpa! * $1.credit! } / gpaWeight : nil,
            earnedCredits: earned.reduce(0) { $0 + $1.credit! }, min: nums.compactMap(\.numeric).min(), max: nums.compactMap(\.numeric).max())
    }
    func filtered(term: String, query: String, kind: String, state: String, band: String, sort: String) -> [AnalyzedGrade] {
        records.filter { (term == "all" || $0.term == term) && (query.isEmpty || $0.raw.name.lowercased().contains(Self.clean(query).lowercased())) && (kind == "all" || $0.kind == kind) && (state == "all" || $0.state.rawValue == state) && (band == "all" || $0.band == band) }.sorted { a,b in
            switch sort {
            case "name": return a.raw.name.localizedCompare(b.raw.name) == .orderedAscending
            case "score-desc", "score-asc":
                guard let x = a.numeric else { return false }; guard let y = b.numeric else { return true }; return sort == "score-desc" ? x > y : x < y
            case "credit": return (a.credit ?? -1) > (b.credit ?? -1)
            default: return (a.order ?? Int.min) == (b.order ?? Int.min) ? a.raw.name < b.raw.name : (a.order ?? Int.min) > (b.order ?? Int.min)
            }
        }
    }
}
