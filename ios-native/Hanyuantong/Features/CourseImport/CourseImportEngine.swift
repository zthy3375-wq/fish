import Foundation

struct CourseImportFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum CourseImportField: String, CaseIterable, Identifiable {
    case name, day, startPeriod, endPeriod, start, end, teacher, room, weeks, rule, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "课程名称"
        case .day: return "星期"
        case .startPeriod: return "开始节次"
        case .endPeriod: return "结束节次"
        case .start: return "开始时间"
        case .end: return "结束时间"
        case .teacher: return "教师"
        case .room: return "地点"
        case .weeks: return "教学周"
        case .rule: return "单双周"
        case .notes: return "备注"
        }
    }
    var required: Bool { [.name, .day, .start, .end, .weeks].contains(self) }
    var aliases: [String] {
        switch self {
        case .name: return ["课程名称", "课程", "课程名", "name", "subject", "summary"]
        case .day: return ["星期", "星期几", "day", "weekday"]
        case .startPeriod: return ["开始节次", "起始节次", "startperiod"]
        case .endPeriod: return ["结束节次", "endperiod"]
        case .start: return ["开始时间", "上课时间", "start"]
        case .end: return ["结束时间", "下课时间", "end"]
        case .teacher: return ["教师", "任课教师", "老师", "teacher"]
        case .room: return ["地点", "教室", "上课地点", "room", "location"]
        case .weeks: return ["教学周", "周次", "周数", "weeks"]
        case .rule: return ["单双周", "周规则", "rule"]
        case .notes: return ["备注", "notes"]
        }
    }
}

struct CourseImportTable {
    let headers: [String]
    let rows: [[String]]
    var warnings: [String] = ["CSV 使用 UTF-8 编码；Excel 时间单元格请设为文本 HH:mm。未映射列不会导入。"]
}

struct CourseImportPreview {
    var courses: [Course] = []
    var errors: [String] = []
    var warnings: [String] = []
    var issues: [String] = []
    var duplicates = 0
    var canImport: Bool { errors.isEmpty && !courses.isEmpty }
}

enum CourseImportResult {
    case table(CourseImportTable)
    case preview(CourseImportPreview)
}

/// Parsing never writes to a store. The UI must show a preview and obtain confirmation.
enum CourseImportEngine {
    typealias Mapping = [CourseImportField: String]
    static let maximumBytes = 5 * 1024 * 1024
    static let maximumRows = 3000
    static let maximumColumns = 50
    static let csvTemplate = "课程名称,星期,开始节次,结束节次,开始时间,结束时间,教师,地点,教学周,单双周,备注\r\n示例课程（请修改）,1,1,2,08:00,09:35,任课教师,教学楼101,1-18,每周,\r\n"

    static func read(from url: URL, semesterStart: Date, weekCount: Int, existing: [Course]) throws -> CourseImportResult {
        guard ["csv", "xlsx", "ics"].contains(url.pathExtension.lowercased()) else {
            throw CourseImportFailure("请选择 CSV、XLSX 或 ICS 课程文件；JSON 备份请到“数据”恢复。")
        }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true else { throw CourseImportFailure("请选择普通课程文件。") }
        guard (info.fileSize ?? 0) <= maximumBytes else { throw CourseImportFailure("文件超过 5 MB，请拆分课表。") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            try checkSize(data)
        }
        return try parse(name: url.lastPathComponent, data: data, semesterStart: semesterStart, weekCount: weekCount, existing: existing)
    }

    static func parse(name: String, data: Data, semesterStart: Date, weekCount: Int = 18, existing: [Course] = []) throws -> CourseImportResult {
        try checkSize(data)
        try validateContext(semesterStart, weekCount)
        switch (name as NSString).pathExtension.lowercased() {
        case "csv": return .table(try readCSV(data))
        case "xlsx": return .table(try CourseWorkbookReader.read(data))
        case "ics": return .preview(try CourseCalendarReader.preview(data, semesterStart: semesterStart, weekCount: weekCount, existing: existing))
        default: throw CourseImportFailure("请选择 CSV、XLSX 或 ICS 课程文件；JSON 备份请到“数据”恢复。")
        }
    }

    static func checkSize(_ data: Data) throws {
        guard data.count <= maximumBytes else { throw CourseImportFailure("文件超过 5 MB，请拆分课表。") }
    }
    static func validateContext(_ start: Date, _ count: Int) throws {
        guard (1...60).contains(count), start.timeIntervalSince1970.isFinite,
              (-2208988800...7289654400).contains(start.timeIntervalSince1970) else {
            throw CourseImportFailure("请先设置有效的学期起点与教学周数（1–60）。")
        }
    }
    static func utf8(_ data: Data) throws -> String {
        try checkSize(data)
        guard var text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw CourseImportFailure("文件不是有效的 UTF-8 文本，请另存为 UTF-8 后重试。")
        }
        if text.first == "\u{feff}" { text.removeFirst() }
        return text
    }

    /// RFC 4180 quoted fields, doubled quotes and embedded CR/LF, without lossy decoding.
    static func readCSV(_ data: Data) throws -> CourseImportTable {
        let bytes = Array(try utf8(data).utf8)
        enum State { case start, plain, quoted, closed }
        var state = State.start
        var rows: [[String]] = [], row: [String] = [], cell: [UInt8] = []
        func appendCell() throws {
            guard row.count < maximumColumns, cell.count <= 65536 else { throw CourseImportFailure("表格超过 50 列或单元格过长。") }
            row.append(String(decoding: cell, as: UTF8.self)); cell.removeAll(keepingCapacity: true)
        }
        func appendRow() throws {
            try appendCell()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                guard rows.count <= maximumRows else { throw CourseImportFailure("表格超过 3000 行。") }
                rows.append(row)
            }
            row.removeAll(keepingCapacity: true)
        }
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if state == .quoted {
                if byte == 34 {
                    if index + 1 < bytes.count, bytes[index + 1] == 34 { cell.append(34); index += 1 }
                    else { state = .closed }
                } else { cell.append(byte) }
            } else if byte == 44 {
                try appendCell(); state = .start
            } else if byte == 10 || byte == 13 {
                try appendRow(); state = .start
                if byte == 13, index + 1 < bytes.count, bytes[index + 1] == 10 { index += 1 }
            } else if byte == 34 {
                guard state == .start else { throw CourseImportFailure("CSV 引号位置无效，请检查分隔符和引号。") }
                state = .quoted
            } else if state == .closed {
                guard byte == 32 || byte == 9 else { throw CourseImportFailure("CSV 结束引号后出现了非分隔内容。") }
            } else {
                cell.append(byte); state = .plain
            }
            guard cell.count <= 65536 else { throw CourseImportFailure("CSV 单元格过长。") }
            index += 1
        }
        guard state != .quoted else { throw CourseImportFailure("CSV 引号未闭合。") }
        if !cell.isEmpty || !row.isEmpty || state != .start { try appendRow() }
        return try table(rows)
    }

    static func table(_ rows: [[String]]) throws -> CourseImportTable {
        guard let first = rows.first, !first.isEmpty, first.count <= maximumColumns, rows.count <= maximumRows + 1 else {
            throw CourseImportFailure("表格为空或超过 3000 行 / 50 列。")
        }
        let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "") }
        guard !headers.contains(""), Set(headers).count == headers.count else { throw CourseImportFailure("列名不能为空或重复。") }
        guard rows.dropFirst().allSatisfy({ $0.count == headers.count }) else {
            throw CourseImportFailure("列数不一致，请检查 CSV 分隔符和引号。")
        }
        return CourseImportTable(headers: headers, rows: Array(rows.dropFirst()))
    }

    static func guessMapping(_ headers: [String]) -> Mapping {
        var mapping: Mapping = [:]
        for field in CourseImportField.allCases {
            mapping[field] = headers.first { header in
                let normalized = header.lowercased().filter { !$0.isWhitespace && $0 != "_" }
                return field.aliases.contains(normalized)
            }
        }
        return mapping
    }

    static func parseWeeks(_ value: String, maximum: Int) throws -> [Int] {
        var clean = value.filter { !$0.isWhitespace && $0 != "第" && $0 != "周" }
        for separator in ["–", "—", "~", "～", "至"] { clean = clean.replacingOccurrences(of: separator, with: "-") }
        for separator in ["，", "、", ";"] { clean = clean.replacingOccurrences(of: separator, with: ",") }
        var result = Set<Int>()
        for part in clean.components(separatedBy: ",") {
            guard part.range(of: #"^[0-9]+(?:-[0-9]+)?$"#, options: .regularExpression) != nil else {
                throw CourseImportFailure("教学周应为 1-18 或 1,3,5。")
            }
            let bounds = part.components(separatedBy: "-")
            guard let first = Int(bounds[0]), let last = Int(bounds.last!), first >= 1, last >= first, last <= maximum else {
                throw CourseImportFailure("教学周超出当前学期。")
            }
            result.formUnion(first...last)
        }
        return result.sorted()
    }

    static func preview(_ table: CourseImportTable, mapping: Mapping, semesterStart: Date, weekCount: Int = 18, existing: [Course] = []) -> CourseImportPreview {
        var result = CourseImportPreview(warnings: table.warnings)
        do { try validateContext(semesterStart, weekCount) } catch { result.errors.append(error.localizedDescription); return result }
        guard table.rows.count <= maximumRows, table.headers.count <= maximumColumns,
              table.rows.allSatisfy({ $0.count == table.headers.count }) else {
            result.errors.append("表格超过限制或列数不一致。"); return result
        }
        let missing = CourseImportField.allCases.filter { $0.required && !table.headers.contains(mapping[$0] ?? "") }
        guard missing.isEmpty else {
            result.errors.append("请映射必填列：" + missing.map(\.title).joined(separator: "、")); return result
        }
        let positions = mapping.compactMapValues { table.headers.firstIndex(of: $0) }
        for (index, row) in table.rows.enumerated() {
            do {
                func get(_ field: CourseImportField) -> String {
                    positions[field].map { row[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                }
                var weeks = try parseWeeks(get(.weeks), maximum: weekCount)
                switch get(.rule) {
                case "", "每周", "all", "custom", "自定义": break
                case "单周", "odd": weeks = weeks.filter { $0 % 2 == 1 }
                case "双周", "even": weeks = weeks.filter { $0 % 2 == 0 }
                default: throw CourseImportFailure("无法识别单双周规则。")
                }
                var dayText = get(.day)
                for prefix in ["星期", "礼拜", "周"] { dayText = dayText.replacingOccurrences(of: prefix, with: "") }
                let day = Int(dayText) ?? ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7][dayText] ?? 0
                func period(_ field: CourseImportField) throws -> Int? {
                    let text = get(field)
                    guard !text.isEmpty else { return nil }
                    guard text.range(of: #"^[0-9]{1,2}$"#, options: .regularExpression) != nil, let value = Int(text) else {
                        throw CourseImportFailure("节次应为 1–24 之间的整数。")
                    }
                    return value
                }
                let startPeriod = try period(.startPeriod), endPeriod = try period(.endPeriod)
                var course = Course(name: get(.name), teacher: get(.teacher), room: get(.room), day: day,
                                    start: get(.start), end: get(.end), weeks: weeks, color: "blue")
                course.startPeriod = startPeriod; course.endPeriod = endPeriod; course.notes = get(.notes)
                if let startPeriod, let endPeriod { course.period = startPeriod == endPeriod ? "\(startPeriod)" : "\(startPeriod)-\(endPeriod)" }
                try validate(course, weekCount: weekCount)
                if (existing + result.courses).contains(where: { isDuplicate(course, $0) }) { result.duplicates += 1; continue }
                for other in existing + result.courses where result.issues.count < 200 && overlaps(course, other) {
                    result.issues.append("\(course.name) 与 \(other.name)：周\(course.day) \(course.start)–\(course.end) 教学周重叠。")
                }
                if let slot = result.courses.firstIndex(where: { sameSlot(course, $0) }) {
                    result.courses[slot].weeks = Set(result.courses[slot].weeks + course.weeks).sorted()
                } else { result.courses.append(course) }
                if startPeriod == nil { result.warnings.append("部分课程无节次，仅按明确提供的时间显示，未推测节次。") }
            } catch { result.errors.append("第 \(index + 2) 行：\(error.localizedDescription)") }
        }
        if result.courses.count + existing.filter({ $0.source == "personal" }).count > 2000 {
            result.errors.append("导入后个人课程安排超过 2000 条，请拆分或清理后重试。")
        }
        if result.issues.count == 200 { result.warnings.append("时间冲突提示最多显示 200 条。请逐一核对预览中的安排。") }
        result.warnings = unique(result.warnings)
        result.issues = unique(result.issues)
        return result
    }

    static func validate(_ course: Course, weekCount: Int) throws {
        guard !course.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, course.name.count <= 150,
              course.teacher.count <= 100, course.notes.count <= 2000, course.room.count <= 150 else {
            throw CourseImportFailure("课程名称必填；名称/地点限 150 字、教师限 100 字、备注限 2000 字。")
        }
        guard (1...7).contains(course.day) else { throw CourseImportFailure("星期应为 1–7 或星期一至星期日。") }
        guard validTime(course.start), validTime(course.end), course.end > course.start else {
            throw CourseImportFailure("结束时间必须晚于开始时间，时间格式为 HH:mm。")
        }
        switch (course.startPeriod, course.endPeriod) {
        case (nil, nil): break
        case let (first?, last?) where (1...24).contains(first) && (first...24).contains(last): break
        default: throw CourseImportFailure("节次范围应在 1–24 之间，开始与结束节次必须同时填写。")
        }
        guard !course.weeks.isEmpty, course.weeks.allSatisfy({ (1...weekCount).contains($0) }), Set(course.weeks).count == course.weeks.count else {
            throw CourseImportFailure("教学周范围或单双周设置无效。")
        }
    }
    static func validTime(_ value: String) -> Bool { value.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil }
    static func overlaps(_ lhs: Course, _ rhs: Course) -> Bool {
        lhs.day == rhs.day && lhs.start < rhs.end && rhs.start < lhs.end && !Set(lhs.weeks).isDisjoint(with: rhs.weeks)
    }
    static func isDuplicate(_ lhs: Course, _ rhs: Course) -> Bool {
        lhs.day == rhs.day && lhs.name.trimmingCharacters(in: .whitespacesAndNewlines) == rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
            && lhs.teacher.trimmingCharacters(in: .whitespacesAndNewlines) == rhs.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.room == rhs.room && Set(lhs.weeks) == Set(rhs.weeks)
    }
    private static func sameSlot(_ lhs: Course, _ rhs: Course) -> Bool {
        lhs.name == rhs.name && lhs.teacher == rhs.teacher && lhs.notes == rhs.notes && lhs.day == rhs.day
            && lhs.start == rhs.start && lhs.end == rhs.end && lhs.room == rhs.room && lhs.startPeriod == rhs.startPeriod && lhs.endPeriod == rhs.endPeriod
    }
    static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
}
