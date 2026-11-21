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
    var interest: String? = nil
    var anonymous = false
    var requestId = UUID().uuidString
    var photos: [TreeholeDraftPhoto] = []
    var buddy: TreeholeBuddyDraft? = nil
    var poll: TreeholePollDraft? = nil
    var hasContent: Bool { !title.isEmpty || !body.isEmpty || !photos.isEmpty || poll != nil || buddy != nil }
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
    static func prepare(_ bytes: Data, avatar: Bool = false) throws -> TreeholeDraftPhoto {
        guard bytes.count <= 20_000_000, let original = UIImage(data: bytes), original.size.width > 0, original.size.height > 0 else { throw TreeholeError(code: "invalid_image") }
        let scale = min(1, 1600 / max(original.size.width, original.size.height))
        let side = min(original.size.width, original.size.height)
        let size = avatar ? CGSize(width: min(512, side), height: min(512, side)) : CGSize(width: max(1, (original.size.width * scale).rounded()), height: max(1, (original.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)); let ratio = size.width / side; let rect = avatar ? CGRect(x: (size.width - original.size.width * ratio) / 2, y: (size.height - original.size.height * ratio) / 2, width: original.size.width * ratio, height: original.size.height * ratio) : CGRect(origin: .zero, size: size); original.draw(in: rect) }
        for quality in [CGFloat(0.82), 0.7, 0.55, 0.4] {
            if let data = rendered.jpegData(compressionQuality: quality), data.count <= 1_200_000 { return TreeholeDraftPhoto(id: UUID().uuidString, data: data) }
        }
        throw TreeholeError(code: "image_too_large")
    }
}
enum TreeholeCategories {
    static let all: [(String, String)] = [("daily", "校园日常"), ("help", "提问求助"), ("study", "学习交流"), ("buddies", "兴趣搭子")]
    static let sections = [("daily", "校园日常"), ("entertainment", "兴趣娱乐"), ("buddies", "搭子广场"), ("treehole", "匿名树洞")]
    static let interests = [("games", "游戏"), ("anime", "动漫"), ("film", "影视"), ("music", "音乐"), ("photo", "摄影"), ("sports", "运动")]
    static func section(_ id: String) -> String { ["help", "study"].contains(id) ? "daily" : id }
    static func name(_ id: String?) -> String { (sections + all).first { $0.0 == id }?.1 ?? "校园日常" }
    static func topics(_ category:String,boards:Bool) -> [(String,String)] {
        if category == "study" { return boards ? [("graduate","考研")] : [] }
        if category != "entertainment" { return [] }
        return (boards ? [("reading","读书"),("fitness","健身")] : []) + interests
    }
    static func interestName(_ id: String?) -> String { (topics("study",boards:true) + topics("entertainment",boards:true)).first { $0.0 == id }?.1 ?? "" }
    static func filters(_ category: String, interest: String, enabled: Bool) -> [String: String] {
        guard enabled else { return ["category": category] }
        let allowedTopic = topics(category, boards: true).contains { $0.0 == interest }
        return ["section": section(category),
                "category": ["daily", "help", "study"].contains(category) ? category : "all",
                "interest": allowedTopic ? interest : ""]
    }
    static func description(_ id: String) -> String? {
        ["daily": "校园瞬间、日常分享，也可以在这里问个问题", "entertainment": "聊聊最近喜欢的游戏、作品和爱好", "buddies": "一起吃饭、运动、开黑，从一条帖子开始", "treehole": "把想说的话放在这里，本区统一匿名"][section(id)]
    }
}
