import Foundation

/// A deliberately bounded RFC 5545 subset. Unsupported recurrence semantics are an error,
/// never a guessed schedule. UTC is converted to campus time; floating times use Beijing.
enum CourseCalendarReader {
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }
    private struct Event {
        var properties: [Property] = []
        func values(_ key: String) -> [Property] { properties.filter { $0.name == key } }
        func one(_ key: String, required: Bool = false) throws -> Property? {
            let matches = values(key)
            guard matches.count <= 1, !required || matches.count == 1 else { throw CourseImportFailure("事件缺少或重复 \(key)。") }
            return matches.first
        }
    }
    private struct Time {
        let date: Date
        let utc: Bool
    }
    private struct Rule {
        let frequency: String
        let interval: Int
        let count: Int?
        let until: Date?
        let weekdays: Set<Int>?
        let weekStart: Int
    }

    static func preview(_ data: Data, semesterStart: Date, weekCount: Int, existing: [Course]) throws -> CourseImportPreview {
        try CourseImportEngine.validateContext(semesterStart, weekCount)
        let events = try parse(try CourseImportEngine.utf8(data))
        let first = ScheduleMath.calendar.startOfDay(for: semesterStart)
        guard let stop = ScheduleMath.calendar.date(byAdding: .day, value: weekCount * 7, to: first) else { throw CourseImportFailure("学期日期无效。") }
        var rows: [[String]] = []
        var errors: [String] = []
        for (index, event) in events.enumerated() {
            do {
                let result = try expand(event, first: first, stop: stop, remaining: CourseImportEngine.maximumRows - rows.count)
                rows.append(contentsOf: result)
            } catch { errors.append("事件 \(index + 1)：\(error.localizedDescription)") }
        }
        let headers = CourseImportField.allCases.map(\.rawValue)
        let mapping = Dictionary(uniqueKeysWithValues: CourseImportField.allCases.map { ($0, $0.rawValue) })
        let warning = "ICS 按具体日期还原教学周；无节次及教师标准字段，不推测。无时区时间按北京时间解释，仅导入所选学期内的定时课程。支持每日/每周重复、INTERVAL、COUNT/UNTIL、BYDAY、WKST、RDATE 和 EXDATE；其他重复规则会报错。"
        var result = CourseImportEngine.preview(CourseImportTable(headers: headers, rows: rows, warnings: [warning]), mapping: mapping,
                                                semesterStart: semesterStart, weekCount: weekCount, existing: existing)
        result.errors.append(contentsOf: errors)
        if rows.isEmpty && errors.isEmpty { result.errors.append("所选学期内没有可导入的定时课程。") }
        return result
    }

    private static func parse(_ text: String) throws -> [Event] {
        let physical = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard physical.count <= 50000 else { throw CourseImportFailure("ICS 行数超过安全上限。") }
        var lines: [String] = []
        for line in physical {
            if line.first == " " || line.first == "\t" {
                guard !lines.isEmpty else { throw CourseImportFailure("ICS 折行位置无效。") }
                lines[lines.count - 1].append(contentsOf: line.dropFirst())
                guard lines.last!.utf8.count <= 65536 else { throw CourseImportFailure("ICS 属性过长。") }
            } else if !line.isEmpty {
                guard line.utf8.count <= 65536 else { throw CourseImportFailure("ICS 属性过长。") }
                lines.append(line)
            }
        }
        var stack: [String] = [], events: [Event] = [], event: Event?
        var calendars = 0, version = false, calendarEnded = false
        for line in lines {
            let property = try contentLine(line)
            if property.name == "BEGIN" {
                let type = property.value.uppercased()
                guard !calendarEnded, stack.count < 8 else { throw CourseImportFailure("ICS 组件结构无效。") }
                if stack.isEmpty {
                    guard type == "VCALENDAR", calendars == 0 else { throw CourseImportFailure("请选择有效的 VCALENDAR 文件。") }
                    calendars += 1
                } else if type == "VEVENT" {
                    guard stack == ["VCALENDAR"], event == nil, events.count < 500 else { throw CourseImportFailure("ICS 事件数超过 500 或事件嵌套无效。") }
                    event = Event()
                } else if stack == ["VCALENDAR"] {
                    guard type == "VTIMEZONE" else { throw CourseImportFailure("ICS 包含非课程组件 \(type)，请仅导出事件。") }
                } else if stack.last == "VEVENT" {
                    guard type == "VALARM" else { throw CourseImportFailure("ICS 事件包含不支持的嵌套组件。") }
                } else if stack.last == "VTIMEZONE" {
                    guard ["STANDARD", "DAYLIGHT"].contains(type) else { throw CourseImportFailure("ICS 时区结构无效。") }
                } else { throw CourseImportFailure("ICS 组件嵌套无效。") }
                stack.append(type)
            } else if property.name == "END" {
                guard stack.last == property.value.uppercased() else { throw CourseImportFailure("ICS 组件未正确闭合。") }
                if stack.last == "VEVENT", let completed = event { events.append(completed); event = nil }
                if stack.last == "VCALENDAR" { calendarEnded = true }
                stack.removeLast()
            } else if stack.isEmpty { throw CourseImportFailure("ICS 属性位于日历外。") }
            else if stack == ["VCALENDAR"] {
                if property.name == "VERSION" {
                    guard !version, property.value == "2.0" else { throw CourseImportFailure("仅支持 ICS 2.0。") }
                    version = true
                }
                if property.name == "METHOD", !["PUBLISH", ""].contains(property.value.uppercased()) {
                    throw CourseImportFailure("请导出静态课表日历，不支持会议邀请或取消消息。")
                }
                if property.name == "CALSCALE", property.value.uppercased() != "GREGORIAN" { throw CourseImportFailure("仅支持公历课表。") }
            } else if stack.last == "VEVENT" {
                guard event!.properties.count < 200 else { throw CourseImportFailure("单个事件属性过多。") }
                event?.properties.append(property)
            } else if stack.last == "VTIMEZONE", property.name == "TZID", property.value != "Asia/Shanghai" {
                throw CourseImportFailure("暂不支持时区 \(property.value)，请导出 UTC 或 Asia/Shanghai。")
            }
        }
        guard stack.isEmpty, calendars == 1, calendarEnded, version else { throw CourseImportFailure("ICS 文件不完整或缺少 VERSION:2.0。") }
        return events
    }

    private static func contentLine(_ line: String) throws -> Property {
        var quoted = false, colon: String.Index?
        for index in line.indices {
            if line[index] == "\"" { quoted.toggle() }
            if line[index] == ":" && !quoted { colon = index; break }
        }
        guard let colon, !quoted else { throw CourseImportFailure("ICS 属性格式无效。") }
        let head = String(line[..<colon])
        var parts: [String] = [], part = ""
        quoted = false
        for character in head {
            if character == "\"" { quoted.toggle() }
            if character == ";" && !quoted { parts.append(part); part = "" }
            else { part.append(character) }
        }
        parts.append(part)
        let name = parts[0].uppercased()
        guard name.range(of: #"^[A-Z0-9-]+$"#, options: .regularExpression) != nil else { throw CourseImportFailure("ICS 属性名称无效。") }
        var parameters: [String: String] = [:]
        for entry in parts.dropFirst() {
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, !pair[0].isEmpty else { throw CourseImportFailure("ICS 参数无效。") }
            let key = pair[0].uppercased()
            guard parameters[key] == nil else { throw CourseImportFailure("ICS 参数重复。") }
            var value = String(pair[1])
            if value.first == "\"", value.last == "\"", value.count >= 2 { value.removeFirst(); value.removeLast() }
            parameters[key] = value
        }
        return Property(name: name, parameters: parameters, value: String(line[line.index(after: colon)...]))
    }

    private static func time(_ property: Property, value: String? = nil, allowSeconds: Bool = false) throws -> Time {
        let text = value ?? property.value
        if property.parameters["VALUE"]?.uppercased() == "DATE" || text.count == 8 { throw CourseImportFailure("全天事件无法还原上课时间。") }
        guard property.parameters.keys.allSatisfy({ ["TZID", "VALUE"].contains($0) }),
              property.parameters["VALUE"] == nil || property.parameters["VALUE"]?.uppercased() == "DATE-TIME" else {
            throw CourseImportFailure("不支持此日期时间参数，请导出标准 DATE-TIME。")
        }
        let utc = text.hasSuffix("Z")
        if let zone = property.parameters["TZID"] {
            guard zone == "Asia/Shanghai", !utc else { throw CourseImportFailure("暂不支持时区 \(zone) 或 UTC/TZID 混用，请导出 UTC 或 Asia/Shanghai。") }
        }
        guard text.range(of: #"^[0-9]{8}T[0-9]{6}Z?$"#, options: .regularExpression) != nil else { throw CourseImportFailure("ICS 日期时间格式无效。") }
        let bytes = Array(text.utf8)
        func number(_ start: Int, _ count: Int) -> Int { bytes[start..<(start + count)].reduce(0) { $0 * 10 + Int($1 - 48) } }
        let year = number(0, 4), month = number(4, 2), day = number(6, 2), hour = number(9, 2), minute = number(11, 2), second = number(13, 2)
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60, allowSeconds || second == 0 else {
            throw CourseImportFailure("ICS 日期无效或含秒级安排；请将时间对齐到整分钟。")
        }
        var calendar = ScheduleMath.calendar
        if utc { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components), calendar.component(.year, from: date) == year, calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day, calendar.component(.hour, from: date) == hour,
              calendar.component(.minute, from: date) == minute, calendar.component(.second, from: date) == second else {
            throw CourseImportFailure("ICS 日期无效。")
        }
        return Time(date: date, utc: utc)
    }

    private static func rule(_ property: Property, start: Time) throws -> Rule {
        guard property.parameters.isEmpty else { throw CourseImportFailure("不支持带参数的 RRULE。") }
        var fields: [String: String] = [:]
        for part in property.value.uppercased().components(separatedBy: ";") {
            let pair = part.components(separatedBy: "=")
            guard pair.count == 2, !pair[1].isEmpty, fields[pair[0]] == nil else { throw CourseImportFailure("RRULE 格式无效。") }
            fields[pair[0]] = pair[1]
        }
        let supported: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"]
        guard Set(fields.keys).isSubset(of: supported), let frequency = fields["FREQ"], ["DAILY", "WEEKLY"].contains(frequency) else {
            throw CourseImportFailure("此重复规则尚不支持。仅支持 DAILY/WEEKLY 及 INTERVAL、COUNT/UNTIL、BYDAY、WKST；请展开为独立事件后导入。")
        }
        func integer(_ key: String, fallback: Int?) throws -> Int? {
            guard let value = fields[key] else { return fallback }
            guard value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, let n = Int(value), (1...5000).contains(n) else {
                throw CourseImportFailure("RRULE \(key) 超出安全范围 1–5000。")
            }
            return n
        }
        let count = try integer("COUNT", fallback: nil)
        let interval = try integer("INTERVAL", fallback: 1)!
        guard count == nil || fields["UNTIL"] == nil else { throw CourseImportFailure("RRULE 不可同时包含 COUNT 和 UNTIL。") }
        var until: Date?
        if let value = fields["UNTIL"] {
            let end = try time(Property(name: "UNTIL", parameters: [:], value: value), allowSeconds: true)
            // Floating DTSTART requires floating UNTIL; UTC requires UTC. TZID starts may use UTC UNTIL.
            guard !start.utc || end.utc else { throw CourseImportFailure("UTC 重复事件的 UNTIL 必须为 UTC。") }
            until = end.date
            guard end.date >= start.date else { throw CourseImportFailure("重复结束日期早于开始日期。") }
        }
        let names = ["MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6, "SU": 7]
        var days: Set<Int>?
        if let value = fields["BYDAY"] {
            let entries = value.components(separatedBy: ",")
            guard entries.allSatisfy({ names[$0] != nil }), Set(entries).count == entries.count else {
                throw CourseImportFailure("不支持带序号或无效的 BYDAY，请展开为独立事件。")
            }
            days = Set(entries.compactMap { names[$0] })
        }
        guard let weekStart = names[fields["WKST"] ?? "MO"] else { throw CourseImportFailure("WKST 无效。") }
        return Rule(frequency: frequency, interval: interval, count: count, until: until, weekdays: days, weekStart: weekStart)
    }

    private static func expand(_ event: Event, first: Date, stop: Date, remaining: Int) throws -> [[String]] {
        for property in ["RECURRENCE-ID", "DURATION", "EXRULE"] where !event.values(property).isEmpty {
            throw CourseImportFailure("不支持 \(property)，请将改期安排转为带 DTEND 的独立事件后导入。")
        }
        if let status = try event.one("STATUS"), status.value.uppercased() == "CANCELLED" { return [] }
        let startProperty = try event.one("DTSTART", required: true)!
        let endProperty = try event.one("DTEND", required: true)!
        let start = try time(startProperty), end = try time(endProperty)
        guard start.utc == end.utc, startProperty.parameters["TZID"] == endProperty.parameters["TZID"] else {
            throw CourseImportFailure("开始和结束时间必须使用相同的时区格式。")
        }
        let duration = end.date.timeIntervalSince(start.date)
        guard duration > 0, duration < 86400 else { throw CourseImportFailure("课程时长无效或跨日。") }
        let summary = try unescape(try event.one("SUMMARY", required: true)!.value)
        let location = try unescape(try event.one("LOCATION")?.value ?? "")
        let notes = try unescape(try event.one("DESCRIPTION")?.value ?? "")
        var occurrences: Set<Date> = [start.date]
        var excluded = Set<Date>()
        for key in ["RDATE", "EXDATE"] {
            for property in event.values(key) {
                for value in property.value.components(separatedBy: ",") {
                    let date = try time(property, value: value).date
                    if key == "RDATE" { occurrences.insert(date) } else { excluded.insert(date) }
                    guard occurrences.count + excluded.count <= 5000 else { throw CourseImportFailure("日期例外超过 5000 条。") }
                }
            }
        }
        if let property = try event.one("RRULE") {
            let rule = try rule(property, start: start)
            var calendar = ScheduleMath.calendar
            if start.utc { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }
            func weekday(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 + 1 }
            let startDay = weekday(start.date)
            if let weekdays = rule.weekdays, !weekdays.contains(startDay) {
                throw CourseImportFailure("DTSTART 与 BYDAY 不一致，请修正或展开事件后导入。")
            }
            let weekdays = rule.weekdays ?? [startDay]
            let anchorOffset = (startDay - rule.weekStart + 7) % 7
            var dayIndex = 0, generated = 0, candidate = start.date
            while candidate < stop && (rule.until == nil || candidate <= rule.until!) {
                guard dayIndex <= 36600 else { throw CourseImportFailure("重复事件起点过早，超过安全展开范围，请缩小日期范围。") }
                let matches: Bool
                if rule.frequency == "DAILY" {
                    matches = dayIndex % rule.interval == 0 && (rule.weekdays == nil || weekdays.contains(weekday(candidate)))
                } else {
                    matches = ((dayIndex + anchorOffset) / 7) % rule.interval == 0 && weekdays.contains(weekday(candidate))
                }
                if matches {
                    generated += 1
                    guard generated <= 5000 else { throw CourseImportFailure("循环事件超过安全展开上限 5000，请缩小日期范围。") }
                    occurrences.insert(candidate)
                    if let count = rule.count, generated >= count { break }
                }
                dayIndex += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { throw CourseImportFailure("重复事件日期无效。") }
                candidate = next
            }
        }
        var rows: [[String]] = []
        for occurrence in occurrences.subtracting(excluded).sorted() where occurrence >= first && occurrence < stop {
            let finish = occurrence.addingTimeInterval(duration)
            guard ScheduleMath.calendar.isDate(occurrence, inSameDayAs: finish) else { throw CourseImportFailure("跨日课程请拆分。") }
            guard rows.count < remaining else { throw CourseImportFailure("展开后超过 3000 次上课安排。") }
            func clock(_ date: Date) -> String {
                let parts = ScheduleMath.calendar.dateComponents([.hour, .minute], from: date)
                return String(format: "%02d:%02d", parts.hour!, parts.minute!)
            }
            let values: [CourseImportField: String] = [.name: summary, .day: String(ScheduleMath.weekday(on: occurrence)),
                .start: clock(occurrence), .end: clock(finish), .room: location, .weeks: String(ScheduleMath.week(on: occurrence, start: first)), .notes: notes]
            rows.append(CourseImportField.allCases.map { values[$0] ?? "" })
        }
        return rows
    }

    private static func unescape(_ text: String) throws -> String {
        var result = "", escaped = false
        for character in text {
            if escaped {
                switch character {
                case "n", "N": result.append("\n")
                case "\\", ",", ";": result.append(character)
                default: throw CourseImportFailure("ICS 文本转义无效。")
                }
                escaped = false
            } else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        guard !escaped else { throw CourseImportFailure("ICS 文本转义不完整。") }
        return result
    }
}
