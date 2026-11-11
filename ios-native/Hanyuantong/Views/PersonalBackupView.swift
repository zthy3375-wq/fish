import SwiftUI
import UniformTypeIdentifiers

struct PersonalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(backup: PersonalBackup) throws { data = try backup.encode() }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw PersonalBackup.Failure.invalid }
        _ = try PersonalBackup.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PersonalBackupView: View {
    @EnvironmentObject private var store: CampusStore
    @State private var document: PersonalBackupDocument?
    @State private var importing = false
    @State private var exporting = false
    @State private var pending: PersonalBackup?
    @State private var confirming = false
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Text("仅备份个人课程、待办和学期起始日期。学校课表、成绩、考试、账号及登录信息不会导出或被恢复操作覆盖。")
                Text("备份是未加密的 JSON 文件，可能包含个人安排，请妥善选择保存位置。仅支持本 iPhone 原生版格式，不兼容 Android 备份。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    do {
                        document = try PersonalBackupDocument(backup: store.makePersonalBackup())
                        exporting = true
                    } catch { resultMessage = error.localizedDescription }
                } label: { Label("导出个人备份", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("从 JSON 备份恢复", systemImage: "square.and.arrow.down") }
            }
            Section {
                Text("恢复将替换全部个人课程与待办，并更新学期起始日期。建议先导出当前备份。最多 2 MB、2000 门课程和 5000 条待办。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("个人备份与恢复")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "邯院通-iPhone-个人备份") { result in
            switch result {
            case .success: resultMessage = "个人备份已导出。请妥善保管该未加密文件。"
            case .failure(let error): resultMessage = error.localizedDescription
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                pending = try PersonalBackup.read(from: url)
                confirming = true
            } catch { pending = nil; resultMessage = error.localizedDescription }
        }
        .alert("替换个人数据？", isPresented: $confirming) {
            Button("取消", role: .cancel) { pending = nil }
            Button("替换并恢复", role: .destructive) {
                guard let backup = pending else { return }
                do {
                    try store.restorePersonalBackup(backup)
                    resultMessage = "已恢复个人课程、待办与学期起始日期。学校数据和登录状态未更改。"
                } catch { resultMessage = error.localizedDescription }
                pending = nil
            }
        } message: {
            Text("将用备份中的 \(pending?.courses.count ?? 0) 门个人课程与 \(pending?.tasks.count ?? 0) 条待办替换当前全部个人记录，并更新学期起始日期。此操作无法自动撤销。学校数据和登录状态不受影响。")
        }
        .alert("个人备份", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("好", role: .cancel) { resultMessage = nil }
        } message: { Text(resultMessage ?? "") }
    }
}
