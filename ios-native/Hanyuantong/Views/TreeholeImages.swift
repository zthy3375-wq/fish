import SwiftUI
import UIKit

struct TreeholeGallerySelection: Identifiable {
    let id = UUID()
    let postId: String
    let images: [TreeholeImage]
    let index: Int
}
struct TreeholeImageGrid: View {
    let postId: String
    let images: [TreeholeImage]
    let full: Bool
    let api: TreeholeService
    let open: (Int) -> Void
    @State private var page = 0
    private var ratio: CGFloat { guard let image = images.first, image.width > 0, image.height > 0 else { return 1 }; return CGFloat(image.width) / CGFloat(image.height) }
    var body: some View {
        if images.count == 1 {
            imageButton(0, image: images[0], ratio: full ? ratio : min(1.8, max(0.75, ratio)), fit: full)
                .frame(maxWidth: full || ratio >= 1.15 ? .infinity : ratio < 0.85 ? 240 : 300, alignment: .leading)
        } else if full {
            VStack(spacing: 8) {
                TabView(selection: $page) { ForEach(Array(images.enumerated()), id: \.element.id) { index, image in imageButton(index, image: image, ratio: 4 / 3, fit: true).tag(index) } }.tabViewStyle(.page(indexDisplayMode: .never)).aspectRatio(4 / 3, contentMode: .fit)
                HStack { Text("左右滑动查看"); Spacer(); Text("\(page + 1) / \(images.count)") }.font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: images.count == 2 || images.count == 4 ? 2 : 3), spacing: 5) { ForEach(Array(images.prefix(9).enumerated()), id: \.element.id) { index, image in imageButton(index, image: image, ratio: 1, fit: false) } }
        }
    }
    private func imageButton(_ index: Int, image: TreeholeImage, ratio: CGFloat, fit: Bool) -> some View {
        Button { open(index) } label: {
            Color.clear.aspectRatio(ratio, contentMode: .fit).overlay { TreeholeRemoteImage(postId: postId, image: image, api: api, fit: fit) }.clipped()
                .overlay(alignment: .bottomTrailing) { if !full && images.count == 1 && self.ratio < 0.6 { Text("长图").font(.system(size: 10)).padding(4).foregroundStyle(.white).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3)).padding(6) } }
                .background(TreeholeTheme.background).clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("查看第 \(index + 1) 张图片")
    }
}
struct TreeholeRemoteImage: View {
    let postId: String
    let image: TreeholeImage
    let api: TreeholeService
    var fit = false
    @State private var url: URL?
    @State private var attempted = false
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let value): if fit { value.resizable().scaledToFit() } else { value.resizable().scaledToFill() }
            case .failure: Button { Task { await renew() } } label: { Label("重新加载", systemImage: "arrow.clockwise").font(.caption).frame(maxWidth: .infinity, maxHeight: .infinity).background(TreeholeTheme.background) }.task { if !attempted { await renew() } }
            default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(TreeholeTheme.background)
            }
        }.task(id: image.id) { url = image.url.flatMap(URL.init(string:)); if url == nil { await renew() } }
    }
    private func renew() async {
        attempted = true
        if let result = try? await api.request("media.url", ["postId": postId, "imageId": image.id]), let value = result.image?.url { url = URL(string: value) }
    }
}
struct TreeholeGallery: View {
    let selection: TreeholeGallerySelection
    let api: TreeholeService
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    init(selection: TreeholeGallerySelection, api: TreeholeService) { self.selection = selection; self.api = api; _index = State(initialValue: selection.index) }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(selection.images.enumerated()), id: \.element.id) { offset, image in TreeholeZoomImage(postId: selection.postId, image: image, api: api).tag(offset) }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            HStack { Text("\(index + 1) / \(selection.images.count)"); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }.accessibilityLabel("关闭图片") }.font(.subheadline).foregroundStyle(.white).padding(20)
        }
    }
}
private struct TreeholeZoomImage: View {
    let postId: String
    let image: TreeholeImage
    let api: TreeholeService
    @State private var bitmap: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let bitmap { TreeholeZoomScroll(bitmap: bitmap) }
            else if failed { Button("点击重新加载") { Task { await load() } }.foregroundStyle(.white) }
            else { ProgressView().tint(.white) }
        }.task { await load() }
    }
    private func load() async {
        failed = false
        do {
            let result = try await api.request("media.url", ["postId": postId, "imageId": image.id])
            guard let value = result.image?.url, let url = URL(string: value) else { throw TreeholeError(code: "image_unavailable") }
            let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: config); defer { session.finishTasksAndInvalidate() }
            let (bytes, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, bytes.count <= 1_200_000, let loaded = UIImage(data: bytes) else { throw TreeholeError(code: "image_unavailable") }
            bitmap = loaded
        } catch { failed = true }
    }
}
private struct TreeholeZoomScroll: UIViewRepresentable {
    let bitmap: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4; scroll.delegate = context.coordinator
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        let image = UIImageView(image: bitmap); image.contentMode = .scaleAspectFit; image.isUserInteractionEnabled = true; scroll.addSubview(image); context.coordinator.image = image
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggle(_:))); doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.image?.image = bitmap
        if scroll.zoomScale == 1 { context.coordinator.image?.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size }
        DispatchQueue.main.async { if scroll.zoomScale == 1 { context.coordinator.image?.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size } }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var image: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
        @objc func toggle(_ gesture: UITapGestureRecognizer) { guard let scroll = gesture.view as? UIScrollView else { return }; scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : 2.5, animated: true) }
    }
}
