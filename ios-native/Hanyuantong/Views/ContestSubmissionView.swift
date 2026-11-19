import SwiftUI
import PhotosUI

// Account/event/version scoped protected draft; retries keep the same immutable request.
struct NativeContestSubmissionDraft: Codable, Equatable {
    var title = "", body = "", requestID = UUID().uuidString
    var postID: String? = nil
    var linked = false, agreed = false, share = false, attempted = false
    var kept: [TreeholeImage] = []
    var photos: [TreeholeDraftPhoto] = []
    var version: Int? = nil
}
struct ContestSubmissionView: View {
    let api: TreeholeService
    let memberID: String
    let event: NativeContest
    let entry: NativeContestEntry?
    let submitted: (NativeContestEntry) -> Void
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = NativeContestSubmissionDraft()
    @State private var picked: [PhotosPickerItem] = []
    @State private var preview = false, busy = false, loaded = false, restoring = false, leaving = false
    @State private var message = "", error: String?
    @State private var saveTask: Task<Void, Never>?
    private var key: String { "contest-v2-" + memberID + "-" + event.id + "-" + (entry?.id ?? "new") }
    private var hasImages: Bool { event.formats.contains("image") || event.formats.contains("mixed") }
    private var hasText: Bool { event.formats.contains("text") || event.formats.contains("mixed") }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("返回比赛") { if preview { preview = false } else { leaving = true } }.disabled(busy)
            Text(entry == nil ? "我要参赛" : "编辑作品").font(.title.bold())
            Text(event.title).font(.subheadline).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            if restoring {
                Text("有一份保存在本机的草稿，继续编辑前请核对最新作品。")
                HStack { Button("恢复草稿") { restoring = false }; Button("使用当前作品") { reset(); restoring = false; persist() } }
            } else if loaded {
                if preview {
                    Text(draft.title).font(.title2.bold()); images
                    Text(draft.body).textSelection(.enabled)
                    Button(busy ? "正在确认…" : draft.attempted ? "重试并确认投稿" : "确认参赛") { send() }.buttonStyle(.borderedProminent).disabled(busy)
                    Button("返回编辑") { preview = false }.disabled(busy || draft.attempted)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("作品名称", text: $draft.title)
                        if hasText { TextEditor(text: $draft.body).frame(minHeight: 150).disabled(draft.linked).accessibilityLabel("作品内容") }
                        if hasImages {
                            images
                            if !draft.linked && draft.kept.count + draft.photos.count < 3 {
                                PhotosPicker(selection: $picked, maxSelectionCount: max(1, 3 - draft.kept.count - draft.photos.count), matching: .images) { Label("添加图片（最多3张）", systemImage: "photo") }
                                    .onChange(of: picked) { items in loadPhotos(items) }
                            }
                        }
                        DisclosureGroup("选择已有帖子或同步到社区") {
                            ContestPostPicker(api: api) { post in draft.postID = post.id; draft.linked = true; draft.body = post.body; draft.kept = post.images ?? []; draft.photos = []; if draft.title.isEmpty { draft.title = post.title?.isEmpty == false ? post.title! : String(post.body.prefix(40)) }; draft.share = false }
                            if draft.linked { Button("改为直接投稿") { draft.linked = false; draft.postID = nil; draft.kept = [] } }
                            else { Toggle("同时发布到社区", isOn: $draft.share) }
                        }
                        DisclosureGroup("参赛规则") { Text(event.rules).font(.caption) }
                        Toggle("我已阅读规则，作品符合投稿要求", isOn: $draft.agreed).font(.caption)
                    }.disabled(busy || draft.attempted)
                    if draft.attempted {
                        Text("上次提交结果尚未确认。重试会核对同一次投稿，不会重复发布。").font(.caption)
                        Button("重试并确认投稿") { send() }.disabled(busy)
                    } else {
                        Button("预览作品") { error = validate(); if error == nil { preview = true } }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                }
                Text(message).font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView("正在处理，请稍候…") }
            }
        }.task(id: key) { restore() }
            .onChange(of: draft) { _ in saveTask?.cancel(); saveTask = Task { try? await Task.sleep(nanoseconds: 250_000_000); if !Task.isCancelled { persist() } } }
            .onChange(of: scenePhase) { phase in if phase != .active { persist() } }
            .onDisappear { saveTask?.cancel(); persist() }
            .confirmationDialog("保存草稿并离开？", isPresented: $leaving, titleVisibility: .visible) {
                Button("保存并离开") { if persist() { close() } }
                Button("继续编辑", role: .cancel) {}
            } message: { Text("下次使用当前账号进入这场比赛，可以继续编辑。") }
    }
    @ViewBuilder private var images: some View {
        ForEach(draft.kept) { image in
            VStack { AsyncImage(url: image.url.flatMap(URL.init(string:))) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "photo") }.frame(maxHeight: 220)
                if !draft.linked && !preview { Button("移除已有图片") { draft.kept.removeAll { $0.id == image.id }; persist() }.disabled(busy || draft.attempted) }
            }
        }
        ForEach(draft.photos) { photo in
            VStack { if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220) }
                if !preview { Button("移除图片") { draft.photos.removeAll { $0.id == photo.id }; persist() }.disabled(busy || draft.attempted) }
                Text(photo.remote == nil ? "等待上传" : "已上传").font(.caption)
            }
        }
    }
    private func reset() { draft = NativeContestSubmissionDraft(); draft.title = entry?.title ?? ""; draft.body = entry?.body ?? ""; draft.postID = entry?.postId; draft.linked = entry?.linked == true; draft.kept = entry?.images ?? []; draft.version = entry?.version }
    private func restore() {
        reset(); defer { loaded = true }
        do { if var saved = try ProtectedStorage().read(key, as: NativeContestSubmissionDraft.self) { if saved.version != entry?.version { saved.version = entry?.version; saved.attempted = false; saved.requestID = UUID().uuidString }; draft = saved; restoring = true } }
        catch { error = "草稿暂时无法读取，可以继续编辑。" }
    }
    @discardableResult private func persist() -> Bool {
        guard loaded, !restoring else { return true }
        do { try ProtectedStorage().write(draft, name: key); message = "草稿已保存在本机"; return true }
        catch { self.error = "草稿保存失败，请保留当前页面重试"; return false }
    }
    private func validate() -> String? {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请为作品起个名字" }
        let count = draft.kept.count + draft.photos.count
        let kind = count == 0 ? "text" : draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "image" : "mixed"
        if !event.formats.contains(kind) || (count == 0 && draft.body.isEmpty) { return "请根据本场允许的类型填写文字或上传图片" }
        return draft.agreed ? nil : "请先阅读并同意参赛规则"
    }
    private func loadPhotos(_ items: [PhotosPickerItem]) { guard !busy else { return }; busy = true; Task { defer { busy = false }; do { for item in items.prefix(max(0, 3-draft.kept.count-draft.photos.count)) { if let data = try await item.loadTransferable(type: Data.self) { draft.photos.append(try TreeholeDraftStore.prepare(data)) } }; picked = []; persist() } catch { self.error = "图片读取失败，已保留其他图片，请重试" } } }
    private func send() {
        guard !busy else { return }; error = validate(); guard error == nil else { return }; busy = true
        Task { defer { busy = false }; do {
            for photo in draft.photos where photo.remote == nil {
                guard let image = try await api.request("media.upload", ["data":photo.data.base64EncodedString(), "requestId":photo.id]).image, let index = draft.photos.firstIndex(where: { $0.id == photo.id }) else { throw TreeholeError(code: "image_unavailable") }
                draft.photos[index].remote = image; persist()
            }
            draft.attempted = true; persist()
            let payload: [String: Any] = ["contestId":event.id, "entryId":entry?.id as Any? ?? NSNull(), "requestId":draft.requestID, "title":draft.title, "body":draft.body, "images":draft.kept.map(\.id) + draft.photos.compactMap { $0.remote?.id }, "postId":draft.postID as Any? ?? NSNull(), "agreed":draft.agreed, "share":draft.share, "linkPost":draft.linked, "expectedVersion":draft.version as Any? ?? NSNull()]
            guard let result = try await api.request("contests.submit", payload).entry else { throw TreeholeError(code: "invalid_response") }
            loaded = false; try? ProtectedStorage().remove(key); submitted(result)
        } catch { if let code = (error as? TreeholeError)?.code, ["contest_conflict","contest_format","invalid_request","contest_closed","image_unavailable","contest_entry_limit"].contains(code) { draft.attempted = false }; self.error = (error as? TreeholeError)?.errorDescription ?? "连接失败，内容已保留。重试将确认同一次投稿。"; persist() } }
    }
}
