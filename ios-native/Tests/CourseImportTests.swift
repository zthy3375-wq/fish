import XCTest
import zlib
@testable import Hanyuantong

/// Synthetic files only. None of these fixtures contain school/user data or require a network.
final class CourseImportTests: XCTestCase {
    private var semesterStart: Date { ScheduleMath.calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))! }
    private let header = "课程名称,星期,开始时间,结束时间,教学周"

    private func preview(_ csv: String, existing: [Course] = []) throws -> CourseImportPreview {
        let table = try CourseImportEngine.readCSV(Data(csv.utf8))
        return CourseImportEngine.preview(table, mapping: CourseImportEngine.guessMapping(table.headers),
                                          semesterStart: semesterStart, weekCount: 18, existing: existing)
    }
    private func calendar(_ properties: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:synthetic\r\n\(properties)\r\nEND:VEVENT\r\nEND:VCALENDAR"
    }
    private func ics(_ properties: String) throws -> CourseImportPreview {
        try CourseCalendarReader.preview(Data(calendar(properties).utf8), semesterStart: semesterStart, weekCount: 18, existing: [])
    }
    private let floating = "DTSTART:20260907T080000\r\nDTEND:20260907T093500\r\nSUMMARY:工程课"

    func testTemplateAndMappingDoNotWriteOrInferPeriods() throws {
        let result = try preview(CourseImportEngine.csvTemplate)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.courses[0].weeks, Array(1...18))
        XCTAssertEqual(result.courses[0].startPeriod, 1)
        XCTAssertEqual(result.courses[0].source, "personal")
        XCTAssertNil(result.courses[0].externalID)
        let noPeriods = try preview(header + "\n课程,星期三,10:00,11:35,2")
        XCTAssertNil(noPeriods.courses[0].startPeriod)
        XCTAssertTrue(noPeriods.warnings.joined().contains("未推测"))
    }
    func testCSVUTF8BOMQuotesEmbeddedNewlineAndCRLF() throws {
        let text = "\u{feff}" + header + ",备注\r\n\"课程,带逗号\",1,08:00,09:00,1,\"第一行\r\n第二行\"\"引号\"\"\"\r\n"
        let result = try preview(text)
        XCTAssertEqual(result.courses.first?.name, "课程,带逗号")
        XCTAssertEqual(result.courses.first?.notes, "第一行\r\n第二行\"引号\"")
        XCTAssertTrue(result.errors.isEmpty)
    }
    func testCSVRejectsInvalidUTF8MalformedQuotesAndRows() {
        XCTAssertThrowsError(try CourseImportEngine.readCSV(Data([0xff, 0xfe, 0xff])))
        for text in ["a,b\n1,2,3", "a,b\n\"unclosed", "a,b\na\"b,2", "a,b\n\"x\"junk,2", "a,a\n1,2", "a,\n1,2", "\n\n"] {
            XCTAssertThrowsError(try CourseImportEngine.readCSV(Data(text.utf8)), text)
        }
    }
    func testCSVSizeRowAndColumnBounds() {
        XCTAssertThrowsError(try CourseImportEngine.readCSV(Data(repeating: 32, count: CourseImportEngine.maximumBytes + 1)))
        XCTAssertThrowsError(try CourseImportEngine.readCSV(Data(("a\n" + String(repeating: "1\n", count: 3001)).utf8)))
        let columns = (1...51).map(String.init).joined(separator: ",")
        XCTAssertThrowsError(try CourseImportEngine.readCSV(Data(columns.utf8)))
    }
    func testMappingRequiresExplicitTimesAndCanMapUnknownHeaders() throws {
        let table = try CourseImportEngine.readCSV(Data("标题,几,起,止,周\n课程,2,08:00,09:00,1".utf8))
        let missing = CourseImportEngine.preview(table, mapping: [:], semesterStart: semesterStart)
        XCTAssertFalse(missing.canImport)
        XCTAssertTrue(missing.errors[0].contains("映射"))
        let valid = CourseImportEngine.preview(table, mapping: [.name: "标题", .day: "几", .start: "起", .end: "止", .weeks: "周"], semesterStart: semesterStart)
        XCTAssertTrue(valid.canImport)
    }
    func testInvalidRowsBlockWholePreview() throws {
        let result = try preview(header + "\n课程,1,08:00,09:00,1\n坏课程,1,09:00,08:00,1")
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertFalse(result.canImport)
        XCTAssertTrue(result.errors[0].contains("结束时间"))
    }
    func testWeekRangesAndOddEvenValidation() throws {
        XCTAssertEqual(try CourseImportEngine.parseWeeks("第1–4周,6、8", maximum: 18), [1, 2, 3, 4, 6, 8])
        for text in ["", "0", "1-19", "4-1", "1,,2", "1x", "1.5", "-1", "1-"] {
            XCTAssertThrowsError(try CourseImportEngine.parseWeeks(text, maximum: 18), text)
        }
        let result = try preview(header + ",单双周\n课程,1,08:00,09:00,1-6,单周")
        XCTAssertEqual(result.courses[0].weeks, [1, 3, 5])
        XCTAssertFalse(try preview(header + ",单双周\n课程,1,08:00,09:00,2,单周").canImport)
    }
    func testTimeWeekdayAndPeriodValidation() throws {
        for row in ["课程,8,08:00,09:00,1", "课程,1,8:00,09:00,1", "课程,1,08:00,24:00,1", "课程,1,08:00,09:60,1"] {
            XCTAssertFalse(try preview(header + "\n" + row).canImport)
        }
        for periods in ["1,", "2,1", "0,2", "1,25", "1.5,2"] {
            XCTAssertFalse(try preview(header + ",开始节次,结束节次\n课程,1,08:00,09:00,1," + periods).canImport)
        }
    }
    func testDuplicatesAgainstExistingAndWithinFileAreSkipped() throws {
        let csv = header + "\n课程,1,08:00,09:00,1\n课程,1,08:00,09:00,1"
        let result = try preview(csv)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.courses.count, 1)
        let duplicate = try preview(csv, existing: result.courses)
        XCTAssertEqual(duplicate.duplicates, 2)
        XCTAssertTrue(duplicate.courses.isEmpty)
    }
    func testSlotsMergeWeeksAndConflictsRemainVisible() throws {
        let csv = header + "\n课程,1,08:00,09:00,1\n课程,1,08:00,09:00,3\n课程,2,08:00,09:00,1\n冲突课,1,08:30,09:30,1"
        let result = try preview(csv)
        XCTAssertEqual(result.courses.count, 3)
        XCTAssertEqual(result.courses[0].weeks, [1, 3])
        XCTAssertFalse(result.issues.isEmpty)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertFalse(CourseImportEngine.overlaps(result.courses[0], Course(name: "接续", day: 1, start: "09:00", end: "10:00", weeks: [1])))
    }
    func testMarkupRemainsPlainText() throws {
        let result = try preview(header + "\n<img src=x onerror=alert(1)>,1,08:00,09:00,1")
        XCTAssertEqual(result.courses.first?.name, "<img src=x onerror=alert(1)>")
    }
    func testUnknownFormatsAndInvalidContextFail() {
        XCTAssertThrowsError(try CourseImportEngine.parse(name: "backup.json", data: Data(), semesterStart: semesterStart))
        XCTAssertThrowsError(try CourseImportEngine.parse(name: "a.csv", data: Data(header.utf8), semesterStart: semesterStart, weekCount: 0))
    }
    func testWeeklyICSExclusionsAndSlotGrouping() throws {
        let result = try ics(floating + "\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nEXDATE:20260914T080000")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.courses.count, 1)
        XCTAssertEqual(result.courses[0].weeks, [1, 3])
        XCTAssertNil(result.courses[0].startPeriod)
    }
    func testUTCICSConvertsToBeijingRegardlessOfDeviceZone() throws {
        let result = try ics("DTSTART:20260907T000000Z\r\nDTEND:20260907T013500Z\r\nSUMMARY:UTC课程")
        XCTAssertEqual(result.courses.first?.start, "08:00")
        XCTAssertEqual(result.courses.first?.end, "09:35")
        XCTAssertEqual(result.courses.first?.day, 1)
    }
    func testWeeklyByDayIntervalAndCountUseActualOccurrences() throws {
        let result = try ics(floating + "\r\nRRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=4;BYDAY=MO,WE;WKST=MO")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.courses.count, 2)
        XCTAssertEqual(result.courses.map(\.day).sorted(), [1, 3])
        XCTAssertTrue(result.courses.allSatisfy { $0.weeks == [1, 3] })
    }
    func testDailyUntilAllowsSecondPrecisionBoundary() throws {
        let result = try ics(floating + "\r\nRRULE:FREQ=DAILY;UNTIL=20260909T235959")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.courses.map(\.day).sorted(), [1, 2, 3])
    }
    func testRDatesFoldedLinesAndEscapedText() throws {
        let result = try ics(floating.replacingOccurrences(of: "SUMMARY:工程课", with: "SUMMARY:工程\r\n 课\\,实验") + "\r\nRDATE:20260914T080000,20260921T080000\r\nEXDATE:20260914T080000\r\nDESCRIPTION:第一行\\n第二行")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.courses.first?.name, "工程课,实验")
        XCTAssertEqual(result.courses.first?.weeks, [1, 3])
        XCTAssertEqual(result.courses.first?.notes, "第一行\n第二行")
    }
    func testAllDayCrossDayAndUnsupportedZoneAreRejected() throws {
        for properties in [
            "DTSTART;VALUE=DATE:20260907\r\nDTEND;VALUE=DATE:20260908\r\nSUMMARY:全天",
            "DTSTART:20260907T233000\r\nDTEND:20260908T003000\r\nSUMMARY:跨日",
            "DTSTART;TZID=America/New_York:20260907T080000\r\nDTEND;TZID=America/New_York:20260907T090000\r\nSUMMARY:外区",
            "DTSTART:20260230T080000\r\nDTEND:20260230T090000\r\nSUMMARY:无效日期",
            "DTSTART:20260907T080030\r\nDTEND:20260907T090000\r\nSUMMARY:秒级安排"
        ] { XCTAssertFalse(try ics(properties).errors.isEmpty) }
    }
    func testUnsupportedRecurrencesAndOverridesBlockImport() throws {
        for property in ["RRULE:FREQ=MONTHLY;COUNT=3", "RRULE:FREQ=WEEKLY;BYDAY=1MO", "RRULE:FREQ=WEEKLY;BYSETPOS=1", "RRULE:FREQ=WEEKLY;COUNT=2;UNTIL=20261001T000000", "RRULE:FREQ=WEEKLY;COUNT=0", "RECURRENCE-ID:20260907T080000", "DURATION:PT1H", "EXRULE:FREQ=WEEKLY"] {
            let result = try ics(floating + "\r\n" + property)
            XCTAssertFalse(result.canImport, property)
            XCTAssertTrue(result.courses.isEmpty, "No partially expanded event may leak after failure: " + property)
        }
    }
    func testICSExcludesOutsideSemesterAndCancelledEvents() throws {
        XCTAssertFalse(try ics("DTSTART:20250101T080000\r\nDTEND:20250101T090000\r\nSUMMARY:旧课").canImport)
        XCTAssertTrue(try ics(floating + "\r\nSTATUS:CANCELLED").courses.isEmpty)
    }
    func testICSEventCountAndRecurrenceBounds() throws {
        let events = String(repeating: "BEGIN:VEVENT\r\n\(floating)\r\nEND:VEVENT\r\n", count: 501)
        XCTAssertThrowsError(try CourseCalendarReader.preview(Data("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(events)END:VCALENDAR".utf8), semesterStart: semesterStart, weekCount: 18, existing: []))
        XCTAssertFalse(try ics(floating + "\r\nRRULE:FREQ=DAILY;COUNT=5001").canImport)
        XCTAssertThrowsError(try CourseCalendarReader.preview(Data("not ICS".utf8), semesterStart: semesterStart, weekCount: 18, existing: []))
        XCTAssertThrowsError(try CourseCalendarReader.preview(Data(calendar(floating).dropLast(10).utf8), semesterStart: semesterStart, weekCount: 18, existing: []))
    }
    func testRealStoredAndDeflatedXLSXArchives() throws {
        for compressed in [false, true] {
            let table = try CourseWorkbookReader.read(try workbook(compressed: compressed))
            let result = CourseImportEngine.preview(table, mapping: CourseImportEngine.guessMapping(table.headers), semesterStart: semesterStart)
            XCTAssertTrue(result.errors.isEmpty)
            XCTAssertEqual(result.courses.first?.name, "合成课程")
            XCTAssertEqual(result.courses.first?.day, 3)
            XCTAssertEqual(result.courses.first?.weeks, [2, 4, 6])
        }
    }
    func testXLSXSharedStringsAndSparseBlankCells() throws {
        var entries = workbookEntries()
        entries["xl/sharedStrings.xml"] = "<sst><si><r><t>合成</t></r><r><t>课程</t></r><rPh><t>不显示</t></rPh></si></sst>"
        entries["xl/worksheets/sheet1.xml"] = entries["xl/worksheets/sheet1.xml"]!.replacingOccurrences(of: "<c r=\"A2\" t=\"inlineStr\"><is><t>合成课程</t></is></c>", with: "<c r=\"A2\" t=\"s\"><v>0</v></c>")
        entries["xl/worksheets/sheet1.xml"] = entries["xl/worksheets/sheet1.xml"]!.replacingOccurrences(of: "</row><row r=\"2\">", with: "<c r=\"F1\" t=\"inlineStr\"><is><t>教师</t></is></c></row><row r=\"2\">")
        let table = try CourseWorkbookReader.read(zip(entries))
        XCTAssertEqual(table.rows[0][0], "合成课程")
        XCTAssertEqual(table.rows[0][5], "")
    }
    func testXLSXFormulaExternalRelationshipAndDTDAreRejected() throws {
        var entries = workbookEntries()
        entries["xl/worksheets/sheet1.xml"] = entries["xl/worksheets/sheet1.xml"]!.replacingOccurrences(of: "<sheetData>", with: "<sheetData><row r=\"0\"><c><f>1+1</f><v>2</v></c></row>")
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
        entries = workbookEntries()
        entries["xl/_rels/other.xml.rels"] = "<Relationships><Relationship Id=\"external\" Target=\"https://example.invalid/private\" TargetMode=\"External\" /></Relationships>"
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
        entries = workbookEntries()
        entries["xl/workbook.xml"] = "<!DOCTYPE x [<!ENTITY sample SYSTEM 'file:///synthetic'>]><workbook>&sample;</workbook>"
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
    }
    func testXLSXRejectsMultipleSheetsUnsafePathsAndMacros() throws {
        var entries = workbookEntries()
        entries["xl/workbook.xml"] = entries["xl/workbook.xml"]!.replacingOccurrences(of: "</sheets>", with: "<sheet name=\"另一张\" r:id=\"r2\"/></sheets>")
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
        entries = workbookEntries(); entries["../unsafe.xml"] = "x"
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
        entries = workbookEntries(); entries["xl/vbaProject.bin"] = "synthetic"
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
    }
    func testZIPIntegrityTruncationAndDeclaredExpansionLimit() throws {
        var bytes = try workbook()
        bytes[35] ^= 0x01
        XCTAssertThrowsError(try CourseWorkbookReader.read(bytes))
        XCTAssertThrowsError(try CourseWorkbookReader.read(Data(try workbook().dropLast(8))))
        var bomb = try zip(["xl/workbook.xml": "synthetic"])
        let central = bomb.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        replace32(&bomb, at: central + 24, value: 9 * 1024 * 1024)
        XCTAssertThrowsError(try CourseWorkbookReader.unzip(bomb))
    }
    func testCompressedBombChecksActualOutputNotOnlyMetadata() throws {
        var archive = try zip(["xl/workbook.xml": String(repeating: "x", count: 100000)], compressed: true)
        let central = archive.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        replace32(&archive, at: 22, value: 10)
        replace32(&archive, at: central + 24, value: 10)
        XCTAssertThrowsError(try CourseWorkbookReader.unzip(archive))
    }
    func testZIPStreamingDescriptorsAreSupported() throws {
        let bytes = try zip(workbookEntries(), compressed: true, descriptor: true)
        XCTAssertEqual(try CourseWorkbookReader.read(bytes).rows.count, 1)
    }
    func testXLSXDimensionAndInvalidCellReferencesFail() throws {
        var entries = workbookEntries()
        entries["xl/worksheets/sheet1.xml"] = entries["xl/worksheets/sheet1.xml"]!.replacingOccurrences(of: "<sheetData>", with: "<dimension ref=\"A1:AZ3002\"/><sheetData>")
        XCTAssertThrowsError(try CourseWorkbookReader.read(zip(entries)))
    }
    func testBoundedFileReadAndWrongExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((header + "\n课程,1,08:00,09:00,1").utf8).write(to: url)
        if case .table(let table) = try CourseImportEngine.read(from: url, semesterStart: semesterStart, weekCount: 18, existing: []) {
            XCTAssertEqual(table.rows.count, 1)
        } else { XCTFail("CSV must return mapping table") }
        try Data(repeating: 32, count: CourseImportEngine.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try CourseImportEngine.read(from: url, semesterStart: semesterStart, weekCount: 18, existing: []))
    }

    // Minimal but structurally real OOXML and ZIP writers used only for synthetic regressions.
    private func workbook(compressed: Bool = false) throws -> Data { try zip(workbookEntries(), compressed: compressed) }
    private func workbookEntries() -> [String: String] {
        let headers = ["课程名称", "星期", "开始时间", "结束时间", "教学周"]
        let values = ["合成课程", "三", "10:00", "11:35", "2,4,6"]
        func row(_ values: [String], number: Int) -> String {
            "<row r=\"\(number)\">" + values.enumerated().map { index, value in
                "<c r=\"\(String(UnicodeScalar(65 + index)!))\(number)\" t=\"inlineStr\"><is><t>\(value)</t></is></c>"
            }.joined() + "</row>"
        }
        return [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\" /></Types>",
            "xl/workbook.xml": "<workbook xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"课程\" sheetId=\"1\" r:id=\"r1\" /></sheets></workbook>",
            "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id=\"r1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\" /></Relationships>",
            "xl/worksheets/sheet1.xml": "<worksheet><sheetData>\(row(headers, number: 1))\(row(values, number: 2))</sheetData></worksheet>"
        ]
    }
    private func zip(_ entries: [String: String], compressed: Bool = false, descriptor: Bool = false) throws -> Data {
        var local = Data(), central = Data()
        func append16(_ value: Int, to data: inout Data) { data.append(UInt8(value & 255)); data.append(UInt8((value >> 8) & 255)) }
        func append32(_ value: UInt32, to data: inout Data) { for shift in stride(from: 0, through: 24, by: 8) { data.append(UInt8((value >> shift) & 255)) } }
        for name in entries.keys.sorted() {
            let raw = Data(entries[name]!.utf8), nameData = Data(name.utf8), body = compressed ? try deflated(raw) : raw
            let checksum = UInt32(raw.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) })
            let offset = local.count, flags = 0x800 | (descriptor ? 8 : 0), method = compressed ? 8 : 0
            append32(0x04034b50, to: &local); append16(20, to: &local); append16(flags, to: &local); append16(method, to: &local)
            append32(0, to: &local); append32(descriptor ? 0 : checksum, to: &local)
            append32(descriptor ? 0 : UInt32(body.count), to: &local); append32(descriptor ? 0 : UInt32(raw.count), to: &local)
            append16(nameData.count, to: &local); append16(0, to: &local); local.append(nameData); local.append(body)
            if descriptor { append32(0x08074b50, to: &local); append32(checksum, to: &local); append32(UInt32(body.count), to: &local); append32(UInt32(raw.count), to: &local) }
            append32(0x02014b50, to: &central); append16(20, to: &central); append16(20, to: &central)
            append16(flags, to: &central); append16(method, to: &central); append32(0, to: &central); append32(checksum, to: &central)
            append32(UInt32(body.count), to: &central); append32(UInt32(raw.count), to: &central)
            append16(nameData.count, to: &central); append16(0, to: &central); append16(0, to: &central); append16(0, to: &central)
            append16(0, to: &central); append32(0, to: &central); append32(UInt32(offset), to: &central); central.append(nameData)
        }
        let start = local.count
        local.append(central)
        append32(0x06054b50, to: &local); append16(0, to: &local); append16(0, to: &local)
        append16(entries.count, to: &local); append16(entries.count, to: &local)
        append32(UInt32(central.count), to: &local); append32(UInt32(start), to: &local); append16(0, to: &local)
        return local
    }
    private func deflated(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw CourseImportFailure("Synthetic fixture compression failed")
        }
        defer { deflateEnd(&stream) }
        var buffer = [UInt8](repeating: 0, count: Int(compressBound(uLong(data.count))))
        let status = data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(data.count)
            return buffer.withUnsafeMutableBytes { output in
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(output.count)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw CourseImportFailure("Synthetic fixture compression failed") }
        return Data(buffer.prefix(Int(stream.total_out)))
    }
    private func replace32(_ data: inout Data, at offset: Int, value: UInt32) {
        for index in 0..<4 { data[offset + index] = UInt8((value >> (8 * index)) & 255) }
    }
}
