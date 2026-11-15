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
    private var shown: [TreeholeImage] { Array(images.prefix(full ? 9 : 3)) }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: images.count == 1 ? 1 : 3), spacing: 5) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, image in
                Button { open(index) } label: {
                    TreeholeRemoteImage(postId: postId, image: image, api: api).frame(height: images.count == 1 ? 210 : 105).clipped()
                        .overlay { if !full && index == 2 && images.count > 3 { Color.black.opacity(0.4); Text("+\(images.count - 3)").font(.title2.bold()).foregroundStyle(.white) } }
                }.buttonStyle(.plain).accessibilityLabel("查看第 \(index + 1) 张图片")
            }
        }.frame(maxWidth: images.count == 1 ? 250 : .infinity, alignment: .leading)
    }
}
struct TreeholeRemoteImage: View {
    let postId: String
    let image: TreeholeImage
    let api: TreeholeService
    @State private var url: URL?
    @State private var attempted = false
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let value): value.resizable().scaledToFill()
            case .failure: Button { Task { await renew() } } label: { Label("重新加载", systemImage: "arrow.clockwise").font(.caption).frame(maxWidth: .infinity, maxHeight: .infinity).background(CampusTheme.background) }.task { if !attempted { await renew() } }
            default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(CampusTheme.background)
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
