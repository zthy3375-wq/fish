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
            Group {
                if images.count == 3 {
                    Color.clear.aspectRatio(1.6, contentMode: .fit).overlay {
                        GeometryReader { geometry in
                            let primary = (geometry.size.width - 6) * 0.6
                            let secondary = geometry.size.width - 6 - primary
                            let row = max(0, (geometry.size.height - 6) / 2)
                            HStack(spacing: 6) {
                                imageButton(0, image: images[0], ratio: primary / max(1, geometry.size.height), fit: false)
                                VStack(spacing: 6) {
                                    ForEach(1..<3, id: \.self) { index in
                                        imageButton(index, image: images[index], ratio: secondary / max(1, row), fit: false)
                                    }
                                }.frame(width: secondary)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: images.count == 2 || images.count == 4 ? 2 : 3), spacing: 6) {
                        ForEach(Array(images.prefix(9).enumerated()), id: \.element.id) { index, image in imageButton(index, image: image, ratio: 1, fit: false) }
                    }
                }
            }.overlay(alignment: .bottomTrailing) {
                Text("\(images.count) 张").font(.caption2).foregroundStyle(.white).padding(4)
                    .background(.black.opacity(0.55), in: Capsule()).padding(6).allowsHitTesting(false)
            }
        }
    }
    private func imageButton(_ index: Int, image: TreeholeImage, ratio: CGFloat, fit: Bool) -> some View {
        Button { open(index) } label: {
            Color.clear.aspectRatio(ratio, contentMode: .fit).overlay { TreeholeRemoteImage(postId: postId, image: image, api: api, fit: fit) }.clipped()
                .overlay(alignment: .bottomTrailing) { if !full && images.count == 1 && self.ratio < 0.6 { Text("长图").font(.system(size: 10)).padding(4).foregroundStyle(.white).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3)).padding(6) } }
                .background(TreeholeTheme.background).clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("\(full ? "查看图片" : "查看配图") \(index + 1)，共 \(images.count) 张")
    }
}
struct TreeholeRemoteImage: View {
    let postId: String
    let image: TreeholeImage
    let api: TreeholeService
    var fit = false
    @State private var url: URL?
    @State private var attempted = false
    @State private var renewalFailed = false
    private var unavailable: some View {
        Label("图片暂未加载", systemImage: "photo").font(.caption).frame(maxWidth: .infinity, maxHeight: .infinity).background(TreeholeTheme.background)
    }
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let value): if fit { value.resizable().scaledToFit() } else { value.resizable().scaledToFill() }
            case .failure: unavailable.task { if !attempted { await renew() } }
            case .empty where renewalFailed: unavailable
            default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(TreeholeTheme.background)
            }
        }.task(id: image) {
            attempted = false; renewalFailed = false
            url = image.url.flatMap(URL.init(string:))
            if url == nil { await renew() }
        }
    }
    private func renew() async {
        attempted = true
        let result = try? await api.request("media.url", ["postId": postId, "imageId": image.id])
        guard !Task.isCancelled else { return }
        if let value = result?.image?.url, let refreshed = URL(string: value) { url = refreshed }
        else { renewalFailed = true }
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
            if let bitmap {
                TreeholeZoomScroll(bitmap: bitmap)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("帖子大图").accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("community-zoomed-photo")
            } else if failed { Button("点击重新加载") { Task { await load() } }.foregroundStyle(.white) }
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
    func makeUIView(context: Context) -> CommunityPhotoScrollView { CommunityPhotoScrollView() }
    func updateUIView(_ view: CommunityPhotoScrollView, context: Context) { view.display(bitmap) }
}

final class CommunityPhotoScrollView: UIScrollView, UIScrollViewDelegate {
    private let photo = UIImageView()
    private var viewport = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        photo.contentMode = .scaleAspectFit
        addSubview(photo)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func display(_ bitmap: UIImage) {
        guard photo.image !== bitmap else { return }
        viewport = .zero
        minimumZoomScale = min(1, minimumZoomScale)
        maximumZoomScale = max(1, maximumZoomScale)
        setZoomScale(1, animated: false)
        photo.image = bitmap
        photo.frame = CGRect(origin: .zero, size: bitmap.size)
        contentSize = bitmap.size
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size != viewport, size.width > 0, size.height > 0, let image = photo.image,
              image.size.width > 0, image.size.height > 0 else { return }
        let relative = viewport == .zero ? 1 : zoomScale / minimumZoomScale
        let focus = viewport == .zero ? CGPoint(x: image.size.width / 2, y: image.size.height / 2) :
            CGPoint(x: (contentOffset.x + viewport.width / 2) / zoomScale,
                    y: (contentOffset.y + viewport.height / 2) / zoomScale)
        viewport = size
        let fit = min(size.width / image.size.width, size.height / image.size.height)
        maximumZoomScale = max(maximumZoomScale, fit * 4)
        minimumZoomScale = fit
        maximumZoomScale = fit * 4
        setZoomScale(fit * min(4, max(1, relative)), animated: false)
        centerPhoto()
        let x = max(-contentInset.left, min(focus.x * zoomScale - size.width / 2, contentSize.width - size.width + contentInset.right))
        let y = max(-contentInset.top, min(focus.y * zoomScale - size.height / 2, contentSize.height - size.height + contentInset.bottom))
        setContentOffset(CGPoint(x: x, y: y), animated: false)
    }

    private func centerPhoto() {
        let x = max(0, (bounds.width - photo.frame.width) / 2)
        let y = max(0, (bounds.height - photo.frame.height) / 2)
        let insets = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != insets { contentInset = insets }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }
    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.01 { setZoomScale(minimumZoomScale, animated: true); return }
        let point = gesture.location(in: photo)
        let target = minimumZoomScale * 2.5
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: true)
    }
}
