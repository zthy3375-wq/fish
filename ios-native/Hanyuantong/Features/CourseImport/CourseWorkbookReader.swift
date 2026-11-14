import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import zlib

/// No ZIP contents are written to disk, and no relationship or XML entity is fetched.
/// Every entry is inflated and CRC checked within fixed limits before workbook parsing.
enum CourseWorkbookReader {
    private static let entryLimit = 8 * 1024 * 1024
    private static let totalLimit = 20 * 1024 * 1024

    static func read(_ data: Data) throws -> CourseImportTable {
        try CourseImportEngine.checkSize(data)
        let archive = try unzip(data)
        guard let workbookData = archive["xl/workbook.xml"], let relationships = archive["xl/_rels/workbook.xml.rels"], archive["[Content_Types].xml"] != nil else {
            throw CourseImportFailure("压缩文件不含有效 Excel 工作簿。")
        }
        for (name, bytes) in archive {
            let lower = name.lowercased()
            guard !lower.hasSuffix(".bin"), !lower.contains("externallinks/"), !lower.contains("vbaproject"), !lower.contains("embeddings/") else {
                throw CourseImportFailure("不接受宏、外部链接或嵌入文件，请另存为纯数据 XLSX。")
            }
            if lower.hasSuffix(".rels") {
                let root = try XML.read(bytes)
                guard root.name == "Relationships" else { throw CourseImportFailure("Excel 关系文件无效。") }
                for relation in root.children {
                    guard relation.name == "Relationship", relation.attributes["TargetMode"]?.lowercased() != "external",
                          let target = relation.attributes["Target"], !target.contains(":"), !target.contains("\\") else {
                        throw CourseImportFailure("Excel 包含外部或无效关系，请另存为纯数据文件。")
                    }
                }
            }
        }
        let contentTypes = try XML.read(archive["[Content_Types].xml"]!)
        guard contentTypes.name == "Types", !contentTypes.children.contains(where: {
            let type = ($0.attributes["ContentType"] ?? "").lowercased()
            return type.contains("macroenabled") || type.contains("vbaproject") || type.contains("externallink")
        }) else { throw CourseImportFailure("不接受宏或外部链接工作簿，请另存为标准 XLSX。") }
        let workbook = try XML.read(workbookData)
        guard workbook.name == "workbook", workbook.descendants("externalReference").isEmpty else {
            throw CourseImportFailure("Excel 工作簿无效或含外部引用。")
        }
        let sheets = workbook.children.first(where: { $0.name == "sheets" })?.children.filter { $0.name == "sheet" } ?? []
        guard sheets.count == 1, let relationshipID = sheets[0].attributes["r:id"] else {
            throw CourseImportFailure("Excel 必须仅含一张课程数据表，请另存所需工作表。")
        }
        let relations = try XML.read(relationships).children
        let matching = relations.filter { $0.attributes["Id"] == relationshipID }
        guard matching.count == 1, let target = matching[0].attributes["Target"],
              matching[0].attributes["Type"]?.hasSuffix("/worksheet") == true else {
            throw CourseImportFailure("Excel 工作表关系无效。")
        }
        let sheetPath = try resolve(target)
        guard sheetPath.hasPrefix("xl/worksheets/"), let sheetData = archive[sheetPath] else {
            throw CourseImportFailure("Excel 课程工作表缺失。")
        }
        var strings: [String] = []
        if let bytes = archive["xl/sharedStrings.xml"] {
            let root = try XML.read(bytes)
            guard root.name == "sst", root.children.count <= 150050 else { throw CourseImportFailure("Excel 共享文本过多或无效。") }
            for item in root.children where item.name == "si" { strings.append(try richText(item)) }
        }
        let sheet = try XML.read(sheetData)
        guard sheet.name == "worksheet", sheet.descendants("f").isEmpty else {
            throw CourseImportFailure("不接受公式单元格，请先粘贴为纯文本。")
        }
        if let ref = sheet.children.first(where: { $0.name == "dimension" })?.attributes["ref"] {
            for part in ref.components(separatedBy: ":") { _ = try address(part) }
        }
        guard let sheetRows = sheet.children.first(where: { $0.name == "sheetData" })?.children else { throw CourseImportFailure("Excel 工作表为空。") }
        var rows: [[Int: String]] = [], seenRows = Set<Int>(), lastRow = 0, width = 0
        for row in sheetRows {
            guard row.name == "row" else { throw CourseImportFailure("Excel 行结构无效。") }
            let rowNumber: Int
            if let explicit = row.attributes["r"] {
                guard let parsed = Int(explicit) else { throw CourseImportFailure("Excel 行号无效。") }
                rowNumber = parsed
            } else { rowNumber = lastRow + 1 }
            guard (1...3001).contains(rowNumber), seenRows.insert(rowNumber).inserted, rowNumber > lastRow else {
                throw CourseImportFailure("表格超过 3000 行，或行号重复/无序。")
            }
            lastRow = rowNumber
            var cells: [Int: String] = [:], lastColumn = 0
            for cell in row.children {
                guard cell.name == "c" else { throw CourseImportFailure("Excel 单元格结构无效。") }
                let column: Int
                if let reference = cell.attributes["r"] {
                    let position = try address(reference)
                    guard position.row == rowNumber else { throw CourseImportFailure("Excel 单元格行号不匹配。") }
                    column = position.column
                } else { column = lastColumn + 1 }
                guard (1...50).contains(column), cells[column] == nil, column > lastColumn else {
                    throw CourseImportFailure("表格超过 50 列，或单元格编号重复/无序。")
                }
                lastColumn = column; width = max(width, column)
                let values = cell.children.filter { $0.name == "v" }
                guard values.count <= 1 else { throw CourseImportFailure("Excel 单元格含多个值。") }
                let raw = values.first?.text ?? ""
                let value: String
                switch cell.attributes["t"] ?? "n" {
                case "s":
                    guard let index = Int(raw), strings.indices.contains(index) else { throw CourseImportFailure("Excel 共享文本索引无效。") }
                    value = strings[index]
                case "inlineStr":
                    guard let inline = cell.children.first(where: { $0.name == "is" }) else { throw CourseImportFailure("Excel 内联文本缺失。") }
                    value = try richText(inline)
                case "n", "str", "d": value = raw
                case "b":
                    guard raw == "0" || raw == "1" else { throw CourseImportFailure("Excel 布尔值无效。") }
                    value = raw == "1" ? "true" : "false"
                case "e": throw CourseImportFailure("Excel 含错误单元格，请先修正。")
                default: throw CourseImportFailure("Excel 单元格类型不受支持，请粘贴为文本。")
                }
                guard value.utf8.count <= 65536 else { throw CourseImportFailure("Excel 单元格文本过长。") }
                cells[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cells.values.contains(where: { !$0.isEmpty }) { rows.append(cells) }
        }
        guard width > 0 else { throw CourseImportFailure("Excel 工作表为空。") }
        return try CourseImportEngine.table(rows.map { cells in (1...width).map { cells[$0] ?? "" } })
    }

    private static func address(_ value: String) throws -> (column: Int, row: Int) {
        guard value.range(of: #"^[A-Z]{1,2}[1-9][0-9]{0,3}$"#, options: .regularExpression) != nil else {
            throw CourseImportFailure("Excel 单元格范围无效或超过限制。")
        }
        let letters = value.prefix { $0.isLetter }
        let column = letters.utf8.reduce(0) { $0 * 26 + Int($1 - 64) }
        guard column <= 50, let row = Int(value.dropFirst(letters.count)), row <= 3001 else {
            throw CourseImportFailure("表格超过 3000 行或 50 列。")
        }
        return (column, row)
    }
    private static func resolve(_ target: String) throws -> String {
        guard !target.contains(".."), !target.contains("\\"), !target.contains(":"), !target.contains("%"), !target.contains("?"), !target.contains("#") else {
            throw CourseImportFailure("Excel 包含不安全工作表路径。")
        }
        return target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
    }
    private static func richText(_ node: XML.Node) throws -> String {
        var text = ""
        for child in node.children {
            if child.name == "t" { text += child.text }
            else if child.name == "r" { text += child.children.filter { $0.name == "t" }.map(\.text).joined() }
            // Phonetic guides (rPh/phoneticPr) are not the displayed cell text.
        }
        guard text.utf8.count <= 65536 else { throw CourseImportFailure("Excel 单元格文本过长。") }
        return text
    }

    private struct Entry {
        let name: String
        let flags: Int
        let method: Int
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
    }

    /// Central and local metadata must agree. ZIP64, encryption, symlinks and overlapping
    /// entries are rejected. Data descriptors are supported for normal streaming exporters.
    static func unzip(_ data: Data) throws -> [String: Data] {
        try CourseImportEngine.checkSize(data)
        let bytes = [UInt8](data)
        func u16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 2 <= bytes.count else { throw CourseImportFailure("Excel ZIP 数据不完整。") }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= bytes.count else { throw CourseImportFailure("Excel ZIP 数据不完整。") }
            return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 22, try u32(0) == 0x04034b50 else { throw CourseImportFailure("不是有效的 XLSX ZIP 文件。") }
        var end: Int?
        for position in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try u32(position) == 0x06054b50, position + 22 + (try u16(position + 20)) == bytes.count { end = position; break }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0 else { throw CourseImportFailure("Excel ZIP 目录缺失或不支持多卷压缩。") }
        let count = try u16(end + 10), centralSize = Int(try u32(end + 12)), centralStart = Int(try u32(end + 16))
        guard count > 0, count <= 500, try u16(end + 8) == count, centralStart + centralSize == end else {
            throw CourseImportFailure("Excel ZIP 条目过多、目录损坏或使用不支持的 ZIP64。")
        }
        var position = centralStart, entries: [Entry] = [], names = Set<String>(), total = 0
        for _ in 0..<count {
            guard try u32(position) == 0x02014b50 else { throw CourseImportFailure("Excel ZIP 目录无效。") }
            let flags = try u16(position + 8), method = try u16(position + 10)
            let compressed = Int(try u32(position + 20)), expanded = Int(try u32(position + 24))
            let nameLength = try u16(position + 28), extraLength = try u16(position + 30), commentLength = try u16(position + 32)
            let offset = Int(try u32(position + 42))
            let endOfEntry = position + 46 + nameLength + extraLength + commentLength
            guard endOfEntry <= end, nameLength > 0, flags & ~0x080e == 0, [0, 8].contains(method), try u16(position + 34) == 0,
                  expanded <= entryLimit, compressed <= data.count, offset < centralStart else {
                throw CourseImportFailure("Excel 解压内容过大，或含加密/不支持的 ZIP 条目。")
            }
            let attributes = try u32(position + 38)
            guard (attributes >> 16) & 0xf000 != 0xa000 else { throw CourseImportFailure("Excel 包含不安全链接条目。") }
            let nameBytes = Data(bytes[(position + 46)..<(position + 46 + nameLength)])
            guard let name = String(data: nameBytes, encoding: .utf8), !name.contains(".."), !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0"), names.insert(name.lowercased()).inserted else {
                throw CourseImportFailure("Excel 包含不安全或重复文件路径。")
            }
            total += expanded
            guard total <= totalLimit else { throw CourseImportFailure("Excel 解压内容过大，请拆分课表。") }
            // Parse extras, rejecting ZIP64 instead of relying on potentially truncated sizes.
            var extra = position + 46 + nameLength
            let extraEnd = extra + extraLength
            while extra < extraEnd {
                guard extra + 4 <= extraEnd else { throw CourseImportFailure("Excel ZIP 扩展字段损坏。") }
                let type = try u16(extra), length = try u16(extra + 2)
                guard type != 1, extra + 4 + length <= extraEnd else { throw CourseImportFailure("不支持 ZIP64 或损坏的 ZIP 扩展字段。") }
                extra += 4 + length
            }
            entries.append(Entry(name: name, flags: flags, method: method, crc: try u32(position + 16), compressed: compressed, expanded: expanded, offset: offset))
            position = endOfEntry
        }
        guard position == end else { throw CourseImportFailure("Excel ZIP 目录长度不匹配。") }
        var output: [String: Data] = [:], ranges: [Range<Int>] = [], actualTotal = 0
        for entry in entries {
            let local = entry.offset
            guard try u32(local) == 0x04034b50, try u16(local + 6) == entry.flags, try u16(local + 8) == entry.method else {
                throw CourseImportFailure("Excel ZIP 本地记录不匹配。")
            }
            let nameLength = try u16(local + 26), extraLength = try u16(local + 28)
            let start = local + 30 + nameLength + extraLength, finish = start + entry.compressed
            guard start <= centralStart, finish <= centralStart,
                  String(data: Data(bytes[(local + 30)..<(local + 30 + nameLength)]), encoding: .utf8) == entry.name else {
                throw CourseImportFailure("Excel ZIP 数据不完整或路径不匹配。")
            }
            var recordEnd = finish
            if entry.flags & 8 == 0 {
                guard try u32(local + 14) == entry.crc, Int(try u32(local + 18)) == entry.compressed, Int(try u32(local + 22)) == entry.expanded else {
                    throw CourseImportFailure("Excel ZIP 文件大小或校验信息不匹配。")
                }
            } else {
                let descriptor = (try u32(finish)) == 0x08074b50 ? finish + 4 : finish
                guard descriptor + 12 <= centralStart, try u32(descriptor) == entry.crc,
                      Int(try u32(descriptor + 4)) == entry.compressed, Int(try u32(descriptor + 8)) == entry.expanded else {
                    throw CourseImportFailure("Excel ZIP 数据描述不完整。")
                }
                recordEnd = descriptor + 12
            }
            let range = local..<recordEnd
            guard !ranges.contains(where: { $0.overlaps(range) }) else { throw CourseImportFailure("Excel ZIP 条目重叠。") }
            ranges.append(range)
            let compressed = Data(bytes[start..<finish])
            let expanded: Data
            if entry.method == 0 {
                guard entry.compressed == entry.expanded else { throw CourseImportFailure("Excel ZIP 存储大小不匹配。") }
                expanded = compressed
            } else { expanded = try inflate(compressed, expected: entry.expanded) }
            guard expanded.count == entry.expanded else { throw CourseImportFailure("Excel ZIP 解压长度不匹配。") }
            let checksum: uLong = expanded.withUnsafeBytes { raw in
                crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count))
            }
            guard UInt32(checksum) == entry.crc else { throw CourseImportFailure("Excel ZIP 校验失败，文件可能已损坏。") }
            actualTotal += expanded.count
            guard actualTotal <= totalLimit else { throw CourseImportFailure("Excel 解压内容过大。") }
            output[entry.name] = expanded
        }
        return output
    }

    private static func inflate(_ data: Data, expected: Int) throws -> Data {
        var stream = z_stream()
        let initialized = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initialized == Z_OK else { throw CourseImportFailure("无法初始化 Excel 解压。") }
        defer { inflateEnd(&stream) }
        var result = Data()
        try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var buffer = [UInt8](repeating: 0, count: 32768)
            while true {
                let previousInput = stream.avail_in
                let status: Int32 = buffer.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let produced = buffer.count - Int(stream.avail_out)
                guard result.count + produced <= min(entryLimit, expected) else { throw CourseImportFailure("Excel 解压内容过大或声明大小不匹配。") }
                result.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw CourseImportFailure("Excel 压缩数据末尾存在多余内容。") }
                    break
                }
                guard status == Z_OK, produced > 0 || stream.avail_in < previousInput else { throw CourseImportFailure("Excel 压缩数据损坏或不完整。") }
            }
        }
        return result
    }

    private final class XML: NSObject, XMLParserDelegate {
        final class Node {
            let name: String
            let attributes: [String: String]
            var children: [Node] = []
            var text = ""
            init(name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
            func descendants(_ name: String) -> [Node] {
                children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
            }
        }
        var root: Node?
        var stack: [Node] = []
        var failure: Error?
        var count = 0
        var textBytes = 0
        static func read(_ data: Data) throws -> Node {
            // OOXML uses UTF-8/UTF-16 XML. Restrict to UTF-8 so declaration scanning cannot
            // be bypassed by alternate encodings. No DTD/entity resolution is permitted.
            guard data.count <= entryLimit, let source = String(data: data, encoding: .utf8), !source.contains("\0"),
                  !source.uppercased().contains("<!DOCTYPE"), !source.uppercased().contains("<!ENTITY") else {
                throw CourseImportFailure("Excel XML 编码无效或含不允许的实体/DTD。")
            }
            let delegate = XML()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), delegate.failure == nil, let root = delegate.root, delegate.stack.isEmpty else {
                throw delegate.failure ?? CourseImportFailure("Excel XML 结构无效。")
            }
            return root
        }
        private func fail(_ parser: XMLParser) { failure = CourseImportFailure("Excel XML 超过安全限制或包含外部实体。"); parser.abortParsing() }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            count += 1
            guard count <= 500000, stack.count < 32, attributeDict.count <= 64 else { fail(parser); return }
            let node = Node(name: elementName.components(separatedBy: ":").last!, attributes: attributeDict)
            if let parent = stack.last { parent.children.append(node) }
            else if root == nil { root = node }
            else { fail(parser); return }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBytes += string.utf8.count
            guard textBytes <= entryLimit else { fail(parser); return }
            stack.last?.text += string
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let text = String(data: CDATABlock, encoding: .utf8) else { fail(parser); return }
            self.parser(parser, foundCharacters: text)
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { fail(parser); return nil }
    }
}
