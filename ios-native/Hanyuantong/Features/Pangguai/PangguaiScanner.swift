import SwiftUI
import AVFoundation
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import Vision
import ImageIO
import CoreImage

/// All camera/image work is local. Decoded strings pass through deviceCode before any network request.
struct PangguaiScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    @State private var photo: PhotosPickerItem?
    @State private var torch = false
    @State private var status = "将机身二维码完整放入画面。屏幕码请关闭手电并避开反光。"
    @State private var resolved = false
    @State private var readingPhoto = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PGCameraView(torch: torch, paused: readingPhoto || resolved, onCode: accept, onError: { status = $0 })
                    .clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(CampusTheme.border))
                Text(status).font(.subheadline).multilineTextAlignment(.center).padding(.horizontal)
                HStack {
                    Button { torch.toggle() } label: { Label(torch ? "关闭手电":"手电筒", systemImage: torch ? "flashlight.off.fill":"flashlight.on.fill") }
                    Spacer()
                    PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) { Label("从照片识别", systemImage: "photo") }.disabled(readingPhoto)
                }.buttonStyle(.bordered).padding()
                Text("扫码只查询设备，不会扣款或启动。").font(.caption).foregroundStyle(CampusTheme.muted)
            }.padding().background(CampusTheme.background).navigationTitle("扫一扫").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { resolved = true; dismiss() } } }
                .task(id: photo) {
                    guard let photo else { return }
                    readingPhoto = true; defer { readingPhoto = false }
                    do {
                        guard let picked = try await photo.loadTransferable(type: PGBoundedPickedImage.self) else { throw PGFailure.qr }
                        let data = picked.data
                        try Task.checkCancellation()
                        let value = try await Task.detached(priority: .userInitiated) { try PGImageQRReader.read(data) }.value
                        try Task.checkCancellation(); if !resolved { accept(value) }
                    } catch { if !Task.isCancelled && !resolved { status = "图片未识别到有效设备码，请选择清晰近照或继续扫描。" } }
                }
                .onDisappear { resolved = true; torch = false }
        }
    }
    private func accept(_ code: String) {
        guard !resolved else { return }
        guard (try? PangguaiProtocol.deviceCode(code)) != nil else { status = PGFailure.qr.message; return }
        resolved = true; onCode(code); dismiss()
    }
}

private struct PGBoundedPickedImage: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size > 0, size <= 20_000_000 else { throw PGFailure.qr }
            let data = try Data(contentsOf: received.file, options: .mappedIfSafe)
            guard data.count <= 20_000_000 else { throw PGFailure.qr }
            return PGBoundedPickedImage(data: data)
        }
    }
}

enum PGImageQRReader {
    static func read(_ data: Data) throws -> String {
        guard data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache:false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 30000, height <= 30000,
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:1414, kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { throw PGFailure.qr }
        let original = CIImage(cgImage: cg), context = CIContext(options: [.cacheIntermediates:false])
        // Monochrome/inversion/softening help bright LCD codes without uploading or retaining pixels.
        let red = original.applyingFilter("CIColorMatrix", parameters: ["inputRVector":CIVector(x:1,y:0,z:0,w:0), "inputGVector":CIVector(x:1,y:0,z:0,w:0), "inputBVector":CIVector(x:1,y:0,z:0,w:0)])
        let variants = [original, red, red.applyingFilter("CIGaussianBlur", parameters:["inputRadius":0.7]).cropped(to: original.extent), original.applyingFilter("CIColorInvert")]
        for variant in variants {
            try Task.checkCancellation()
            guard let image = context.createCGImage(variant, from: original.extent) else { continue }
            let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let codes = Set((request.results ?? []).compactMap(\.payloadStringValue).filter { (try? PangguaiProtocol.deviceCode($0)) != nil })
            guard codes.count <= 1 else { throw PGFailure.qr }
            if let code = codes.first { return code }
        }
        throw PGFailure.qr
    }
}

private struct PGCameraView: UIViewControllerRepresentable {
    var torch: Bool; var paused: Bool; var onCode: (String) -> Void; var onError: (String) -> Void
    func makeUIViewController(context: Context) -> PGCameraController {
        let c = PGCameraController(); c.onCode = onCode; c.onError = onError; return c
    }
    func updateUIViewController(_ c: PGCameraController, context: Context) { c.onCode = onCode; c.onError = onError; c.setTorch(torch); c.setPaused(paused) }
    static func dismantleUIViewController(_ c: PGCameraController, coordinator: ()) { c.stop() }
}

private final class PGCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    let capture = AVCaptureSession()
    let queue = DispatchQueue(label: "org.handancampus.pangguai.camera")
    var onCode: (String) -> Void = { _ in }; var onError: (String) -> Void = { _ in }
    private var layer: AVCaptureVideoPreviewLayer?
    private var hasAppeared = false
    private var configured = false
    private var stopped = false
    private var paused = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: capture); preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview); layer = preview
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); hasAppeared = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in DispatchQueue.main.async { guard let self, self.hasAppeared else { return }; if allowed { self.configure() } else { self.onError("相机权限未开启，可从照片识别。") } } }
        default: onError("相机权限未开启。可从照片识别，或在系统设置中开启相机。")
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layer?.frame = view.bounds; layer?.connection?.videoOrientation = .portrait }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); hasAppeared = false; stop() }
    private func configure() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = false
            if self.configured { if !self.paused { self.capture.startRunning() }; return }
            self.capture.beginConfiguration(); defer { self.capture.commitConfiguration() }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device), self.capture.canAddInput(input) else {
                DispatchQueue.main.async { self.onError("相机暂不可用，可从照片识别。") }; return
            }
            self.capture.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard self.capture.canAddOutput(output) else { return }; self.capture.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
            self.configured = true
            self.queue.async { if !self.stopped && !self.paused { self.capture.startRunning() } }
        }
    }
    func setPaused(_ paused: Bool) {
        queue.async { [weak self] in
            guard let self else { return }; self.paused = paused
            if paused { self.capture.stopRunning() } else if self.configured && !self.stopped { self.capture.startRunning() }
        }
    }
    func setTorch(_ on: Bool) {
        queue.async { [weak self] in
            guard let self, !self.stopped, let device = (self.capture.inputs.first as? AVCaptureDeviceInput)?.device, device.hasTorch, device.isTorchAvailable else { return }
            do { try device.lockForConfiguration(); defer { device.unlockForConfiguration() }; device.torchMode = on ? .on:.off } catch { }
        }
    }
    func stop() { queue.async { [weak self] in guard let self else { return }; self.stopped = true; self.capture.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard hasAppeared else { return }
        let codes = Set(metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }.filter { (try? PangguaiProtocol.deviceCode($0)) != nil })
        if codes.count == 1, let code = codes.first { onCode(code) }
    }
}
