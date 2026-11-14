import Foundation
import CoreFoundation
import CryptoKit

struct BackupCompatibilityFailure: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Parsing and preview are side-effect free. The caller must explicitly confirm and persist an import.
enum PersonalBackupImport {
    case native(PersonalBackup)
    case androidSchedule(AndroidScheduleImportPlan)
    case androidTasks(AndroidTaskImportPlan)

    static let maximumBytes = 5 * 1024 * 1024

    static func read(from url: URL) throws -> PersonalBackupImport {
        guard url.pathExtension.lowercased() == "json" else {
            throw BackupCompatibilityFailure("请选择 JSON 个人备份。不支持压缩包、学校或生活服务缓存。")
        }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true else { throw BackupCompatibilityFailure("请选择普通 JSON 文件。") }
        guard (info.fileSize ?? 0) <= maximumBytes else { throw BackupCompatibilityFailure("备份超过 5 MB。") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw BackupCompatibilityFailure("备份超过 5 MB。") }
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> PersonalBackupImport {
        guard !data.isEmpty, data.count <= maximumBytes else { throw BackupCompatibilityFailure("备份为空或超过 5 MB。") }
        // No decompression route: ZIP/GZIP cannot expand beyond a hidden memory limit.
        var scanner = BoundedBackupJSON(data: data)
        try scanner.validate()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupCompatibilityFailure("备份必须是 JSON 对象。")
        }
        if root["format"] != nil {
            return .androidSchedule(try AndroidScheduleImportPlan.parse(root))
        }
        if root["notificationsEnabled"] != nil {
            return .androidTasks(try AndroidTaskImportPlan.parse(root))
        }
        // Keep the original native decoder and its strict version/field/source validation.
        if root["semesterStart"] != nil { return .native(try PersonalBackup.decode(data)) }
        throw BackupCompatibilityFailure("无法识别备份。支持 iPhone 原生备份、Android 个人课表及待办备份（版本 1 或 2）。")
    }
}

enum BackupValue {
    static func object(_ value: Any?, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
        guard let object = value as? [String: Any], required.isSubset(of: Set(object.keys)),
              Set(object.keys).isSubset(of: required.union(optional)) else {
            // Do not reflect unknown keys or values: they may contain private material.
            throw BackupCompatibilityFailure("备份含缺失或未知字段，可能不是个人备份，未导入任何数据。")
        }
        return object
    }
    static func array(_ value: Any?, max: Int, min: Int = 0) throws -> [Any] {
        guard let value = value as? [Any], (min...max).contains(value.count) else {
            throw BackupCompatibilityFailure("备份列表格式或数量超出限制。")
        }
        return value
    }
    static func string(_ value: Any?, max: Int, required: Bool = false) throws -> String {
        guard let value = value as? String, value.utf16.count <= max,
              !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw BackupCompatibilityFailure("备份文本为空、过长或格式无效。")
        }
        return value
    }
    static func optionalString(_ value: Any?, max: Int) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return try string(value, max: max, required: true)
    }
    static func integer(_ value: Any?, _ range: ClosedRange<Int>) throws -> Int {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
            throw BackupCompatibilityFailure("备份数字格式无效。")
        }
        let number = value.doubleValue
        guard number.isFinite, number.rounded() == number, number >= Double(range.lowerBound), number <= Double(range.upperBound) else {
            throw BackupCompatibilityFailure("备份数字超出范围。")
        }
        return Int(number)
    }
    static func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw BackupCompatibilityFailure("备份开关格式无效。")
        }
        return value.boolValue
    }
    static func clock(_ value: Any?) throws -> String {
        let text = try string(value, max: 5)
        let bytes = Array(text.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }),
              Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48) < 24,
              Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48) < 60 else {
            throw BackupCompatibilityFailure("时间必须为有效的 HH:mm。")
        }
        return text
    }
    static func day(_ value: Any?, task: Bool = false) throws -> String {
        let text = try string(value, max: 10)
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(text.prefix(4)), (task ? 2000...2099 : 1900...2199).contains(year),
              let month = Int(text.dropFirst(5).prefix(2)), let day = Int(text.suffix(2)),
              let date = ScheduleMath.calendar.date(from: DateComponents(year: year, month: month, day: day)),
              dayString(date) == text else { throw BackupCompatibilityFailure("备份日期无效。") }
        return text
    }
    static func localDate(_ value: Any?) throws -> Date {
        let text = try string(value, max: 16)
        guard text.count == 16, text[text.index(text.startIndex, offsetBy: 10)] == "T" else {
            throw BackupCompatibilityFailure("待办时间必须为北京时间 YYYY-MM-DDTHH:mm。")
        }
        _ = try day(String(text.prefix(10)), task: true)
        _ = try clock(String(text.suffix(5)))
        let formatter = dateFormatter("yyyy-MM-dd'T'HH:mm")
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else {
            throw BackupCompatibilityFailure("待办北京时间无效。")
        }
        return date
    }
    static func optionalLocalDate(_ value: Any?) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        return try localDate(value)
    }
    static func timestamp(_ value: Any?) throws -> Date {
        let text = try string(value, max: 64, required: true)
        guard text.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-5][0-9](?:\.[0-9]{1,25})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])\z"#, options: .regularExpression) != nil else {
            throw BackupCompatibilityFailure("备份时间戳必须为完整的 ISO 8601 时间。")
        }
        // Keep native v1's complete 1900...2201 instant range, rather than narrowing it to task-plan dates.
        let dateText = String(text.prefix(10)), calendar = ScheduleMath.calendar
        guard let year = Int(dateText.prefix(4)), let month = Int(dateText.dropFirst(5).prefix(2)), let day = Int(dateText.suffix(2)),
              let calendarDate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              dayString(calendarDate) == dateText else { throw BackupCompatibilityFailure("备份时间戳日期无效。") }
        _ = try clock(String(text.dropFirst(11).prefix(5)))
        var wholeText = text, fraction = Decimal.zero
        if let dot = text.firstIndex(of: ".") {
            let start = text.index(after: dot)
            let digits = text[start...].prefix { $0 >= "0" && $0 <= "9" }
            let zoneStart = text.index(start, offsetBy: digits.count)
            wholeText = String(text[..<dot]) + String(text[zoneStart...])
            guard let parsed = Decimal(string: "0." + String(digits), locale: Locale(identifier: "en_US_POSIX")) else {
                throw BackupCompatibilityFailure("备份时间戳的小数秒无效。")
            }
            fraction = parsed
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        guard let whole = formatter.date(from: wholeText) else { throw BackupCompatibilityFailure("备份时间戳无效。") }
        // Foundation's fractional formatter rounds to milliseconds. Decimal addition in the Date
        // reference epoch avoids that rounding and avoids losing another bit by adding the Unix offset.
        let reference = Decimal(Int64(whole.timeIntervalSinceReferenceDate)) + fraction
        guard let seconds = Double(NSDecimalNumber(decimal: reference).stringValue) else { throw BackupCompatibilityFailure("备份时间戳无效。") }
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        guard (-2208988800...7289654400).contains(date.timeIntervalSince1970) else {
            throw BackupCompatibilityFailure("备份时间戳必须为有效 ISO 8601 时间。")
        }
        return date
    }
    static func optionalTimestamp(_ value: Any?) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        return try timestamp(value)
    }
    static func dayDate(_ value: String) -> Date { dateFormatter("yyyy-MM-dd").date(from: value)! }
    static func dayString(_ value: Date) -> String { dateFormatter("yyyy-MM-dd").string(from: value) }
    static func localString(_ value: Date) -> String { dateFormatter("yyyy-MM-dd'T'HH:mm").string(from: value) }
    static func timestampString(_ value: Date) -> String {
        let seconds = value.timeIntervalSinceReferenceDate
        guard seconds.isFinite, abs(seconds) < 10_000_000_000,
              let reference = Decimal(string: String(seconds), locale: Locale(identifier: "en_US_POSIX")) else { return "" }
        let whole = seconds.rounded(.down)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        let base = formatter.string(from: Date(timeIntervalSinceReferenceDate: whole))
        let fraction = reference - Decimal(Int64(whole))
        if fraction == .zero { return base }
        let decimalText = NSDecimalNumber(decimal: fraction).stringValue
        guard decimalText.hasPrefix("0."), decimalText.count <= 27, base.hasSuffix("Z") else { return "" }
        return String(base.dropLast()) + String(decimalText.dropFirst()) + "Z"
    }
    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = ScheduleMath.calendar; formatter.timeZone = ScheduleMath.calendar.timeZone
        formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }
    static func unique(_ ids: [String]) throws {
        guard Set(ids).count == ids.count else { throw BackupCompatibilityFailure("备份含重复编号，未导入。") }
    }
    /// Version-8 UUIDs provide repeatable native identities; original strings remain in the typed plan/model.
    static func stableID(_ value: String, namespace: String) -> UUID {
        if let uuid = UUID(uuidString: value) { return uuid }
        var bytes = Array(SHA256.hash(data: Data(("hanyuantong.backup/" + namespace + "/" + value).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let result = try encoder.encode(value)
        guard result.count <= PersonalBackupImport.maximumBytes else { throw BackupCompatibilityFailure("导出超过 5 MB，请减少记录。") }
        return result
    }
}

/// Check nesting, node count and duplicate keys before Foundation allocates an object tree.
/// Duplicate escaped keys are also rejected, rather than accepting a last-key-wins interpretation.
private struct BoundedBackupJSON {
    let bytes: [UInt8]
    var position = 0
    var nodes = 0
    init(data: Data) { bytes = Array(data) }
    mutating func validate() throws {
        try value(depth: 0); whitespace()
        guard position == bytes.count else { throw invalid() }
    }
    private func invalid() -> BackupCompatibilityFailure { BackupCompatibilityFailure("JSON 无效、字段重复、嵌套过深或记录过多。未导入任何数据。") }
    private mutating func whitespace() { while position < bytes.count && [9, 10, 13, 32].contains(bytes[position]) { position += 1 } }
    private mutating func take(_ byte: UInt8) -> Bool {
        whitespace(); guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1; return true
    }
    private mutating func value(depth: Int) throws {
        nodes += 1; guard nodes <= 250_000, depth <= 16 else { throw invalid() }
        whitespace(); guard position < bytes.count else { throw invalid() }
        switch bytes[position] {
        case 123:
            position += 1; var keys = Set<String>()
            if take(125) { return }
            repeat {
                whitespace(); let key = try string()
                guard keys.insert(key).inserted, keys.count <= 80, take(58) else { throw invalid() }
                try value(depth: depth + 1)
                if take(125) { return }
                guard take(44) else { throw invalid() }
            } while true
        case 91:
            position += 1
            if take(93) { return }
            repeat {
                try value(depth: depth + 1)
                if take(93) { return }
                guard take(44) else { throw invalid() }
            } while true
        case 34: _ = try string()
        default:
            let start = position
            while position < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) { position += 1 }
            guard position > start, position - start <= 64 else { throw invalid() }
            let token = Data(bytes[start..<position])
            guard (try? JSONSerialization.jsonObject(with: token, options: .fragmentsAllowed)) != nil else { throw invalid() }
        }
    }
    private mutating func string() throws -> String {
        guard position < bytes.count, bytes[position] == 34 else { throw invalid() }
        let start = position; position += 1
        while position < bytes.count {
            let byte = bytes[position]; position += 1
            guard position - start <= 32_768 else { throw invalid() }
            if byte == 92 { guard position < bytes.count else { throw invalid() }; position += 1 }
            else if byte == 34 {
                guard let text = try? JSONSerialization.jsonObject(with: Data(bytes[start..<position]), options: .fragmentsAllowed) as? String else { throw invalid() }
                return text
            }
        }
        throw invalid()
    }
}
