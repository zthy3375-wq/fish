import SwiftUI
import PhotosUI

struct TreeholeResponses: View {
    let post: TreeholePost
    var disabled = false
    let choose: (String) -> Void
    var kinds = ["same","hug","useful"]
    private var choices:[(String,String,String)] { ([("joy","欢乐","😄"),("same", "我也一样", "🤝"), ("hug", "抱抱", "🫂"), ("useful", "有用", "💡")]).filter { kinds.contains($0.0) } }
    var body: some View {
        CampusAdaptiveRow { HStack(spacing: 8) { buttons } } fallback: { VStack(alignment: .leading, spacing: 8) { buttons } }.accessibilityElement(children: .contain).accessibilityLabel("轻量回应").disabled(disabled)
    }
    @ViewBuilder private var buttons: some View {
        ForEach(choices, id: \.0) { key, label, icon in
            Button { choose(key) } label: {
                HStack(spacing: 4) { Text(icon).accessibilityHidden(true); Text(label); if let count = post.responseCounts?[key], count > 0 { Text("\(count)").monospacedDigit() } }
                    .font(.caption).padding(.horizontal, 10).frame(minHeight: 44)
                    .foregroundStyle(post.myResponse == key ? TreeholeTheme.primary : TreeholeTheme.muted)
                    .background(post.myResponse == key ? TreeholeTheme.tint : TreeholeTheme.background, in: Capsule())
                    .overlay(Capsule().stroke(post.myResponse == key ? TreeholeTheme.primary : .clear, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(post.myResponse == key ? "已选择" : "未选择")
        }
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
