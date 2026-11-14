import SwiftUI
import UIKit

struct CampusMapView: View {
    @State private var campus = 0
    var body: some View {
        VStack(spacing: 16) {
            Picker("校区", selection: $campus) { Text("东校区").tag(0); Text("西校区").tag(1) }.pickerStyle(.segmented).padding(.horizontal, 20)
            Text("双指缩放，拖动查看完整平面图").font(.caption).foregroundStyle(CampusTheme.muted)
            ZoomableCampusMap(imageName: campus == 0 ? "east-campus-plan" : "west-campus-plan").id(campus)
                .accessibilityLabel(campus == 0 ? "东校区平面图，可双指缩放" : "西校区平面图，可双指缩放")
        }.padding(.top, 12).background(CampusTheme.background).navigationTitle("校园平面图").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ZoomableCampusMap: UIViewRepresentable {
    let imageName: String
    func makeUIView(context: Context) -> MapScrollView {
        let scroll = MapScrollView()
        scroll.delegate = context.coordinator
        scroll.imageView.image = UIImage(named: imageName)
        return scroll
    }
    func updateUIView(_ uiView: MapScrollView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? MapScrollView)?.imageView }
    }
}

private final class MapScrollView: UIScrollView {
    let imageView = UIImageView()
    private var previousSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        maximumZoomScale = 5
        minimumZoomScale = 1
        bouncesZoom = true
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "校园平面图"
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize, bounds.width > 0, bounds.height > 0 else { return }
        previousSize = bounds.size
        setZoomScale(1, animated: false)
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
}
