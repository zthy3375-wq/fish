import SwiftUI
import PhotosUI

struct TreeholeResponses: View {
    let post: TreeholePost
    var disabled = false
    let choose: (String) -> Void
    var kinds = ["same","hug","useful"]
    private let choices = [("useful", "有用", "lightbulb"), ("joy", "欢乐", "face.smiling"), ("hug", "抱抱", "heart")]
    var body: some View {
        let current = choices.first { $0.0 == post.myResponse }
        let total = choices.reduce(0) { $0 + (post.responseCounts?[$1.0] ?? 0) }
        let count = current.map { post.responseCounts?[$0.0] ?? 0 } ?? total
        return Menu {
            ForEach(choices, id: \.0) { key, label, icon in
                Button { choose(key) } label: {
                    Label(label, systemImage: post.myResponse == key ? "checkmark" : icon)
                }.disabled(!kinds.contains(key))
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: current?.2 ?? "face.smiling")
                Text(current?.1 ?? "回应")
                if count > 0 { Text(String(count)).monospacedDigit() }
            }.font(.subheadline).frame(minHeight: 44)
        }.foregroundStyle(current == nil ? TreeholeTheme.muted : TreeholeTheme.primary)
            .accessibilityLabel("选择回应").accessibilityValue(current?.1 ?? "回应").disabled(disabled)

    }
}
struct TreeholeAvatarEditor: View {
    @ObservedObject var tree: TreeholeStore
    @State private var selection: CampusPhotoItem?
    @State private var candidate: TreeholeDraftPhoto?
    @State private var confirmRemove = false
    var body: some View {
        VStack(spacing: 12) {
            if let photo = candidate, let image = UIImage(data: photo.data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 38)).accessibilityLabel("新头像预览")
                Text("预览头像 · 居中裁切").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("使用这张头像") { tree.perform { try await tree.setAvatar(photo); candidate = nil; selection = nil } }.buttonStyle(.borderedProminent)
                    Button("取消") { candidate = nil; selection = nil }.buttonStyle(.bordered)
                }
            } else {
                CampusPhotoPicker(selection: $selection, matching: .images) { Label("更换头像", systemImage: "person.crop.circle.badge.plus").frame(minHeight: 44) }
                if tree.user?.avatar != nil { Button("恢复默认头像") { confirmRemove = true }.frame(minHeight: 44) }
            }
            Text("公开昵称发言使用此头像，匿名发言仍使用匿名图标。").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).disabled(tree.busy)
        .onChange(of: selection) { item in
            guard let item else { return }; let identity = tree.user?.id
            tree.perform {
                guard let bytes = try await item.loadData(), identity == tree.user?.id else { return }
                candidate = try TreeholeDraftStore.prepare(bytes, avatar: true)
            }
        }
        .onChange(of: tree.user?.id) { _ in candidate = nil; selection = nil }
        .confirmationDialog("恢复默认头像？", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("恢复默认头像", role: .destructive) { tree.perform { try await tree.setAvatar(nil) } }
        }
    }
}

struct ReactionFeedback:ViewModifier {
    let active:Bool
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var pulse=false
    func body(content:Content)->some View {
        content.scaleEffect(pulse && !reduced ? 1.10 : 1)
            .animation(reduced ? nil : .easeOut(duration:0.15),value:pulse)
            .onChange(of:active) { value in pulse=value }
            .task(id:pulse) { guard pulse else {return}; do {try await Task.sleep(nanoseconds:150_000_000)} catch{return}; pulse=false }
    }
}
