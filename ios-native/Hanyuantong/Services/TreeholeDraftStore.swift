import Foundation
import Combine
import UIKit

struct TreeholeDraftPhoto: Codable, Equatable, Identifiable {
    let id: String
    let data: Data
    var remote: TreeholeImage?
}
struct TreeholeDraft: Codable, Equatable {
    var title = ""
    var body = ""
    var category = "daily"
    var anonymous = false
    var requestId = UUID().uuidString
    var photos: [TreeholeDraftPhoto] = []
    var hasContent: Bool { !title.isEmpty || !body.isEmpty || !photos.isEmpty }
}
@MainActor final class TreeholeDraftStore: ObservableObject {
    @Published var value = TreeholeDraft() { didSet { scheduleSave() } }
    @Published var message = ""
    private var member: String?
    private var storage: ProtectedStorage?
    private var pending: Task<Void, Never>?
    private var loading = false
    init(storage: ProtectedStorage? = nil) { self.storage = storage }
    func bind(_ id: String?) {
        guard id != member else { return }
        flush(); pending?.cancel(); loading = true; member = id; value = TreeholeDraft(); message = ""
        defer { loading = false }
        guard let id, UUID(uuidString: id) != nil else { return }
        do { let store = try storage ?? ProtectedStorage(); storage = store; value = try store.read("treehole-draft-" + id, as: TreeholeDraft.self) ?? TreeholeDraft() }
        catch { message = "草稿暂时无法读取" }
    }
    private func scheduleSave() {
        guard !loading, member != nil else { return }
        pending?.cancel(); message = "保存中…"
        pending = Task { try? await Task.sleep(nanoseconds: 250_000_000); guard !Task.isCancelled else { return }; flush() }
    }
    func flush() {
        guard !loading, let member, UUID(uuidString: member) != nil else { return }
        do { let store = try storage ?? ProtectedStorage(); storage = store
            if value.hasContent { try store.write(value, name: "treehole-draft-" + member); message = "草稿已保存" }
            else { try store.remove("treehole-draft-" + member); message = "" }
        } catch { message = "草稿保存失败，请保留当前页面" }
    }
    func clear() { pending?.cancel(); value = TreeholeDraft(); flush() }
    static func prepare(_ bytes: Data) throws -> TreeholeDraftPhoto {
        guard bytes.count <= 20_000_000, let original = UIImage(data: bytes), original.size.width > 0, original.size.height > 0 else { throw TreeholeError(code: "invalid_image") }
        let scale = min(1, 1600 / max(original.size.width, original.size.height))
        let size = CGSize(width: max(1, (original.size.width * scale).rounded()), height: max(1, (original.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)); original.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [CGFloat(0.82), 0.7, 0.55, 0.4] {
            if let data = rendered.jpegData(compressionQuality: quality), data.count <= 1_200_000 { return TreeholeDraftPhoto(id: UUID().uuidString, data: data) }
        }
        throw TreeholeError(code: "image_too_large")
    }
}
enum TreeholeCategories {
    static let all: [(String, String)] = [("daily", "校园日常"), ("help", "提问求助"), ("study", "学习交流"), ("buddies", "兴趣搭子")]
    static func name(_ id: String?) -> String { all.first { $0.0 == id }?.1 ?? "校园日常" }
}
