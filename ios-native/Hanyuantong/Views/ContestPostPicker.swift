import SwiftUI

struct ContestPostPicker: View {
    let api: TreeholeService
    var imageOnly = false
    let choose: (TreeholePost) -> Void
    @State private var posts: [TreeholePost] = []
    @State private var next: [String: String]?
    @State private var open = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(imageOnly ? "从我的图文帖选择封面" : "选择我的帖子参赛") { load() }.disabled(busy)
            if open {
                Text("选择自己的非匿名文字或图文帖子").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(posts) { post in
                            Button { choose(post); open = false } label: {
                                HStack(spacing: 10) {
                                    if let image = post.images?.first, let url = image.url.flatMap(URL.init(string:)) {
                                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }.frame(width: 48, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Text(post.title?.isEmpty == false ? post.title! : post.body.isEmpty ? "图片作品" : post.body).lineLimit(2).font(.subheadline).multilineTextAlignment(.leading)
                                    Spacer()
                                }.frame(minHeight: 48)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 300)
                if posts.isEmpty && !busy { Text("本页没有符合要求的帖子").font(.caption).foregroundStyle(.secondary) }
                if next != nil { Button("更多我的帖子") { load(more: true) }.disabled(busy) }
                Button("收起选择") { open = false }
            }
        }
    }
    private func load(more: Bool = false) {
        Task {
            guard !busy else { return }; busy = true; open = true; error = nil; defer { busy = false }
            do {
                var payload: [String: Any] = ["scope":"mine"]
                if more { for (key, value) in next ?? [:] { payload[key] = value } }
                let response = try await api.request("posts.list", payload)
                let rows = (response.posts ?? []).filter { !$0.anonymous && (!imageOnly || !($0.images ?? []).isEmpty) }
                posts = more ? posts + rows : rows; next = response.next
            } catch { self.error = (error as? TreeholeError)?.errorDescription ?? "帖子暂未加载，请重试" }
        }
    }
}
